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
    mkdir -p "$SANDBOX/cache" "$SANDBOX/bin"

    # Stub mcpserver-repl: emulates the real dispatcher — success for valid
    # client.SessionLog.* methods, type:error for the workflow.* fictions
    # so any future shim-removal regresses through THIS test.
    cat > "$SANDBOX/bin/mcpserver-repl" <<'STUB'
#!/usr/bin/env bash
input="$(cat)"
method="$(printf '%s\n' "$input" | grep '^[[:space:]]*method:' | head -1 | sed 's/^[[:space:]]*method:[[:space:]]*//')"
case "$method" in
    client.SessionLog.SubmitAsync|client.SessionLog.QueryAsync)
        printf 'type: response\npayload:\n  ok: true\n'
        ;;
    workflow.sessionlog.*)
        printf 'type: error\npayload:\n  code: method_not_found\n  message: not routed\n'
        ;;
    *)
        printf 'type: error\npayload:\n  code: method_invocation_error\n  message: unknown\n'
        ;;
esac
STUB
    chmod +x "$SANDBOX/bin/mcpserver-repl"

    cat > "$SANDBOX/cache/session-state.yaml" <<EOF
status: verified
sessionId: ClaudeCode-20260419T000000Z-test
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

@test "beginTurn shim is a no-op success" {
    source "$LIB"
    run repl_invoke "workflow.sessionlog.beginTurn" "requestId: x"
    [ "$status" -eq 0 ]
}

@test "openSession shim is a no-op success" {
    source "$LIB"
    run repl_invoke "workflow.sessionlog.openSession" "agent: ClaudeCode"
    [ "$status" -eq 0 ]
}

@test "raw client.SessionLog.QueryAsync passes through to mcpserver-repl" {
    source "$LIB"
    run repl_invoke "client.SessionLog.QueryAsync" "limit: 1"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "type: response"
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
