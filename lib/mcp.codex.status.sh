#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CACHE_ROOT="${PLUGIN_ROOT_OVERRIDE:-$CODEX_PLUGIN_ROOT}"
WORKSPACE_PATH="${MCP_WORKSPACE_PATH:-$(pwd)}"

# shellcheck source=./cache-scope.sh
source "$SCRIPT_DIR/cache-scope.sh"
cache_scope_init "$CACHE_ROOT" "$WORKSPACE_PATH"

# shellcheck source=./marker-resolver.sh
source "$SCRIPT_DIR/marker-resolver.sh"

yaml_quote() {
    local value="${1:-}"
    value="$(printf '%s' "$value" | sed "s/'/''/g")"
    printf "'%s'" "$value"
}

state_value() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 1
    grep "^${key}:" "$file" 2>/dev/null | head -1 | sed "s/^${key}:[[:space:]]*//"
}

marker_file=""
marker_trust="missing"
marker_base_url=""
marker_workspace_path=""
health_nonce_status="not_checked"
health_nonce=""
health_error=""

if marker_file="$(find_marker_file "$WORKSPACE_PATH" 2>/dev/null)"; then
    marker_base_url="$(parse_marker_field "$marker_file" "baseUrl" 2>/dev/null || true)"
    marker_workspace_path="$(parse_marker_field "$marker_file" "workspacePath" 2>/dev/null || true)"

    if command -v openssl >/dev/null 2>&1 && verify_signature "$marker_file" >/dev/null 2>&1; then
        marker_trust="signature_verified"
    else
        marker_trust="signature_failed"
    fi

    if [ -n "$marker_base_url" ] && command -v curl >/dev/null 2>&1; then
        health_nonce="nonce-$(date +%s)-$$"
        health_response="$(curl -sf --max-time "${MCP_PLUGIN_HEALTH_TIMEOUT_SECONDS:-3}" "${marker_base_url}/health?nonce=${health_nonce}" 2>&1)"
        if printf '%s' "$health_response" | grep -q "\"nonce\":\"${health_nonce}\""; then
            health_nonce_status="verified"
        else
            health_nonce_status="failed"
            health_error="$(printf '%s' "$health_response" | tr '\r\n' ' ' | cut -c1-160)"
        fi
    fi
else
    marker_file=""
fi

session_file="$CACHE_DIR/session-state.yaml"
turn_file="$CACHE_DIR/current-turn.yaml"
repl_path="$(command -v mcpserver-repl 2>/dev/null || true)"

printf 'mcp.codex.status:\n'
printf '  pluginRoot: %s\n' "$(yaml_quote "$CODEX_PLUGIN_ROOT")"
printf '  cacheRoot: %s\n' "$(yaml_quote "$CACHE_ROOT")"
printf '  workspacePath: %s\n' "$(yaml_quote "$WORKSPACE_PATH")"
printf '  cacheDir: %s\n' "$(yaml_quote "$CACHE_DIR")"
printf '  replPath: %s\n' "$(yaml_quote "$repl_path")"
printf '  marker:\n'
printf '    path: %s\n' "$(yaml_quote "$marker_file")"
printf '    trust: %s\n' "$(yaml_quote "$marker_trust")"
printf '    healthNonce: %s\n' "$(yaml_quote "$health_nonce_status")"
printf '    healthNonceValue: %s\n' "$(yaml_quote "$health_nonce")"
printf '    healthError: %s\n' "$(yaml_quote "$health_error")"
printf '    baseUrl: %s\n' "$(yaml_quote "$marker_base_url")"
printf '    workspacePath: %s\n' "$(yaml_quote "$marker_workspace_path")"
printf '  session:\n'
printf '    sourceType: %s\n' "$(yaml_quote "$(state_value "$session_file" sourceType || true)")"
printf '    sessionId: %s\n' "$(yaml_quote "$(state_value "$session_file" sessionId || true)")"
printf '    status: %s\n' "$(yaml_quote "$(state_value "$session_file" status || true)")"
printf '  currentTurn:\n'
printf '    turnRequestId: %s\n' "$(yaml_quote "$(state_value "$turn_file" turnRequestId || true)")"
printf '    queryTitle: %s\n' "$(yaml_quote "$(state_value "$turn_file" queryTitle || true)")"
printf '    status: %s\n' "$(yaml_quote "$(state_value "$turn_file" status || true)")"
printf '    codeEdits: %s\n' "$(yaml_quote "$(state_value "$turn_file" codeEdits || true)")"
printf '    lastBuildStatus: %s\n' "$(yaml_quote "$(state_value "$turn_file" lastBuildStatus || true)")"
printf '  namespaces:\n'
printf '    - workflow.sessionlog\n'
printf '    - workflow.todo\n'
printf '    - workflow.memory\n'
printf '    - workflow.requirements\n'
printf '    - client\n'
printf '  wrappers:\n'
printf '    status: %s\n' "$(yaml_quote "./Invoke-CodexMcpPlugin.ps1 -Command Status")"
printf '    invoke: %s\n' "$(yaml_quote "./Invoke-CodexMcpPlugin.ps1 -Command Invoke -Method <method> -Params <yaml>")"
printf '    completeTurn: %s\n' "$(yaml_quote "./Invoke-CodexMcpPlugin.ps1 -Command CompleteTurn -Response <text>")"
