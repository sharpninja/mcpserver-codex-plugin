#!/usr/bin/env bats
# Regression suite for the workflow.sessionlog.* shim added to lib/repl-invoke.sh.
#
# Original bug: every workflow.sessionlog.* call returned method_not_found
# from mcpserver-repl. mcpserver-repl exits 0 even on type:error, so callers
# saw "success" — but cache/current-turn.yaml never flipped to completed and
# the Stop hook blocked every turn.

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB="$PLUGIN_ROOT/lib/repl-invoke.sh"

setup() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "$SANDBOX/cache" "$SANDBOX/bin" "$SANDBOX/workspace"
    export STUB_LOG="$SANDBOX/repl-calls.log"
    export STUB_DB="$SANDBOX/requirements-fr.db"

# Stub mcpserver-repl: emulates the real dispatcher — success for valid
# client.* methods, type:error for the workflow.* fictions so any future
# shim-removal regresses through THIS test.
    cat > "$SANDBOX/bin/mcpserver-repl" <<'STUB'
#!/usr/bin/env bash
input="$(cat)"
method="$(printf '%s\n' "$input" | grep '^[[:space:]]*method:' | head -1 | sed 's/^[[:space:]]*method:[[:space:]]*//')"
{
    printf 'method=%s\n' "$method"
    printf 'cwd=%s\n' "$(pwd)"
    printf 'MCP_WORKSPACE_PATH=%s\n' "${MCP_WORKSPACE_PATH:-}"
    printf 'MCP_SERVER_URL=%s\n' "${MCP_SERVER_URL:-}"
    printf '%s\n' "$input" | sed 's/^/input: /'
    printf '%s\n' '---'
} >> "${STUB_LOG:-/dev/null}"

extract_yaml_value() {
    printf '%s\n' "$input" | grep "^[[:space:]]*$1:" | tail -1 | sed "s/^[[:space:]]*$1:[[:space:]]*//"
}

if [[ "$method" == workflow.requirements.* ]] && [ "${STUB_WORKFLOW_REQUIREMENTS_AUTH_ERROR:-}" = "1" ]; then
    printf 'type: error\npayload:\n  code: method_invocation_error\n  message: Authentication required: no credential is configured on this client.\n'
    exit 0
fi

if [ "$method" = "workflow.requirements.generateDocument" ] && [ "${STUB_WORKFLOW_REQUIREMENTS_REJECT_WIKI:-}" = "1" ]; then
    format="$(extract_yaml_value format)"
    if [ "$format" = "wiki" ]; then
        printf 'type: error\npayload:\n  code: invalid_argument\n  message: "Invalid format: wiki. Valid values: markdown, yaml"\n'
        exit 0
    fi
fi

if [ "$method" = "client.SessionLog.QueryAsync" ] && [ "${STUB_REQUIRE_COMPAT_AUTH:-}" = "1" ] && [ "${MCP_WORKSPACE_PATH:-}" = "${STUB_AUTH_FAIL_WORKSPACE_PATH:-}" ]; then
    printf 'type: error\npayload:\n  code: method_invocation_error\n  message: Authentication required: no credential is configured on this client.\n'
    exit 0
fi

