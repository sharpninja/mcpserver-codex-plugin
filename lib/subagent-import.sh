#!/usr/bin/env bash
# subagent-import.sh - Discover and import Codex subagent JSONL transcripts
# as first-class MCP session-log turns after a subagent task completes.
#
# Called after a subagent task completes to sweep up unimported subagent work.
#
# Reads:
#   CODEX_SESSION_FILE or CODEX_ROLLOUT_FILE - parent JSONL path
#   current-turn.yaml codexJsonlPath field (fallback)
#
# Exits 0 unconditionally; failures are logged to stderr and skipped.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    exit 0
fi

if ! type resolve_cache_dir >/dev/null 2>&1; then
    # shellcheck source=./resolve-cache-dir.sh
    source "$SCRIPT_PLUGIN_ROOT/lib/resolve-cache-dir.sh" 2>/dev/null || true
fi
CACHE_DIR="$(resolve_cache_dir 2>/dev/null || printf '%s' "$SCRIPT_PLUGIN_ROOT/cache")"

PARENT_JSONL="${CODEX_SESSION_FILE:-${CODEX_ROLLOUT_FILE:-}}"
if [ -z "$PARENT_JSONL" ] && [ -f "$CACHE_DIR/current-turn.yaml" ]; then
    PARENT_JSONL="$(grep '^codexJsonlPath:' "$CACHE_DIR/current-turn.yaml" 2>/dev/null | head -1 | sed 's/^codexJsonlPath:[[:space:]]*//' | tr -d '"' || true)"
fi

if [ -z "$PARENT_JSONL" ] || [ ! -f "$PARENT_JSONL" ]; then
    exit 0
fi

SESSION_ID="$(grep '^sessionId:' "$CACHE_DIR/session-state.yaml" 2>/dev/null | head -1 | sed 's/^sessionId:[[:space:]]*//' || true)"
if [ -z "$SESSION_ID" ]; then
    exit 0
fi

PARENT_TURN_ID="$(grep '^turnRequestId:' "$CACHE_DIR/current-turn.yaml" 2>/dev/null | head -1 | sed 's/^turnRequestId:[[:space:]]*//' || true)"

if ! type repl_invoke >/dev/null 2>&1; then
    # shellcheck source=./repl-invoke.sh
    source "$SCRIPT_PLUGIN_ROOT/lib/repl-invoke.sh" 2>/dev/null || true
fi

SUBAGENTS_JSON="$(node "${SCRIPT_PLUGIN_ROOT}/lib/codex-jsonl.js" subagents "$PARENT_JSONL" 2>/dev/null || true)"
if [ -z "$SUBAGENTS_JSON" ] || [ "$SUBAGENTS_JSON" = "[]" ]; then
    exit 0
fi

IMPORTED_TRACKER="$CACHE_DIR/subagent-imported.txt"
touch "$IMPORTED_TRACKER" 2>/dev/null || true

echo "$SUBAGENTS_JSON" | node -e "
const data = require('fs').readFileSync(0,'utf8').trim();
let subs = [];
try { subs = JSON.parse(data); } catch {}
for (const sub of subs) {
  process.stdout.write(sub.path + '\t' + (sub.agentNickname || '') + '\t' + (sub.sessionId || '') + '\n');
}
" 2>/dev/null | while IFS=$'\t' read -r SUBAGENT_PATH NICKNAME SUBAGENT_SESSION_ID; do
    [ -z "$SUBAGENT_PATH" ] || [ ! -f "$SUBAGENT_PATH" ] && continue

    IMPORT_KEY="${SUBAGENT_SESSION_ID:-${SUBAGENT_PATH}}"
    if grep -qxF "$IMPORT_KEY" "$IMPORTED_TRACKER" 2>/dev/null; then
        continue
    fi

    IMPORT_LINES="$(node "${SCRIPT_PLUGIN_ROOT}/lib/codex-jsonl.js" import "$SUBAGENT_PATH" "$SESSION_ID" "$PARENT_TURN_ID" 2>/dev/null || true)"
    [ -z "$IMPORT_LINES" ] && continue

    SUCCESS=0
    while IFS=$'\t' read -r METHOD PARAMS_B64 LABEL; do
        [ -z "$METHOD" ] || [ -z "$PARAMS_B64" ] && continue
        PARAMS="$(printf '%s' "$PARAMS_B64" | base64 --decode 2>/dev/null || true)"
        [ -z "$PARAMS" ] && continue
        if type repl_invoke >/dev/null 2>&1; then
            if repl_invoke "$METHOD" "$PARAMS" >/dev/null 2>&1; then
                SUCCESS=1
            fi
        fi
    done <<< "$IMPORT_LINES"

    if [ "$SUCCESS" = "1" ] && [ -n "$PARENT_TURN_ID" ] && type repl_invoke >/dev/null 2>&1; then
        NICK_LABEL="${NICKNAME:-subagent}"
        APPEND_PARAMS="actions:
  - order: 99
    type: session_log
    status: completed
    description: Subagent ${NICK_LABEL} transcript imported as MCP session-log turns: ${SUBAGENT_PATH}
    filePath: ${SUBAGENT_PATH}"
        repl_invoke "workflow.sessionlog.appendActions" "$APPEND_PARAMS" >/dev/null 2>&1 || true
    fi

    printf '%s\n' "$IMPORT_KEY" >> "$IMPORTED_TRACKER"
done

exit 0
