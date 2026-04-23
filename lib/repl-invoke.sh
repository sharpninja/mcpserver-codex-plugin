#!/usr/bin/env bash
set -uo pipefail

# repl_invoke <method> [params_yaml]
# Sends a YAML request envelope to mcpserver-repl --agent-stdio.
# Workflow-prefixed methods are plugin-local shims that translate to either:
# - local cache mutations under cache/
# - the real client.* MCP methods exposed by mcpserver-repl

REPL_INVOKE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPL_INVOKE_PLUGIN_ROOT="${PLUGIN_ROOT_OVERRIDE:-$(cd "$REPL_INVOKE_SCRIPT_DIR/.." && pwd)}"
REPL_INVOKE_CACHE_DIR="${REPL_INVOKE_PLUGIN_ROOT}/cache"

_repl_now_iso() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

_repl_now_compact() {
    date -u +%Y%m%dT%H%M%SZ
}

_repl_slugify() {
    local value="${1:-}"
    printf '%s' "$value" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//' \
        | cut -c1-48
}

_repl_unquote() {
    local value="${1:-}"
    value="$(printf '%s' "$value" | sed 's/^"\(.*\)"$/\1/; s/^'\''\(.*\)'\''$/\1/')"
    printf '%s' "$value"
}

_repl_yaml_get() {
    # _repl_yaml_get <yaml_text> <key>
    printf '%s\n' "$1" | grep "^[[:space:]]*$2:" | head -1 | sed "s/^[[:space:]]*$2:[[:space:]]*//"
}

_repl_yaml_block_get() {
    # _repl_yaml_block_get <yaml_text> <key>
    printf '%s\n' "$1" | awk -v key="$2" '
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*\\|[[:space:]]*$" { capture = 1; next }
        capture {
            if ($0 ~ "^[^[:space:]]") {
                exit
            }
            sub(/^[[:space:]][[:space:]]/, "")
            print
        }
    '
}

_repl_list_block_get() {
    # _repl_list_block_get <yaml_text> <key>
    printf '%s\n' "$1" | awk -v key="$2" '
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*$" { capture = 1; next }
        capture {
            if ($0 ~ "^[^[:space:]]") {
                exit
            }
            sub(/^[[:space:]][[:space:]]/, "")
            print
        }
    '
}

_repl_state_value() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 1
    grep "^${key}:" "$file" 2>/dev/null | head -1 | sed "s/^${key}:[[:space:]]*//"
}

_repl_session_state_value() {
    _repl_state_value "${REPL_INVOKE_CACHE_DIR}/session-state.yaml" "$1"
}

_repl_current_turn_value() {
    _repl_state_value "${REPL_INVOKE_CACHE_DIR}/current-turn.yaml" "$1"
}

_repl_session_meta() {
    local f="${REPL_INVOKE_CACHE_DIR}/session-state.yaml"
    [ -f "$f" ] || return 1

    local sid source_type
    sid="$(_repl_session_state_value "sessionId")"
    [ -z "$sid" ] && return 1

    source_type="$(_repl_session_state_value "sourceType")"
    if [ -z "$source_type" ]; then
        source_type="${sid%%-*}"
    fi

    printf '%s %s' "$source_type" "$sid"
}

_repl_emit_response() {
    local body="${1:-  ok: true}"
    printf 'type: response\npayload:\n%s\n' "$body"
}

