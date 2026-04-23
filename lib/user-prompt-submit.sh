#!/usr/bin/env bash
# user-prompt-submit.sh — UserPromptSubmit hook for the McpServer Codex plugin.
#
# Runs on every user prompt. Auto-opens a session log turn via
# workflow.sessionlog.beginTurn so agents cannot skip the Per-User-Message
# protocol required by AGENTS-README-FIRST.yaml. Writes the active turn's
# requestId to cache/current-turn.yaml so the Stop hook can verify the turn
# was completed before the response finalizes.
#
# Input (stdin): Codex UserPromptSubmit payload as JSON with at least:
#   { "prompt": "<user message>", "session_id": "...", ... }
#
# Output (stdout): JSON with optional additionalContext. Exits 0 unconditionally
# so prompt processing never blocks on MCP issues (graceful degradation).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CACHE_DIR="${PLUGIN_ROOT_OVERRIDE:-$CODEX_PLUGIN_ROOT}/cache"

# Source libraries
if ! type repl_invoke >/dev/null 2>&1; then
    # shellcheck source=../../lib/repl-invoke.sh
    source "$CODEX_PLUGIN_ROOT/lib/repl-invoke.sh" 2>/dev/null || true
fi

# Read stdin into PAYLOAD (may be empty)
PAYLOAD="$(cat 2>/dev/null || true)"

# Extract the user prompt text. Prefer jq when available; fall back to grep/sed.
extract_prompt() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$PAYLOAD" | jq -r '.prompt // empty' 2>/dev/null
    else
        # Rough fallback — assumes no escaped quotes inside the prompt.
        printf '%s' "$PAYLOAD" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -1
    fi
}

USER_PROMPT="$(extract_prompt)"

# Bootstrap the local cache on demand so the wrapper is self-contained.
if [ ! -f "$CACHE_DIR/session-state.yaml" ] || [ -z "$(grep '^sessionId:' "$CACHE_DIR/session-state.yaml" 2>/dev/null | head -1)" ]; then
    if [ -f "$CODEX_PLUGIN_ROOT/lib/session-start.sh" ]; then
        MCP_SESSION_AGENT="${MCP_SESSION_AGENT:-Codex}" \
        MCP_SESSION_MODEL="${MCP_SESSION_MODEL:-codex}" \
            bash "$CODEX_PLUGIN_ROOT/lib/session-start.sh" "$PWD" >/dev/null 2>&1 || true
    fi
fi

# If no MCP session established, short-circuit. Codex can still respond.
if [ ! -f "$CACHE_DIR/session-state.yaml" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","status":"no-session"}}\n'
    exit 0
fi

SESSION_STATUS="$(grep '^status:' "$CACHE_DIR/session-state.yaml" 2>/dev/null | head -1 | sed 's/^status:[[:space:]]*//')"
if [ "$SESSION_STATUS" != "verified" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","status":"%s"}}\n' "$SESSION_STATUS"
    exit 0
fi

# Build a deterministic turn requestId
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RAND_SUFFIX="$(printf '%04x' $RANDOM)"
TURN_REQUEST_ID="req-${TIMESTAMP}-prompt-${RAND_SUFFIX}"

# Derive a short queryTitle from the first line of the prompt (max 60 chars)
QUERY_TITLE="$(printf '%s' "$USER_PROMPT" | head -1 | cut -c1-60)"
[ -z "$QUERY_TITLE" ] && QUERY_TITLE="User prompt"

# Escape the prompt for YAML embedding (preserve multi-line content via literal block)
QUERY_TEXT_BLOCK="$(printf '%s' "$USER_PROMPT" | sed 's/^/    /')"

TURN_PARAMS="requestId: ${TURN_REQUEST_ID}
queryTitle: ${QUERY_TITLE}
queryText: |
${QUERY_TEXT_BLOCK}"

# Open the turn. Graceful fallback to cache_write if REPL unavailable.
if type repl_invoke >/dev/null 2>&1; then
    if ! repl_invoke "workflow.sessionlog.beginTurn" "$TURN_PARAMS" >/dev/null 2>&1; then
        if type cache_write >/dev/null 2>&1; then
            cache_write "workflow.sessionlog.beginTurn" "$TURN_PARAMS" >/dev/null 2>&1 || true
        fi
    fi
fi

# Record the active turn so Stop hook can verify completion.
mkdir -p "$CACHE_DIR"
cat > "$CACHE_DIR/current-turn.yaml" <<EOF
turnRequestId: ${TURN_REQUEST_ID}
queryTitle: ${QUERY_TITLE}
openedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
status: in_progress
codeEdits: 0
lastBuildStatus: unknown
queryText: |
${QUERY_TEXT_BLOCK}
EOF

# Escape arbitrary text for JSON string embedding without depending on jq.
json_escape() {
    awk '
        BEGIN { ORS = "" }
        {
            gsub(/\\/, "\\\\")
            gsub(/"/, "\\\"")
            gsub(/\r/, "\\r")
            gsub(/\t/, "\\t")
            if (NR > 1) {
                printf "\\n"
            }
            printf "%s", $0
        }
    ' <<<"$1"
}

# Inject a per-turn reminder into the agent's context so it sees the
# exact contract that applies to this turn. Prioritize MCP continuity and
# attached-device guidance first; keep verification reminders secondary.
REMINDER="$(cat <<EOF
A session log turn is active. Use McpServer as the default source of task continuity:
1. Prefer session/task state and recent checkpoints over asking the user for context.
2. Use TODO and requirements tools only as needed.
3. For attached Android validation, use adb_step for screenshot -> inspect -> act -> screenshot loops.
4. After meaningful progress or a failed validation cycle, record/update the session log.
5. Run code-verify.sh after source edits and stop-gate.sh before the final response.
EOF
)"

REMINDER_JSON="$(json_escape "$REMINDER")"

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","status":"turn-opened","turnRequestId":"%s","additionalContext":"%s"}}\n' \
    "$TURN_REQUEST_ID" \
    "$REMINDER_JSON"
exit 0
