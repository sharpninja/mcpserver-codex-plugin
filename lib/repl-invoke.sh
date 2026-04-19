#!/usr/bin/env bash
set -uo pipefail

# repl_invoke <method> [params_yaml]
# Sends a YAML request envelope to mcpserver-repl --agent-stdio
# Returns the response payload on stdout, exit 1 on error.
#
# Translation shim: workflow.sessionlog.* methods are not server routes.
# They are plugin-local verbs that update cache/current-turn.yaml so the
# Stop hook can verify completion, and (best-effort) persist a session-log
# turn via the real client.SessionLog.SubmitAsync route.

REPL_INVOKE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPL_INVOKE_PLUGIN_ROOT="${PLUGIN_ROOT_OVERRIDE:-$(cd "$REPL_INVOKE_SCRIPT_DIR/.." && pwd)}"
REPL_INVOKE_CACHE_DIR="${REPL_INVOKE_PLUGIN_ROOT}/cache"

_repl_yaml_get() {
    # _repl_yaml_get <yaml_text> <key>
    # Returns the inline scalar value (no block-scalar support).
    printf '%s\n' "$1" | grep "^[[:space:]]*$2:" | head -1 | sed "s/^[[:space:]]*$2:[[:space:]]*//"
}

_repl_session_meta() {
    # Echo "sourceType sessionId" extracted from cache/session-state.yaml.
    local f="${REPL_INVOKE_CACHE_DIR}/session-state.yaml"
    [ -f "$f" ] || return 1
    local sid
    sid="$(grep '^sessionId:' "$f" | head -1 | sed 's/^sessionId:[[:space:]]*//')"
    [ -z "$sid" ] && return 1
    local prefix="${sid%%-*}"
    printf '%s %s' "$prefix" "$sid"
}

_repl_invoke_raw() {
    local method="$1"
    local params_yaml="${2:-}"
    local request_id="req-$(date -u +%Y%m%dT%H%M%SZ)-$(printf '%04x' $RANDOM)"
    local timeout="${REPL_TIMEOUT:-30}"

    if ! command -v mcpserver-repl >/dev/null 2>&1; then
        echo "ERROR: mcpserver-repl not found on PATH" >&2
        return 1
    fi

    local envelope="type: request
payload:
  requestId: ${request_id}
  method: ${method}"

    if [ -n "$params_yaml" ]; then
        local indented_params
        indented_params=$(echo "$params_yaml" | sed 's/^/    /')
        envelope="${envelope}
  params:
${indented_params}"
    fi

    local response
    if response=$(echo "$envelope" | timeout "$timeout" mcpserver-repl --agent-stdio 2>/dev/null); then
        echo "$response"
        # mcpserver-repl returns 0 even on protocol errors; surface them.
        if echo "$response" | grep -q '^type: error'; then
            return 1
        fi
        return 0
    fi
    echo "ERROR: mcpserver-repl invocation failed for method ${method}" >&2
    return 1
}

_repl_persist_turn() {
    # _repl_persist_turn <requestId> <queryTitle> <status> <responseText> [actionsYamlBlock]
    # Best-effort SubmitAsync. Returns 0 on success, non-zero on persist failure.
    local req_id="$1"
    local title="$2"
    local status="$3"
    local response_text="$4"
    local actions_block="${5:-}"

    local meta sourceType sessionId
    if ! meta="$(_repl_session_meta)"; then
        return 1
    fi
    sourceType="${meta%% *}"
    sessionId="${meta##* }"

    local resp_indented
    resp_indented="$(printf '%s' "$response_text" | sed 's/^/      /')"

    local actions_yaml=""
    if [ -n "$actions_block" ]; then
        actions_yaml="$(printf '%s' "$actions_block" | sed 's/^/      /')"
    fi

    local params="sessionLog:
  sourceType: ${sourceType}
  sessionId: ${sessionId}
  title: ${title}
  status: in_progress
  turns:
    - requestId: ${req_id}
      queryTitle: ${title}
      status: ${status}
      response: |
${resp_indented}"

    if [ -n "$actions_yaml" ]; then
        params="${params}
      actions:
${actions_yaml}"
    fi

    _repl_invoke_raw "client.SessionLog.SubmitAsync" "$params" >/dev/null 2>&1
}

_repl_workflow_begin_turn() {
    # No-op shim: user-prompt-submit.sh already wrote current-turn.yaml.
    return 0
}