case "$method" in
    client.SessionLog.SubmitAsync|client.SessionLog.QueryAsync|client.SessionLog.AppendDialogAsync|client.Todo.QueryAsync|client.Todo.UpdateAsync|client.Todo.GetAsync|client.Todo.GetByIdAsync)
        printf 'type: response\npayload:\n  ok: true\n'
        ;;
    workflow.sessionlog.*|workflow.requirements.*)
        printf 'type: error\npayload:\n  code: method_not_found\n  message: not routed\n'
        ;;
    client.Requirements.CreateFrAsync)
        id="$(extract_yaml_value id)"
        title="$(extract_yaml_value title)"
        body="$(extract_yaml_value body)"
        printf '%s|%s|%s\n' "$id" "$title" "$body" >> "$STUB_DB"
        printf 'type: result\npayload:\n  result:\n    item:\n      id: %s\n      title: %s\n      description: %s\n' "$id" "$title" "$body"
        ;;
    client.Requirements.ListFrAsync)
        if [ "${STUB_REQUIRE_COMPAT_AUTH:-}" = "1" ] && [ "${MCP_WORKSPACE_PATH:-}" = "${STUB_AUTH_FAIL_WORKSPACE_PATH:-}" ]; then
            printf 'type: error\npayload:\n  code: method_invocation_error\n  message: Authentication required: no credential is configured on this client.\n'
            exit 0
        fi
        printf 'type: result\npayload:\n  result:\n    items:\n'
        if [ -f "$STUB_DB" ]; then
            while IFS='|' read -r id title body; do
                [ -z "$id" ] && continue
                printf '      - id: %s\n        title: %s\n        description: %s\n' "$id" "$title" "$body"
            done < "$STUB_DB"
        fi
        printf '    totalCount: %s\n' "$(wc -l < "$STUB_DB" 2>/dev/null || printf 0)"
        ;;
    client.Requirements.GetFrAsync)
        id="$(extract_yaml_value id)"
        printf 'type: result\npayload:\n  result:\n    item:\n      id: %s\n      title: Stored FR\n      description: Stored body\n' "$id"
        ;;
    client.Requirements.GenerateAsync)
        doc="$(extract_yaml_value doc)"
        format="$(extract_yaml_value format)"
        if [ "${STUB_TYPED_GENERATE_EMPTY:-}" = "1" ]; then
            printf 'type: result\npayload:\n  result:\n'
            exit 0
        fi
        if [ "$format" = "wiki" ]; then
            printf 'type: result\npayload:\n  result:\n    success: true\n    format: wiki\n    docType: all\n    generatedAtUtc: 2026-05-08T12:00:00Z\n    outputRoot: /workspace/docs/Project/wiki\n    files:\n      - relativePath: azure/Home.md\n        fullPath: /workspace/docs/Project/wiki/azure/Home.md\n        contentType: text/markdown\n        lastModifiedUtc: 2026-05-08T12:00:00Z\n'
        else
            printf 'type: result\npayload:\n  result:\n    content: |\n      # Requirement Traceability Matrix\n      doc=%s\n    format: markdown\n' "$doc"
        fi
        ;;
    client.Requirements.GetTrAsync|client.Requirements.GetTestAsync|client.Requirements.DeleteFrAsync|client.Requirements.DeleteTrAsync|client.Requirements.DeleteTestAsync|client.Requirements.ListTrAsync|client.Requirements.ListTestAsync|client.Requirements.ListMappingsAsync|client.Requirements.CreateTrAsync|client.Requirements.UpdateFrAsync|client.Requirements.UpdateTrAsync|client.Requirements.CreateTestAsync|client.Requirements.UpdateTestAsync|client.Requirements.UpsertMappingAsync|client.Requirements.DeleteMappingAsync|client.Requirements.IngestAsync)
        printf 'type: result\npayload:\n  result:\n    ok: true\n'
        ;;
    *)
        printf 'type: error\npayload:\n  code: method_invocation_error\n  message: unknown\n'
        ;;
esac
STUB
    chmod +x "$SANDBOX/bin/mcpserver-repl"

    cat > "$SANDBOX/bin/curl" <<'STUB'
#!/usr/bin/env bash
headers_file=""
output_file=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -D)
            headers_file="$2"
            shift 2
            ;;
        -o)
            output_file="$2"
            shift 2
            ;;
        -H)
            shift 2
            ;;
        -*)
            shift
            ;;
        *)
            shift
            ;;
    esac
done
[ -n "$headers_file" ] && printf 'HTTP/1.1 200 OK\r\nContent-Type: application/zip\r\n\r\n' > "$headers_file"
[ -n "$output_file" ] && printf 'PK\003\004' > "$output_file"
exit 0
STUB
    chmod +x "$SANDBOX/bin/curl"

    cat > "$SANDBOX/cache/session-state.yaml" <<EOF
status: verified
sessionId: ClaudeCode-20260419T000000Z-test
sourceType: ClaudeCode
title: Shim test session
model: codex
started: 2026-04-19T00:00:00Z
lastUpdated: 2026-04-19T00:00:00Z
workspacePath: "/tmp/ws"
workspace: "test"
baseUrl: "http://localhost:1"
timestamp: "2026-04-19T00:00:00Z"
EOF

    export PATH="$SANDBOX/bin:$PATH"
    export PLUGIN_ROOT_OVERRIDE="$SANDBOX"
}

teardown() {
    rm -rf "$SANDBOX"
}

write_turn() {
    local status="${1:-in_progress}" edits="${2:-0}" build="${3:-unknown}"
    cat > "$SANDBOX/cache/current-turn.yaml" <<EOF
turnRequestId: req-test-shim-001
queryTitle: Shim test
openedAt: 2026-04-19T00:00:00Z
status: ${status}
codeEdits: ${edits}
lastBuildStatus: ${build}
EOF
}

