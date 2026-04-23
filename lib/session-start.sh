#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CACHE_DIR="${PLUGIN_ROOT_OVERRIDE:-$CODEX_PLUGIN_ROOT}/cache"
START_DIR="${1:-$(pwd)}"

# shellcheck source=./repl-invoke.sh
source "$CODEX_PLUGIN_ROOT/lib/repl-invoke.sh"

if ! _repl_bootstrap_state "$START_DIR" >/dev/null 2>&1; then
    printf '{"status":"untrusted"}\n'
    exit 1
fi

SESSION_PARAMS=""
if [ -n "${MCP_SESSION_AGENT:-}" ]; then
    SESSION_PARAMS="${SESSION_PARAMS}agent: ${MCP_SESSION_AGENT}
"
fi
if [ -n "${MCP_SESSION_MODEL:-}" ]; then
    SESSION_PARAMS="${SESSION_PARAMS}model: ${MCP_SESSION_MODEL}
"
fi
if [ -n "${MCP_SESSION_TITLE:-}" ]; then
    SESSION_PARAMS="${SESSION_PARAMS}title: ${MCP_SESSION_TITLE}
"
fi
if [ -n "${MCP_SESSION_ID:-}" ]; then
    SESSION_PARAMS="${SESSION_PARAMS}sessionId: ${MCP_SESSION_ID}
"
fi

repl_invoke "workflow.sessionlog.openSession" "$SESSION_PARAMS" >/dev/null || {
    printf '{"status":"no-session"}\n'
    exit 1
}

SESSION_ID="$(grep '^sessionId:' "$CACHE_DIR/session-state.yaml" 2>/dev/null | head -1 | sed 's/^sessionId:[[:space:]]*//')"
STATUS="$(grep '^status:' "$CACHE_DIR/session-state.yaml" 2>/dev/null | head -1 | sed 's/^status:[[:space:]]*//')"
printf '{"status":"%s","sessionId":"%s"}\n' "$STATUS" "$SESSION_ID"