_repl_write_session_state() {
    local status="$1"
    local source_type="$2"
    local session_id="$3"
    local title="$4"
    local model="$5"
    local started="$6"
    local last_updated="$7"
    local workspace_path="$8"
    local workspace="$9"
    local base_url="${10}"

    source_type="$(_repl_unquote "$source_type")"
    session_id="$(_repl_unquote "$session_id")"
    title="$(_repl_unquote "$title")"
    model="$(_repl_unquote "$model")"
    started="$(_repl_unquote "$started")"
    last_updated="$(_repl_unquote "$last_updated")"
    workspace_path="$(_repl_unquote "$workspace_path")"
    workspace="$(_repl_unquote "$workspace")"
    base_url="$(_repl_unquote "$base_url")"

    mkdir -p "$REPL_INVOKE_CACHE_DIR"
    local session_file="${REPL_INVOKE_CACHE_DIR}/session-state.yaml"
    local tmp="${session_file}.tmp.$$"

    cat > "$tmp" <<EOF
status: ${status}
EOF

    if [ -n "$source_type" ]; then
        printf 'sourceType: %s\n' "$source_type" >> "$tmp"
    fi
    if [ -n "$session_id" ]; then
        printf 'sessionId: %s\n' "$session_id" >> "$tmp"
    fi
    if [ -n "$title" ]; then
        printf 'title: %s\n' "$title" >> "$tmp"
    fi
    if [ -n "$model" ]; then
        printf 'model: %s\n' "$model" >> "$tmp"
    fi
    if [ -n "$started" ]; then
        printf 'started: %s\n' "$started" >> "$tmp"
    fi
    if [ -n "$last_updated" ]; then
        printf 'lastUpdated: %s\n' "$last_updated" >> "$tmp"
    fi
    printf 'workspacePath: "%s"\n' "$workspace_path" >> "$tmp"
    printf 'workspace: "%s"\n' "$workspace" >> "$tmp"
    printf 'baseUrl: "%s"\n' "$base_url" >> "$tmp"
    printf 'timestamp: "%s"\n' "$(_repl_now_iso)" >> "$tmp"

    mv "$tmp" "$session_file"
}

_repl_bootstrap_state() {
    local start_dir="${1:-$(pwd)}"
    local session_file="${REPL_INVOKE_CACHE_DIR}/session-state.yaml"

    if [ -f "$session_file" ]; then
        local existing_status
        existing_status="$(_repl_session_state_value "status")"
        if [ "$existing_status" = "verified" ]; then
            return 0
        fi
    fi

    # shellcheck source=./marker-resolver.sh
    source "${REPL_INVOKE_SCRIPT_DIR}/marker-resolver.sh" || return 1
    full_bootstrap "$start_dir" || return 1

    local workspace_path workspace base_url
    workspace_path="${MCPSERVER_WORKSPACE_PATH:-$start_dir}"
    workspace="${MCPSERVER_WORKSPACE:-$(basename "$workspace_path")}"
    base_url="${MCPSERVER_BASE_URL:-}"

    _repl_write_session_state "verified" "" "" "" "" "" "" "$workspace_path" "$workspace" "$base_url"
}

_repl_generate_session_id() {
    local agent="$1"
    local title="$2"
    local workspace="$3"
    local slug
    slug="$(_repl_slugify "$title")"
    [ -z "$slug" ] && slug="$(_repl_slugify "$workspace")"
    [ -z "$slug" ] && slug="session"
    printf '%s-%s-%s' "$agent" "$(_repl_now_compact)" "$slug"
}

_repl_build_session_submit_params() {
    local source_type="$1"
    local session_id="$2"
    local title="$3"
    local model="$4"
    local started="$5"
    local status="$6"
    local turns_block="${7:-}"
    local turn_count="${8:-0}"

    local params="sessionLog:
  sourceType: ${source_type}
  sessionId: ${session_id}
  title: ${title}
  model: ${model}
  started: ${started}
  lastUpdated: $(_repl_now_iso)
  status: ${status}
  turnCount: ${turn_count}
  totalTokens: 0"

    if [ -n "$turns_block" ]; then
        params="${params}
  turns:
${turns_block}"
    else
        params="${params}
  turns: []"
    fi

    printf '%s' "$params"
}

_repl_invoke_raw() {
    local method="$1"
    local params_yaml="${2:-}"
    local request_id="req-$(_repl_now_compact)-$(printf '%04x' $RANDOM)"
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
        indented_params="$(printf '%s\n' "$params_yaml" | sed 's/^/    /')"
        envelope="${envelope}
  params:
${indented_params}"
    fi

    local response
    if command -v timeout >/dev/null 2>&1; then
        response="$(printf '%s\n' "$envelope" | timeout "$timeout" mcpserver-repl --agent-stdio 2>/dev/null)"
    else
        response="$(printf '%s\n' "$envelope" | mcpserver-repl --agent-stdio 2>/dev/null)"
    fi

    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        printf '%s\n' "$response"
        if printf '%s\n' "$response" | grep -q '^type: error'; then
            return 1
        fi
        return 0
    fi

    echo "ERROR: mcpserver-repl invocation failed for method ${method}" >&2
    return 1
}

