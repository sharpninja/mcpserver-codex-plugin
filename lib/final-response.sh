#!/usr/bin/env bash
# final-response.sh — Complete the active MCP session-log turn with rich fields.
#
# Reads the Codex JSONL transcript for the current session (if available) and
# extracts interpretation, processingDialog, actions, filesModified, contextList,
# blockers, designDecisions, and requirementsDiscovered before calling completeTurn.
#
# Usage:
#   final-response.sh [<response-text>]
#   echo "<response>" | final-response.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

response="${1:-}"
if [ -z "$response" ] && [ ! -t 0 ]; then
    response="$(cat 2>/dev/null || true)"
fi
if [ -z "$response" ]; then
    response="Turn completed."
fi

# Try to locate the Codex JSONL for the current session and turn.
# The path may be stored in current-turn.yaml (written by the prompt-submit
# integration) or in environment variables set by the Codex CLI.
CODEX_JSONL_PATH="${CODEX_SESSION_FILE:-${CODEX_ROLLOUT_FILE:-}}"

if [ -z "$CODEX_JSONL_PATH" ] && command -v node >/dev/null 2>&1; then
    # Try to read from the scoped current-turn.yaml via cache-scope.sh
    if ! type cache_scope_init >/dev/null 2>&1; then
        # shellcheck source=./cache-scope.sh
        source "$CODEX_PLUGIN_ROOT/lib/cache-scope.sh" 2>/dev/null || true
    fi
    if type cache_scope_init >/dev/null 2>&1; then
        cache_scope_init "$CODEX_PLUGIN_ROOT" "$PWD" 2>/dev/null || true
        TURN_FILE="${CACHE_DIR:-}/current-turn.yaml"
        if [ -n "${CACHE_DIR:-}" ] && [ -f "$TURN_FILE" ]; then
            CODEX_JSONL_PATH="$(grep '^codexJsonlPath:' "$TURN_FILE" 2>/dev/null | head -1 | sed 's/^codexJsonlPath:[[:space:]]*//' | tr -d '"' || true)"
        fi
    fi
fi

_build_complete_params() {
    printf 'response: |\n'
    printf '%s\n' "$response" | sed 's/^/  /'
}

# If we have a JSONL file, extract rich fields and emit to completeTurn
if [ -n "$CODEX_JSONL_PATH" ] && [ -f "$CODEX_JSONL_PATH" ] && command -v node >/dev/null 2>&1; then
    JSONL_ENRICH="$(node "${SCRIPT_DIR}/codex-jsonl-enrich.js" "$CODEX_JSONL_PATH" "$response" 2>/dev/null || true)"
    if [ -n "$JSONL_ENRICH" ]; then
        printf '%s\n' "$JSONL_ENRICH" | "$SCRIPT_DIR/repl-invoke.sh" workflow.sessionlog.completeTurn
        exit $?
    fi
fi

# Fallback: plain completeTurn with just the response text
_build_complete_params | "$SCRIPT_DIR/repl-invoke.sh" workflow.sessionlog.completeTurn