_repl_workflow_append_actions() {
    # Increment codeEdits counter when params include filePath: lines.
    local params="$1"
    local turn_file="${REPL_INVOKE_CACHE_DIR}/current-turn.yaml"
    [ -f "$turn_file" ] || return 0

    # grep -c exits 1 on no-match; fall back to 0 so pipefail doesn't bubble.
    local added
    added="$(printf '%s\n' "$params" | grep -c '^[[:space:]]*filePath:' || true)"
    added="${added:-0}"
    [ "$added" -gt 0 ] || return 0

    local current
    current="$(grep '^codeEdits:' "$turn_file" | head -1 | sed 's/^codeEdits:[[:space:]]*//')"
    current="${current:-0}"
    local new=$((current + added))

    # Cross-platform sed -i (BSD vs GNU). Use a temp file for portability on Git-Bash.
    local tmp="${turn_file}.tmp.$$"
    awk -v n="$new" '
        /^codeEdits:/ { print "codeEdits: " n; next }
        { print }
    ' "$turn_file" > "$tmp" && mv "$tmp" "$turn_file"

    # Best-effort persist actions to server.
    local req_id title
    req_id="$(grep '^turnRequestId:' "$turn_file" | head -1 | sed 's/^turnRequestId:[[:space:]]*//')"
    title="$(grep '^queryTitle:' "$turn_file" | head -1 | sed 's/^queryTitle:[[:space:]]*//')"
    _repl_persist_turn "$req_id" "$title" "in_progress" "Actions appended." "$params" || true
    return 0
}

_repl_workflow_complete_turn() {
    # Flip status -> completed and persist response summary.
    local params="$1"
    local turn_file="${REPL_INVOKE_CACHE_DIR}/current-turn.yaml"
    [ -f "$turn_file" ] || return 0

    local req_id title response_text
    req_id="$(grep '^turnRequestId:' "$turn_file" | head -1 | sed 's/^turnRequestId:[[:space:]]*//')"
    title="$(grep '^queryTitle:' "$turn_file" | head -1 | sed 's/^queryTitle:[[:space:]]*//')"
    response_text="$(printf '%s\n' "$params" | sed -n '/^[[:space:]]*response:[[:space:]]*|/,$p' | sed '1d' | sed 's/^[[:space:]]\{0,8\}//')"
    if [ -z "$response_text" ]; then
        response_text="$(_repl_yaml_get "$params" 'response')"
    fi
    [ -z "$response_text" ] && response_text="(no response provided)"

    local tmp="${turn_file}.tmp.$$"
    awk '
        /^status:/ { print "status: completed"; next }
        { print }
    ' "$turn_file" > "$tmp" && mv "$tmp" "$turn_file"

    _repl_persist_turn "$req_id" "$title" "completed" "$response_text" "" || true
    return 0
}

_repl_workflow_open_session() {
    # No-op shim: session-start.sh already wrote session-state.yaml.
    return 0
}

repl_invoke() {
    local method="$1"
    local params_yaml="${2:-}"

    case "$method" in
        workflow.sessionlog.beginTurn)
            _repl_workflow_begin_turn
            return $?
            ;;
        workflow.sessionlog.appendActions)
            _repl_workflow_append_actions "$params_yaml"
            return $?
            ;;
        workflow.sessionlog.completeTurn)
            _repl_workflow_complete_turn "$params_yaml"
            return $?
            ;;
        workflow.sessionlog.openSession)
            _repl_workflow_open_session
            return $?
            ;;
    esac

    _repl_invoke_raw "$method" "$params_yaml"
}

# Build envelope without sending (kept for testing/cache).
repl_build_envelope() {
    local method="$1"
    local params_yaml="${2:-}"
    local request_id="req-$(date -u +%Y%m%dT%H%M%SZ)-$(printf '%04x' $RANDOM)"

    local envelope="type: request
payload:
  requestId: ${request_id}
  method: ${method}"

    if [ -n "$params_yaml" ]; then
        local indented_params
        indented_params=$(echo "$params_yaml" | sed 's/^/    /')
        envelope="${envelope}
  params:
${indented_params}"
    fi

    echo "$envelope"
}

export -f repl_invoke repl_build_envelope _repl_invoke_raw _repl_persist_turn _repl_session_meta _repl_yaml_get _repl_workflow_begin_turn _repl_workflow_append_actions _repl_workflow_complete_turn _repl_workflow_open_session 2>/dev/null || true