_repl_invoke_with_fallback() {
    local primary="$1"
    local fallback="$2"
    local params_yaml="${3:-}"
    local response

    response="$(_repl_invoke_raw "$primary" "$params_yaml" 2>&1)"
    local status=$?
    if [ $status -eq 0 ]; then
        printf '%s\n' "$response"
        return 0
    fi

    if [ -n "$fallback" ] && printf '%s\n' "$response" | grep -q 'method_not_found'; then
        _repl_invoke_raw "$fallback" "$params_yaml"
        return $?
    fi

    printf '%s\n' "$response"
    return $status
}

_repl_submit_session() {
    local source_type="$1"
    local session_id="$2"
    local title="$3"
    local model="$4"
    local started="$5"
    local status="$6"
    local turns_block="${7:-}"
    local turn_count="${8:-0}"

    local params
    params="$(_repl_build_session_submit_params "$source_type" "$session_id" "$title" "$model" "$started" "$status" "$turns_block" "$turn_count")"
    _repl_invoke_raw "client.SessionLog.SubmitAsync" "$params" >/dev/null 2>&1
}

_repl_normalized_actions_block() {
    _repl_list_block_get "$1" "actions"
}

_repl_normalized_dialog_items_block() {
    _repl_list_block_get "$1" "dialogItems"
}

_repl_turns_block() {
    local req_id="$1"
    local title="$2"
    local status="$3"
    local response_text="$4"
    local actions_block="${5:-}"

    local turn_file="${REPL_INVOKE_CACHE_DIR}/current-turn.yaml"
    local query_text timestamp model
    query_text="$(_repl_yaml_block_get "$(cat "$turn_file" 2>/dev/null)" "queryText")"
    [ -z "$query_text" ] && query_text="$title"
    timestamp="$(_repl_current_turn_value "openedAt")"
    [ -z "$timestamp" ] && timestamp="$(_repl_now_iso)"
    model="$(_repl_session_state_value "model")"
    [ -z "$model" ] && model="codex"

    local query_text_indented response_indented
    query_text_indented="$(printf '%s\n' "$query_text" | sed 's/^/        /')"
    response_indented="$(printf '%s\n' "$response_text" | sed 's/^/        /')"

    local files_modified_block=""
    local file_paths
    file_paths="$(printf '%s\n' "$actions_block" | grep '^[[:space:]]*filePath:' | sed 's/^[[:space:]]*filePath:[[:space:]]*//')"
    if [ -n "$file_paths" ]; then
        files_modified_block="      filesModified:
$(printf '%s\n' "$file_paths" | sed 's/^/        - /')"
    else
        files_modified_block="      filesModified: []"
    fi

    local actions_section="      actions: []"
    if [ -n "$actions_block" ]; then
        actions_section="      actions:
$(printf '%s\n' "$actions_block" | sed 's/^/        /')"
    fi

    cat <<EOF
    - requestId: ${req_id}
      timestamp: ${timestamp}
      queryText: |
${query_text_indented}
      queryTitle: ${title}
      response: |
${response_indented}
      interpretation: ""
      status: ${status}
      model: ${model}
      modelProvider: ""
      tokenCount: 0
      tags: []
      contextList: []
      designDecisions: []
      requirementsDiscovered: []
${files_modified_block}
      blockers: []
${actions_section}
      processingDialog: []
EOF
}

_repl_persist_turn() {
    # _repl_persist_turn <requestId> <queryTitle> <status> <responseText> [actionsYamlList]
    local req_id="$1"
    local title="$2"
    local status="$3"
    local response_text="$4"
    local actions_block="${5:-}"

    local meta source_type session_id
    if ! meta="$(_repl_session_meta)"; then
        return 1
    fi
    source_type="${meta%% *}"
    session_id="${meta##* }"

    local title_state model started
    title_state="$(_repl_session_state_value "title")"
    model="$(_repl_session_state_value "model")"
    started="$(_repl_session_state_value "started")"
    [ -z "$title_state" ] && title_state="$title"
    [ -z "$model" ] && model="codex"
    [ -z "$started" ] && started="$(_repl_now_iso)"

    local turns_block
    turns_block="$(_repl_turns_block "$req_id" "$title" "$status" "$response_text" "$actions_block")"
    _repl_submit_session "$source_type" "$session_id" "$title_state" "$model" "$started" "in_progress" "$turns_block" "1"
}

_repl_workflow_bootstrap() {
    local start_dir
    start_dir="$(_repl_yaml_get "$1" "workspacePath")"
    [ -z "$start_dir" ] && start_dir="$(pwd)"

    if ! _repl_bootstrap_state "$start_dir"; then
        return 1
    fi

    _repl_emit_response "  initialized: true"
}