read_status() {
    grep '^status:' "$SANDBOX/cache/current-turn.yaml" | head -1 | sed 's/^status:[[:space:]]*//'
}

read_edits() {
    grep '^codeEdits:' "$SANDBOX/cache/current-turn.yaml" | head -1 | sed 's/^codeEdits:[[:space:]]*//'
}

write_requirements_state() {
    cat > "$SANDBOX/cache/session-state.yaml" <<EOF
status: verified
sessionId: Codex-20260419T000000Z-test
sourceType: Codex
title: Requirements shim test
model: codex
started: 2026-04-19T00:00:00Z
lastUpdated: 2026-04-19T00:00:00Z
workspacePath: "$SANDBOX/workspace"
workspace: "test"
baseUrl: "http://127.0.0.1:8765"
timestamp: "2026-04-19T00:00:00Z"
EOF
}

@test "completeTurn flips current-turn.yaml status from in_progress to completed" {
    write_turn "in_progress"
    source "$LIB"
    run repl_invoke "workflow.sessionlog.completeTurn" "requestId: req-test-shim-001
response: |
  Done."
    [ "$status" -eq 0 ]
    [ "$(read_status)" = "completed" ]
}

@test "completeTurn is idempotent on already-completed turns" {
    write_turn "completed"
    source "$LIB"
    run repl_invoke "workflow.sessionlog.completeTurn" "response: again"
    [ "$status" -eq 0 ]
    [ "$(read_status)" = "completed" ]
}

@test "completeTurn no-ops gracefully when current-turn.yaml is missing" {
    rm -f "$SANDBOX/cache/current-turn.yaml"
    source "$LIB"
    run repl_invoke "workflow.sessionlog.completeTurn" "response: x"
    [ "$status" -eq 0 ]
}

@test "appendActions bumps codeEdits once per filePath: in params" {
    write_turn "in_progress" 0
    source "$LIB"
    repl_invoke "workflow.sessionlog.appendActions" "actions:
  - description: a
    type: edit
    filePath: src/a.cs
  - description: b
    type: edit
    filePath: src/b.cs"
    [ "$(read_edits)" = "2" ]
}

@test "appendActions with no filePath: leaves codeEdits unchanged" {
    write_turn "in_progress" 0
    source "$LIB"
    repl_invoke "workflow.sessionlog.appendActions" "actions:
  - description: design only
    type: design_decision"
    [ "$(read_edits)" = "0" ]
}

@test "appendActions accumulates across multiple invocations" {
    write_turn "in_progress" 1
    source "$LIB"
    repl_invoke "workflow.sessionlog.appendActions" "actions:
  - description: c
    type: edit
    filePath: src/c.cs"
    [ "$(read_edits)" = "2" ]
}

@test "beginTurn creates current-turn.yaml when called directly" {
    source "$LIB"
    rm -f "$SANDBOX/cache/current-turn.yaml"
    run repl_invoke "workflow.sessionlog.beginTurn" "requestId: req-test-begin-001
queryTitle: Direct begin
queryText: |
  Start work now."
    [ "$status" -eq 0 ]
    grep -q '^turnRequestId: req-test-begin-001' "$SANDBOX/cache/current-turn.yaml"
    grep -q '^status: in_progress' "$SANDBOX/cache/current-turn.yaml"
}

@test "openSession populates missing session metadata" {
    source "$LIB"
    cat > "$SANDBOX/cache/session-state.yaml" <<EOF
status: verified
workspacePath: "/tmp/ws"
workspace: "test"
baseUrl: "http://localhost:1"
timestamp: "2026-04-19T00:00:00Z"
EOF
    run repl_invoke "workflow.sessionlog.openSession" "agent: Codex
title: Fix the plugin
model: gpt-5.4"
    [ "$status" -eq 0 ]
    grep -q '^sessionId: Codex-' "$SANDBOX/cache/session-state.yaml"
    grep -q '^sourceType: Codex' "$SANDBOX/cache/session-state.yaml"
    grep -q '^title: Fix the plugin' "$SANDBOX/cache/session-state.yaml"
}

@test "raw client.SessionLog.QueryAsync passes through to mcpserver-repl" {
    source "$LIB"
    run repl_invoke "client.SessionLog.QueryAsync" "limit: 1"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "type: response"
}

