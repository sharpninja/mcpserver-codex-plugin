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

setup() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "$SANDBOX/cache"

    export CODEX_PLUGIN_ROOT="$PLUGIN_ROOT"
    export PLUGIN_ROOT_OVERRIDE="$SANDBOX"
    unset CLAUDE_STOP_HOOK_ACTIVE
}

teardown() {
    rm -rf "$SANDBOX"
}

write_turn() {
    local status="${1:-in_progress}" edits="${2:-0}" build="${3:-unknown}"
    cat > "$SANDBOX/cache/current-turn.yaml" <<EOF
turnRequestId: req-test-stop-001
queryTitle: Stop gate test
openedAt: 2026-04-19T00:00:00Z
status: ${status}
codeEdits: ${edits}
lastBuildStatus: ${build}
EOF
}

run_stop_gate() {
    bash "$STOP_GATE" </dev/null 2>/dev/null
}

@test "no turn file → no-turn status" {
    rm -f "$SANDBOX/cache/current-turn.yaml"
    out="$(run_stop_gate)"
    echo "$out" | grep -qF '"status":"no-turn"'
}

@test "in_progress turn → decision:block" {
    write_turn "in_progress"
    out="$(run_stop_gate)"
    echo "$out" | grep -qF '"decision":"block"'
}

@test "in_progress block reason names turn id" {
    write_turn "in_progress"
    out="$(run_stop_gate)"
    echo "$out" | grep -qF "req-test-stop-001"
}

@test "completed turn (clean build) → status:passed" {
    write_turn "completed"
    out="$(run_stop_gate)"
    echo "$out" | grep -qF '"status":"passed"'
}

@test "completed turn with failed build + edits → decision:block" {
    write_turn "completed" 3 "failed"
    out="$(run_stop_gate)"
    echo "$out" | grep -qF '"decision":"block"'
    echo "$out" | grep -qF "code edit"
}

@test "accept-failure marker unblocks failed-build stop" {
    write_turn "completed" 3 "failed"
    touch "$SANDBOX/cache/turn-accept-failure.marker"
    out="$(run_stop_gate)"
    echo "$out" | grep -qF '"status":"passed"'
}

@test "accept-failure marker is consumed (deleted) after use" {
    write_turn "completed" 3 "failed"
    touch "$SANDBOX/cache/turn-accept-failure.marker"
    run_stop_gate >/dev/null
    [ ! -f "$SANDBOX/cache/turn-accept-failure.marker" ]
}

@test "end-to-end: shim's completeTurn flips cache so stop-gate passes" {
    write_turn "in_progress"

    cat > "$SANDBOX/cache/session-state.yaml" <<EOF
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

    status_after="$(grep '^status:' "$SANDBOX/cache/current-turn.yaml" | head -1 | sed 's/^status:[[:space:]]*//')"
    [ "$status_after" = "completed" ]

    out="$(run_stop_gate)"
    echo "$out" | grep -qF '"status":"passed"'
}

@test "CLAUDE_STOP_HOOK_ACTIVE=true short-circuits to already-reprompted" {
    write_turn "in_progress"
    export CLAUDE_STOP_HOOK_ACTIVE=true
    out="$(run_stop_gate)"
    unset CLAUDE_STOP_HOOK_ACTIVE
    echo "$out" | grep -qF '"status":"already-reprompted"'
}