_repl_workflow_open_session() {
    local params="$1"
    local start_dir
    start_dir="$(_repl_yaml_get "$params" "workspacePath")"
    [ -z "$start_dir" ] && start_dir="$(pwd)"

    _repl_bootstrap_state "$start_dir" || return 1

    local workspace workspace_path base_url
    workspace="$(_repl_unquote "$(_repl_session_state_value "workspace")")"
    workspace_path="$(_repl_unquote "$(_repl_session_state_value "workspacePath")")"
    base_url="$(_repl_unquote "$(_repl_session_state_value "baseUrl")")"

    local source_type model title session_id started last_updated
    source_type="$(_repl_yaml_get "$params" "agent")"
    [ -z "$source_type" ] && source_type="$(_repl_yaml_get "$params" "sourceType")"
    [ -z "$source_type" ] && source_type="$(_repl_session_state_value "sourceType")"
    [ -z "$source_type" ] && source_type="${MCP_SESSION_AGENT:-Codex}"

    model="$(_repl_yaml_get "$params" "model")"
    [ -z "$model" ] && model="$(_repl_session_state_value "model")"
    [ -z "$model" ] && model="${MCP_SESSION_MODEL:-codex}"

    title="$(_repl_yaml_get "$params" "title")"
    [ -z "$title" ] && title="$(_repl_session_state_value "title")"
    [ -z "$title" ] && title="${workspace} session"

    session_id="$(_repl_yaml_get "$params" "sessionId")"
    [ -z "$session_id" ] && session_id="$(_repl_session_state_value "sessionId")"
    [ -z "$session_id" ] && session_id="$(_repl_generate_session_id "$source_type" "$title" "$workspace")"

    started="$(_repl_session_state_value "started")"
    [ -z "$started" ] && started="$(_repl_now_iso)"
    last_updated="$(_repl_now_iso)"

    _repl_write_session_state "verified" "$source_type" "$session_id" "$title" "$model" "$started" "$last_updated" "$workspace_path" "$workspace" "$base_url"
    _repl_submit_session "$source_type" "$session_id" "$title" "$model" "$started" "in_progress" "" "0" || true

    _repl_emit_response "  sessionId: ${session_id}
  started: ${started}"
}

_repl_workflow_begin_turn() {
    local params="$1"
    local turn_file="${REPL_INVOKE_CACHE_DIR}/current-turn.yaml"
    local session_id

    session_id="$(_repl_session_state_value "sessionId")"
    if [ -z "$session_id" ]; then
        _repl_workflow_open_session "" >/dev/null
        session_id="$(_repl_session_state_value "sessionId")"
    fi
    [ -z "$session_id" ] && return 1

    local turn_request_id query_title query_text opened_at
    turn_request_id="$(_repl_yaml_get "$params" "requestId")"
    [ -z "$turn_request_id" ] && turn_request_id="req-$(_repl_now_compact)-turn-$(_repl_slugify "$(_repl_yaml_get "$params" "queryTitle")")"
    query_title="$(_repl_yaml_get "$params" "queryTitle")"
    [ -z "$query_title" ] && query_title="User prompt"
    query_text="$(_repl_yaml_block_get "$params" "queryText")"
    [ -z "$query_text" ] && query_text="$(_repl_yaml_get "$params" "queryText")"
    [ -z "$query_text" ] && query_text="$query_title"
    opened_at="$(_repl_now_iso)"

    mkdir -p "$REPL_INVOKE_CACHE_DIR"
    cat > "$turn_file" <<EOF
turnRequestId: ${turn_request_id}
queryTitle: ${query_title}
openedAt: ${opened_at}
status: in_progress
codeEdits: 0
lastBuildStatus: unknown
queryText: |
$(printf '%s\n' "$query_text" | sed 's/^/  /')
EOF

    _repl_persist_turn "$turn_request_id" "$query_title" "in_progress" "(turn opened)" "" || true
    _repl_emit_response "  turnRequestId: ${turn_request_id}
  status: in_progress
  timestamp: ${opened_at}"
}