@test "workflow.sessionlog.queryHistory uses compatibility marker without workspace env override" {
    write_requirements_state
    export MCPSERVER_API_KEY="test-api-key"
    export STUB_REQUIRE_COMPAT_AUTH=1
    export STUB_AUTH_FAIL_WORKSPACE_PATH="$SANDBOX/workspace"
    source "$LIB"

    run repl_invoke "workflow.sessionlog.queryHistory" "agent: Codex
limit: 1"

    unset MCPSERVER_API_KEY
    unset STUB_REQUIRE_COMPAT_AUTH
    unset STUB_AUTH_FAIL_WORKSPACE_PATH
    [ "$status" -eq 0 ]
    [ "$(grep -c "method=client.SessionLog.QueryAsync" "$STUB_LOG")" -eq 1 ]
    grep -q "cwd=.*repl-marker" "$STUB_LOG"
    grep -q '^MCP_WORKSPACE_PATH=$' "$STUB_LOG"
    ! grep -q "MCP_WORKSPACE_PATH=$SANDBOX/workspace" "$STUB_LOG"
}

@test "raw call returns exit 1 when mcpserver-repl emits type: error" {
    source "$LIB"
    run repl_invoke "client.SessionLog.NopeAsync" ""
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "type: error"
}

@test "workflow verbs never fall through to raw error path" {
    write_turn "in_progress"
    source "$LIB"
    # The stub returns type:error for workflow.* methods. If shim were
    # removed, this assertion would catch the regression.
    run repl_invoke "workflow.sessionlog.completeTurn" "response: regression guard"
    [ "$status" -eq 0 ]
    [ "$(read_status)" = "completed" ]
}

@test "completeTurn still flips cache when mcpserver-repl is unavailable" {
    write_turn "in_progress"
    # Strip our stub bin from PATH; coreutils stay reachable.
    PATH_BACKUP="$PATH"
    export PATH="$(printf '%s' "$PATH_BACKUP" | tr ':' '\n' | grep -vxF "$SANDBOX/bin" | paste -sd ':' -)"
    source "$LIB"
    run repl_invoke "workflow.sessionlog.completeTurn" "response: offline"
    export PATH="$PATH_BACKUP"
    [ "$status" -eq 0 ]
    [ "$(read_status)" = "completed" ]
}

@test "workflow.requirements.listFr falls back to typed client instead of method_not_found" {
    write_requirements_state
    source "$LIB"
    run repl_invoke "workflow.requirements.listFr" ""
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "type: result"
    ! echo "$output" | grep -q "method_not_found"
    grep -q "method=workflow.requirements.listFr" "$STUB_LOG"
    grep -q "method=client.Requirements.ListFrAsync" "$STUB_LOG"
}

@test "workflow.requirements.updateFr falls back when workflow emits auth error" {
    write_requirements_state
    export STUB_WORKFLOW_REQUIREMENTS_AUTH_ERROR=1
    source "$LIB"
    run repl_invoke "workflow.requirements.updateFr" "id: FR-MCP-901
title: Requirements shim
description: Plugin wrapper must route update calls through typed fallback"
    unset STUB_WORKFLOW_REQUIREMENTS_AUTH_ERROR
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "Authentication required"
    grep -q "method=workflow.requirements.updateFr" "$STUB_LOG"
    grep -q "method=client.Requirements.UpdateFrAsync" "$STUB_LOG"
}

@test "workflow.requirements.createFr listFr getFr works through typed fallback" {
    write_requirements_state
    source "$LIB"

    run repl_invoke "workflow.requirements.createFr" "id: FR-MCP-901
title: Requirements shim
description: Plugin wrapper must route requirements calls
priority: high
area: MCP"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "FR-MCP-901"

    run repl_invoke "workflow.requirements.listFr" ""
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "FR-MCP-901"

    run repl_invoke "workflow.requirements.getFr" "id: FR-MCP-901"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "FR-MCP-901"
}

@test "workflow.requirements.generateDocument returns content through typed fallback" {
    write_requirements_state
    source "$LIB"
    run repl_invoke "workflow.requirements.generateDocument" "format: markdown
docType: matrix"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Requirement Traceability Matrix"
    grep -q "method=client.Requirements.GenerateAsync" "$STUB_LOG"
    grep -q "input:     doc: mapping" "$STUB_LOG"
    grep -q "input:     format: markdown" "$STUB_LOG"
}

