#!/usr/bin/env bats
# Backfilled from mcpserver-marketplace/plugins/mcpserver/tests/hooks/stop-gate.test.sh.
# Guards the contract between the workflow.sessionlog.* shim in
# lib/repl-invoke.sh and the Stop hook (lib/stop-gate.sh).
#
# NOTE: codex layout differs from the other plugins — stop-gate.sh lives at
# lib/stop-gate.sh (not hooks/scripts/), and it resolves its plugin root via
# CODEX_PLUGIN_ROOT (not CLAUDE_PLUGIN_ROOT or PLUGIN_ROOT).
#
# Original regression: shim never flipped current-turn.yaml status, so
# stop-gate.sh blocked every Stop with the in_progress reason. This suite
# exercises both sides plus their end-to-end contract.

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB="$PLUGIN_ROOT/lib/repl-invoke.sh"
STOP_GATE="$PLUGIN_ROOT/lib/stop-gate.sh"
source "$PLUGIN_ROOT/tests/cache-scope-helper.bash"

setup() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "$SANDBOX/bin" "$SANDBOX/workspace"
    init_test_cache "$SANDBOX/workspace" "Codex-20260419T000000Z-stop"

    cat > "$SANDBOX/bin/mcpserver-repl" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
printf 'type: response\npayload:\n  ok: true\n'
EOF
    chmod +x "$SANDBOX/bin/mcpserver-repl"

    cat > "$SANDBOX/bin/pwsh.exe" <<'EOF'
#!/usr/bin/env bash
printf '0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF\n'
EOF
    chmod +x "$SANDBOX/bin/pwsh.exe"

    cat > "$SANDBOX/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
printf '0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF\n'
EOF
    chmod +x "$SANDBOX/bin/powershell.exe"

    export PATH="$SANDBOX/bin:$PATH"
    export REPL_TIMEOUT=1
    export CODEX_PLUGIN_ROOT="$PLUGIN_ROOT"
    export PLUGIN_ROOT_OVERRIDE="$SANDBOX"
    unset CLAUDE_STOP_HOOK_ACTIVE
}

teardown() {
    rm -rf "$SANDBOX"
}

write_turn() {
    local status="${1:-in_progress}" edits="${2:-0}" build="${3:-unknown}"
    refresh_test_cache
    cat > "$TEST_CACHE_DIR/current-turn.yaml" <<EOF
turnRequestId: req-test-stop-001
queryTitle: Stop gate test
openedAt: 2026-04-19T00:00:00Z
status: ${status}
codeEdits: ${edits}
lastBuildStatus: ${build}
EOF
}

run_stop_gate() {
    run bash "$STOP_GATE"
}

@test "no turn file → schema-valid no-op output" {
    rm -f "$(test_cache_file current-turn.yaml)"
    run_stop_gate
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

@test "in_progress turn self-heals to passed when repl-invoke is available" {
    write_turn "in_progress"
    run_stop_gate
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

@test "in_progress turn blocks when repl-invoke cannot be loaded" {
    cat > "$SANDBOX/cache/current-turn.yaml" <<EOF
turnRequestId: req-test-stop-001
queryTitle: Stop gate test
openedAt: 2026-04-19T00:00:00Z
status: in_progress
codeEdits: 0
lastBuildStatus: unknown
EOF
    export CODEX_PLUGIN_ROOT="$SANDBOX/missing-plugin-root"
    run_stop_gate
    export CODEX_PLUGIN_ROOT="$PLUGIN_ROOT"
    [ "$status" -eq 0 ]
    grep -qF '"decision":"block"' <<<"$output"
    grep -qF "req-test-stop-001" <<<"$output"
}

@test "completed turn (clean build) → schema-valid no-op output" {
    write_turn "completed"
    run_stop_gate
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

@test "completed turn with failed build + edits → decision:block" {
    write_turn "completed" 3 "failed"
    run_stop_gate
    [ "$status" -eq 0 ]
    grep -qF '"decision":"block"' <<<"$output"
    grep -qF "code edit" <<<"$output"
}

@test "accept-failure marker unblocks failed-build stop" {
    write_turn "completed" 3 "failed"
    touch "$(test_cache_file turn-accept-failure.marker)"
    run_stop_gate
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

@test "accept-failure marker is consumed (deleted) after use" {
    write_turn "completed" 3 "failed"
    marker_file="$(test_cache_file turn-accept-failure.marker)"
    touch "$marker_file"
    run_stop_gate
    [ "$status" -eq 0 ]
    [ ! -f "$marker_file" ]
}

@test "end-to-end: shim's completeTurn flips cache so stop-gate passes" {
    write_turn "in_progress"

    cat > "$TEST_CACHE_DIR/session-state.yaml" <<EOF
status: verified
sessionId: Codex-20260419T000000Z-test
workspacePath: "/tmp/ws"
workspace: "test"
baseUrl: "http://localhost:1"
timestamp: "2026-04-19T00:00:00Z"
EOF

    # shellcheck source=/dev/null
    ( source "$LIB" && repl_invoke "workflow.sessionlog.completeTurn" "requestId: req-test-stop-001
response: |
  E2E test response." ) >/dev/null 2>&1

    status_after="$(grep '^status:' "$(test_cache_file current-turn.yaml)" | head -1 | sed 's/^status:[[:space:]]*//')"
    [ "$status_after" = "completed" ]

    run_stop_gate
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

@test "CLAUDE_STOP_HOOK_ACTIVE=true short-circuits with schema-valid no-op" {
    write_turn "in_progress"
    export CLAUDE_STOP_HOOK_ACTIVE=true
    run_stop_gate
    unset CLAUDE_STOP_HOOK_ACTIVE
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}