_repl_workflow_update_turn() {
    local params="$1"
    local turn_file="${REPL_INVOKE_CACHE_DIR}/current-turn.yaml"
    [ -f "$turn_file" ] || return 0

    local req_id title response_text status
    req_id="$(_repl_current_turn_value "turnRequestId")"
    title="$(_repl_current_turn_value "queryTitle")"
    status="$(_repl_yaml_get "$params" "status")"
    [ -z "$status" ] && status="$(_repl_current_turn_value "status")"
    [ -z "$status" ] && status="in_progress"
    response_text="$(_repl_yaml_block_get "$params" "response")"
    [ -z "$response_text" ] && response_text="$(_repl_yaml_get "$params" "response")"
    [ -z "$response_text" ] && response_text="Turn updated."

    _repl_persist_turn "$req_id" "$title" "$status" "$response_text" "" || true
    _repl_emit_response "  turnRequestId: ${req_id}
  status: ${status}"
}

_repl_workflow_append_dialog() {
    local params="$1"
    local meta source_type session_id request_id items_block
    if ! meta="$(_repl_session_meta)"; then
        return 1
    fi
    source_type="${meta%% *}"
    session_id="${meta##* }"

    request_id="$(_repl_yaml_get "$params" "requestId")"
    [ -z "$request_id" ] && request_id="$(_repl_current_turn_value "turnRequestId")"
    [ -z "$request_id" ] && return 1

    items_block="$(_repl_normalized_dialog_items_block "$params")"
    [ -z "$items_block" ] && return 1

    local invoke_params="agent: ${source_type}
sessionId: ${session_id}
requestId: ${request_id}
items:
$(printf '%s\n' "$items_block" | sed 's/^/  /')"

    _repl_invoke_raw "client.SessionLog.AppendDialogAsync" "$invoke_params"
}

_repl_workflow_append_actions() {
    local params="$1"
    local turn_file="${REPL_INVOKE_CACHE_DIR}/current-turn.yaml"
    [ -f "$turn_file" ] || return 0

    local added current new tmp
    added="$(printf '%s\n' "$params" | grep -c '^[[:space:]]*filePath:' || true)"
    added="${added:-0}"

    current="$(_repl_current_turn_value "codeEdits")"
    current="${current:-0}"
    new=$((current + added))

    tmp="${turn_file}.tmp.$$"
    awk -v n="$new" '
        /^codeEdits:/ { print "codeEdits: " n; next }
        { print }
    ' "$turn_file" > "$tmp" && mv "$tmp" "$turn_file"

    local req_id title status actions_block
    req_id="$(_repl_current_turn_value "turnRequestId")"
    title="$(_repl_current_turn_value "queryTitle")"
    status="$(_repl_current_turn_value "status")"
    [ -z "$status" ] && status="in_progress"
    actions_block="$(_repl_normalized_actions_block "$params")"
    _repl_persist_turn "$req_id" "$title" "$status" "Actions appended." "$actions_block" || true

    _repl_emit_response "  ok: true
  codeEdits: ${new}"
}

_repl_workflow_complete_turn() {
    local params="$1"
    local turn_file="${REPL_INVOKE_CACHE_DIR}/current-turn.yaml"
    [ -f "$turn_file" ] || {
        _repl_emit_response "  ok: true"
        return 0
    }

    local req_id title response_text tmp
    req_id="$(_repl_current_turn_value "turnRequestId")"
    title="$(_repl_current_turn_value "queryTitle")"
    response_text="$(_repl_yaml_block_get "$params" "response")"
    [ -z "$response_text" ] && response_text="$(_repl_yaml_get "$params" "response")"
    [ -z "$response_text" ] && response_text="(no response provided)"

    tmp="${turn_file}.tmp.$$"
    awk '
        /^status:/ { print "status: completed"; next }
        { print }
    ' "$turn_file" > "$tmp" && mv "$tmp" "$turn_file"

    _repl_persist_turn "$req_id" "$title" "completed" "$response_text" "" || true
    _repl_emit_response "  ok: true
  status: completed"
}

_repl_workflow_query_history() {
    _repl_invoke_raw "client.SessionLog.QueryAsync" "$1"
}

_repl_workflow_todo_select() {
    local params="$1"
    local todo_id state_file
    todo_id="$(_repl_yaml_get "$params" "id")"
    [ -z "$todo_id" ] && return 1

    mkdir -p "$REPL_INVOKE_CACHE_DIR"
    state_file="${REPL_INVOKE_CACHE_DIR}/todo-state.yaml"
    printf 'selectedTodoId: %s\n' "$todo_id" > "$state_file"
    _repl_emit_response "  id: ${todo_id}"
}