@test "workflow.requirements.generateDocument returns wiki workspace export metadata through typed fallback" {
    write_requirements_state
    source "$LIB"
    run repl_invoke "workflow.requirements.generateDocument" "format: wiki
docType: all"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "outputRoot: /workspace/docs/Project/wiki"
    echo "$output" | grep -q "relativePath: azure/Home.md"
    grep -q "input:     doc: all" "$STUB_LOG"
    grep -q "input:     format: wiki" "$STUB_LOG"
}

@test "workflow.requirements.generateDocument falls back when workflow rejects wiki format" {
    write_requirements_state
    export STUB_WORKFLOW_REQUIREMENTS_REJECT_WIKI=1
    source "$LIB"
    run repl_invoke "workflow.requirements.generateDocument" "format: wiki
docType: all"
    unset STUB_WORKFLOW_REQUIREMENTS_REJECT_WIKI
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "outputRoot: /workspace/docs/Project/wiki"
    ! echo "$output" | grep -q "Invalid format: wiki"
    grep -q "method=workflow.requirements.generateDocument" "$STUB_LOG"
    grep -q "method=client.Requirements.GenerateAsync" "$STUB_LOG"
}

@test "workflow.requirements.generateDocument uses HTTP fallback when REPL typed result is empty" {
    write_requirements_state
    export MCPSERVER_API_KEY="test-api-key"
    export STUB_WORKFLOW_REQUIREMENTS_REJECT_WIKI=1
    export STUB_TYPED_GENERATE_EMPTY=1
    source "$LIB"
    run repl_invoke "workflow.requirements.generateDocument" "format: wiki
docType: all"
    unset MCPSERVER_API_KEY
    unset STUB_WORKFLOW_REQUIREMENTS_REJECT_WIKI
    unset STUB_TYPED_GENERATE_EMPTY
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "contentBase64: UEsDBA=="
    echo "$output" | grep -q "contentType: application/zip"
    echo "$output" | grep -q "fileName: requirements-wiki-documents.zip"
}

@test "workflow.requirements.ingestDocument passes wiki documents and timestamps to typed fallback" {
    write_requirements_state
    source "$LIB"
    run repl_invoke "workflow.requirements.ingestDocument" "format: wiki
sourceFormat: wiki
preferredWikiFormat: github
documents:
  github/Functional-Requirements.md:
    content: |
      # Functional Requirements (MCP Server)
    lastModifiedUtc: 2026-05-08T12:00:00Z"
    [ "$status" -eq 0 ]
    grep -q "method=client.Requirements.IngestAsync" "$STUB_LOG"
    grep -q "input:       sourceFormat: wiki" "$STUB_LOG"
    grep -q "input:       preferredWikiFormat: github" "$STUB_LOG"
    grep -q "input:       documents:" "$STUB_LOG"
    grep -q "github/Functional-Requirements.md" "$STUB_LOG"
    grep -q "lastModifiedUtc: 2026-05-08T12:00:00Z" "$STUB_LOG"
}

@test "workflow.requirements uses session-state workspace path and base URL for mcpserver-repl" {
    write_requirements_state
    source "$LIB"
    run repl_invoke "workflow.requirements.listFr" ""
    [ "$status" -eq 0 ]
    grep -q "cwd=$SANDBOX/workspace" "$STUB_LOG"
    grep -q "MCP_WORKSPACE_PATH=$SANDBOX/workspace" "$STUB_LOG"
    grep -q "MCP_SERVER_URL=http://127.0.0.1:8765" "$STUB_LOG"
}

@test "workflow.requirements prefers compatibility marker when direct marker auth would fail" {
    write_requirements_state
    export MCPSERVER_API_KEY="test-api-key"
    export STUB_REQUIRE_COMPAT_AUTH=1
    export STUB_AUTH_FAIL_WORKSPACE_PATH="$SANDBOX/workspace"
    source "$LIB"

    run repl_invoke "workflow.requirements.listFr" ""

    unset MCPSERVER_API_KEY
    unset STUB_REQUIRE_COMPAT_AUTH
    unset STUB_AUTH_FAIL_WORKSPACE_PATH
    [ "$status" -eq 0 ]
    [ "$(grep -c "method=client.Requirements.ListFrAsync" "$STUB_LOG")" -eq 1 ]
    awk '
        /method=client.Requirements.ListFrAsync/ { capture = 1 }
        capture && /cwd=.*repl-marker/ { saw_cwd = 1 }
        capture && /^MCP_WORKSPACE_PATH=$/ { saw_empty_workspace_env = 1 }
        /^---$/ { capture = 0 }
        END { exit((saw_cwd && saw_empty_workspace_env) ? 0 : 1) }
    ' "$STUB_LOG"
}
