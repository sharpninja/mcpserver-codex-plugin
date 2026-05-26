#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
START_DIR="${1:-$(pwd)}"

# shellcheck source=./cache-scope.sh
source "$CODEX_PLUGIN_ROOT/lib/cache-scope.sh"
cache_scope_init "$CODEX_PLUGIN_ROOT" "$START_DIR"

# shellcheck source=./repl-invoke.sh
source "$CODEX_PLUGIN_ROOT/lib/repl-invoke.sh"

_session_start_run_with_timeout() {
    local timeout_seconds="${1:-8}"
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout --kill-after=2s "$timeout_seconds" "$@"
        return $?
    fi

    "$@"
}

if ! _repl_bootstrap_state "$START_DIR" >/dev/null 2>&1; then
    printf '{"status":"untrusted","error":"marker bootstrap failed"}\n'
    exit 1
fi

LOCK_DIR="$CACHE_DIR/session-start.lock"
if [ -d "$LOCK_DIR" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0) ))
    if [ "$LOCK_AGE" -gt "${MCP_PLUGIN_STALE_LOCK_SECONDS:-120}" ]; then
        rm -rf "$LOCK_DIR"
    fi
fi
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '{"status":"no-session","error":"session-start already running"}\n'
    exit 1
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

SESSION_AGENT="${MCP_SESSION_AGENT:-Codex}"
SESSION_MODEL="${MCP_SESSION_MODEL:-codex}"
SESSION_TITLE="${MCP_SESSION_TITLE:-Codex plugin session}"
SESSION_WORKSPACE="${MCPSERVER_WORKSPACE:-$(basename "$START_DIR")}"
SESSION_ID="${MCP_SESSION_ID:-$(_repl_generate_session_id "$SESSION_AGENT" "$SESSION_TITLE" "$SESSION_WORKSPACE")}"

SESSION_PARAMS="agent: ${SESSION_AGENT}
model: ${SESSION_MODEL}
title: ${SESSION_TITLE}
sessionId: ${SESSION_ID}
"

OPEN_TIMEOUT="${REPL_SESSIONLOG_REPL_TIMEOUT:-8}"
PREVIOUS_REPL_TIMEOUT="${REPL_TIMEOUT:-}"
export REPL_TIMEOUT="$OPEN_TIMEOUT"
OPEN_OUTPUT="$(repl_invoke "workflow.sessionlog.openSession" "$SESSION_PARAMS" 2>&1)"
OPEN_STATUS=$?
if [ -n "$PREVIOUS_REPL_TIMEOUT" ]; then
    export REPL_TIMEOUT="$PREVIOUS_REPL_TIMEOUT"
else
    unset REPL_TIMEOUT
fi
if [ $OPEN_STATUS -ne 0 ]; then
    printf '{"status":"no-session","error":"%s","timeoutSeconds":%s}\n' "$(_repl_json_escape "$OPEN_OUTPUT")" "$OPEN_TIMEOUT"
    exit 1
fi

SESSION_ID="$(grep '^sessionId:' "$CACHE_DIR/session-state.yaml" 2>/dev/null | head -1 | sed 's/^sessionId:[[:space:]]*//')"
STATUS="$(grep '^status:' "$CACHE_DIR/session-state.yaml" 2>/dev/null | head -1 | sed 's/^status:[[:space:]]*//')"
printf '{"status":"%s","sessionId":"%s"}\n' "$STATUS" "$SESSION_ID"