_repl_workflow_todo_update_selected() {
    local params="$1"
    local state_file="${REPL_INVOKE_CACHE_DIR}/todo-state.yaml"
    local todo_id
    todo_id="$(_repl_state_value "$state_file" "selectedTodoId")"
    [ -z "$todo_id" ] && return 1

    local combined="id: ${todo_id}"
    if [ -n "$params" ]; then
        combined="${combined}
${params}"
    fi

    _repl_invoke_raw "client.Todo.UpdateAsync" "$combined"
}

repl_invoke() {
    local method="$1"
    local params_yaml="${2:-}"

    case "$method" in
        workflow.sessionlog.bootstrap)
            _repl_workflow_bootstrap "$params_yaml"
            return $?
            ;;
        workflow.sessionlog.openSession)
            _repl_workflow_open_session "$params_yaml"
            return $?
            ;;
        workflow.sessionlog.beginTurn)
            _repl_workflow_begin_turn "$params_yaml"
            return $?
            ;;
        workflow.sessionlog.updateTurn)
            _repl_workflow_update_turn "$params_yaml"
            return $?
            ;;
        workflow.sessionlog.appendDialog)
            _repl_workflow_append_dialog "$params_yaml"
            return $?
            ;;
        workflow.sessionlog.appendActions)
            _repl_workflow_append_actions "$params_yaml"
            return $?
            ;;
        workflow.sessionlog.completeTurn|workflow.sessionlog.failTurn)
            _repl_workflow_complete_turn "$params_yaml"
            return $?
            ;;
        workflow.sessionlog.queryHistory)
            _repl_workflow_query_history "$params_yaml"
            return $?
            ;;
        workflow.todo.query)
            _repl_invoke_raw "client.Todo.QueryAsync" "$params_yaml"
            return $?
            ;;
        workflow.todo.get)
            _repl_invoke_with_fallback "client.Todo.GetAsync" "client.Todo.GetByIdAsync" "$params_yaml"
            return $?
            ;;
        workflow.todo.create)
            _repl_invoke_raw "client.Todo.CreateAsync" "$params_yaml"
            return $?
            ;;
        workflow.todo.update)
            _repl_invoke_raw "client.Todo.UpdateAsync" "$params_yaml"
            return $?
            ;;
        workflow.todo.delete)
            _repl_invoke_raw "client.Todo.DeleteAsync" "$params_yaml"
            return $?
            ;;
        workflow.todo.analyzeRequirements)
            _repl_invoke_raw "client.Todo.AnalyzeRequirementsAsync" "$params_yaml"
            return $?
            ;;
        workflow.todo.select)
            _repl_workflow_todo_select "$params_yaml"
            return $?
            ;;
        workflow.todo.updateSelected)
            _repl_workflow_todo_update_selected "$params_yaml"
            return $?
            ;;
    esac

    _repl_invoke_raw "$method" "$params_yaml"
}

repl_build_envelope() {
    local method="$1"
    local params_yaml="${2:-}"
    local request_id="req-$(_repl_now_compact)-$(printf '%04x' $RANDOM)"

    local envelope="type: request
payload:
  requestId: ${request_id}
  method: ${method}"

    if [ -n "$params_yaml" ]; then
        local indented_params
        indented_params="$(printf '%s\n' "$params_yaml" | sed 's/^/    /')"
        envelope="${envelope}
  params:
${indented_params}"
    fi

    printf '%s\n' "$envelope"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    method="${1:-}"
    if [ -z "$method" ]; then
        echo "usage: repl-invoke.sh <method> [params_yaml_from_stdin]" >&2
        exit 64
    fi

    params_yaml="$(cat 2>/dev/null || true)"
    repl_invoke "$method" "$params_yaml"
    exit $?
fi

export -f repl_invoke repl_build_envelope _repl_invoke_raw _repl_invoke_with_fallback _repl_bootstrap_state _repl_emit_response _repl_generate_session_id _repl_normalized_actions_block _repl_normalized_dialog_items_block _repl_persist_turn _repl_session_meta _repl_session_state_value _repl_state_value _repl_submit_session _repl_turns_block _repl_workflow_append_actions _repl_workflow_append_dialog _repl_workflow_begin_turn _repl_workflow_bootstrap _repl_workflow_complete_turn _repl_workflow_open_session _repl_workflow_query_history _repl_workflow_todo_select _repl_workflow_todo_update_selected _repl_workflow_update_turn _repl_yaml_block_get _repl_yaml_get 2>/dev/null || true
