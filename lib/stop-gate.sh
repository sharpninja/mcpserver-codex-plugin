#!/usr/bin/env bash
# stop-gate.sh — Stop hook for the McpServer Claude Code plugin.
#
# Runs when Claude is about to finalize its response. Verifies that the
# active session log turn (opened by user-prompt-submit.sh) was completed
# with actions recorded. If not, blocks Stop and returns a reason so Claude
# continues and fulfills the protocol.
#
# Additional gate: if the turn cache marks lastBuildStatus=failed after a
# code edit in this turn, Stop is blocked until a successful build is recorded
# OR the agent explicitly sets an "accepted-failure" flag.
#
# Input (stdin): Claude Code Stop payload.
# Output (stdout): JSON. When blocking returns {"decision":"block","reason":"..."}.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CACHE_DIR="${PLUGIN_ROOT_OVERRIDE:-$CODEX_PLUGIN_ROOT}/cache"
TURN_FILE="$CACHE_DIR/current-turn.yaml"

# Read stdin (may be empty) so Claude Code doesn't complain about an unread pipe.
cat >/dev/null 2>&1 || true

# Avoid re-prompting loops: if Claude Code already set stop_hook_active=true on
# a previous block, let this Stop through.
STOP_HOOK_ACTIVE="${CLAUDE_STOP_HOOK_ACTIVE:-false}"
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"Stop","status":"already-reprompted"}}\n'
    exit 0
fi

# No turn file = no gate (e.g. MCP was unavailable; no enforcement possible).
if [ ! -f "$TURN_FILE" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"Stop","status":"no-turn"}}\n'
    exit 0
fi

TURN_STATUS="$(grep '^status:' "$TURN_FILE" 2>/dev/null | head -1 | sed 's/^status:[[:space:]]*//')"
TURN_ID="$(grep '^turnRequestId:' "$TURN_FILE" 2>/dev/null | head -1 | sed 's/^turnRequestId:[[:space:]]*//')"
BUILD_STATUS="$(grep '^lastBuildStatus:' "$TURN_FILE" 2>/dev/null | head -1 | sed 's/^lastBuildStatus:[[:space:]]*//')"
CODE_EDITS="$(grep '^codeEdits:' "$TURN_FILE" 2>/dev/null | head -1 | sed 's/^codeEdits:[[:space:]]*//')"
CODE_EDITS="${CODE_EDITS:-0}"

# Gate 1 — turn not completed.
# Self-heal: agents may not be able to reach workflow.sessionlog.* (not
# registered in the MCP tool surface); auto-complete the turn here so Stop
# is not wedged. Fall through to the explicit block only if self-heal fails.
if [ "$TURN_STATUS" = "in_progress" ]; then
    if [ -f "$CODEX_PLUGIN_ROOT/lib/repl-invoke.sh" ]; then
        # shellcheck source=./repl-invoke.sh
        source "$CODEX_PLUGIN_ROOT/lib/repl-invoke.sh" 2>/dev/null || true
    fi
    if type _repl_workflow_complete_turn >/dev/null 2>&1; then
        AUTO_PARAMS="response: |
    Auto-closed by stop-gate.sh (turn self-heal). The agent could not invoke workflow.sessionlog.* directly; the hook now finalizes the turn when the response finishes."
        _repl_workflow_complete_turn "$AUTO_PARAMS" >/dev/null 2>&1 || true
        TURN_STATUS="$(grep '^status:' "$TURN_FILE" 2>/dev/null | head -1 | sed 's/^status:[[:space:]]*//')"
    fi
    if [ "$TURN_STATUS" = "in_progress" ]; then
        REASON="Session log turn ${TURN_ID} could not be auto-closed. Check plugin/lib/repl-invoke.sh or MCP server availability."
        printf '{"decision":"block","reason":"%s"}\n' "$REASON"
        exit 0
    fi
fi

# Gate 2 — build broken after a code edit.
if [ "$CODE_EDITS" -gt 0 ] && [ "$BUILD_STATUS" = "failed" ]; then
    REASON="Last build in this turn failed after ${CODE_EDITS} code edit(s). Fix the build errors before claiming done, or explicitly accept failure by writing cache/turn-accept-failure.marker."
    if [ -f "$CACHE_DIR/turn-accept-failure.marker" ]; then
        rm -f "$CACHE_DIR/turn-accept-failure.marker"
    else
        printf '{"decision":"block","reason":"%s"}\n' "$REASON"
        exit 0
    fi
fi

# All gates passed.
printf '{"hookSpecificOutput":{"hookEventName":"Stop","status":"passed","turnRequestId":"%s"}}\n' "$TURN_ID"
exit 0
