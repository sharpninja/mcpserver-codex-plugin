#!/usr/bin/env bats

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
source "$PLUGIN_ROOT/tests/cache-scope-helper.bash"

to_host_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

setup() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "$SANDBOX/bin" "$SANDBOX/workspace"
    export PATH="$SANDBOX/bin:$PATH"
    export PLUGIN_ROOT_OVERRIDE="$SANDBOX"
    export STUB_LOG="$SANDBOX/repl-calls.log"
    init_test_cache "$SANDBOX/workspace" "Codex-20260521T000000Z-helper"

    cat > "$SANDBOX/bin/mcpserver-repl" <<'STUB'
#!/usr/bin/env bash
input="$(cat)"
{
    printf '%s\n' "$input"
    printf '%s\n' '---'
} >> "${STUB_LOG:-/dev/null}"
printf 'type: response\npayload:\n  ok: true\n'
STUB
    chmod +x "$SANDBOX/bin/mcpserver-repl"
}

teardown() {
    rm -rf "$SANDBOX"
}

write_turn_state() {
    cat > "$(test_cache_file session-state.yaml)" <<EOF
sourceType: Codex
sessionId: $TEST_SESSION_ID
status: verified
EOF

    cat > "$(test_cache_file current-turn.yaml)" <<EOF
sourceType: Codex
sessionId: $TEST_SESSION_ID
turnRequestId: req-helper-001
queryTitle: helper test
status: in_progress
codeEdits: 0
EOF
}

@test "mcp.codex.status reports cache, marker, session, turn, and namespaces" {
    write_turn_state

    run bash -c 'cd "$1" && "$2/lib/mcp.codex.status.sh"' _ "$TEST_WORKSPACE" "$PLUGIN_ROOT"

    [ "$status" -eq 0 ]
    grep -Fq "mcp.codex.status:" <<<"$output"
    grep -Fq "cacheDir:" <<<"$output"
    grep -Fq "trust: 'missing'" <<<"$output"
    grep -Fq "sessionId: '$TEST_SESSION_ID'" <<<"$output"
    grep -Fq "turnRequestId: 'req-helper-001'" <<<"$output"
    grep -Fq "workflow.todo" <<<"$output"
    grep -Fq "completeTurn:" <<<"$output"
}

@test "final-response helper completes the scoped current turn" {
    write_turn_state

    run bash "$PLUGIN_ROOT/lib/final-response.sh" "completed by helper"

    [ "$status" -eq 0 ]
    grep -q '^status: completed' "$(test_cache_file current-turn.yaml)"
}

@test "PowerShell wrapper passes params through native parameter without shell expansion" {
    write_turn_state
    pwsh_bin="$(command -v pwsh.exe || command -v pwsh || true)"
    [ -n "$pwsh_bin" ] || skip "pwsh is not available"

    run "$pwsh_bin" -NoLogo -NoProfile -File "$(to_host_path "$PLUGIN_ROOT/Invoke-CodexMcpPlugin.ps1")" \
        -Command Invoke \
        -Method client.Todo.QueryAsync \
        -Params 'keyword: $(cat /should-not-run)' \
        -PluginRoot "$(to_host_path "$PLUGIN_ROOT")" \
        -CacheRoot "$(to_host_path "$SANDBOX")" \
        -WorkspacePath "$(to_host_path "$TEST_WORKSPACE")" \
        -BashPath "$(to_host_path "$BASH")"

    [ "$status" -eq 0 ]
    grep -Fq 'keyword: $(cat /should-not-run)' "$STUB_LOG"
}

@test "PowerShell wrapper passes params through stdin without shell expansion" {
    write_turn_state
    pwsh_bin="$(command -v pwsh.exe || command -v pwsh || true)"
    [ -n "$pwsh_bin" ] || skip "pwsh is not available"

    run bash -c '
        printf "%s\n" "keyword: from-stdin" "literal: \$(cat /should-not-run)" |
            "$1" -NoLogo -NoProfile -File "$2" \
                -Command Invoke \
                -Method client.Todo.QueryAsync \
                -PluginRoot "$3" \
                -CacheRoot "$4" \
                -WorkspacePath "$5" \
                -BashPath "$6"
    ' _ \
        "$pwsh_bin" \
        "$(to_host_path "$PLUGIN_ROOT/Invoke-CodexMcpPlugin.ps1")" \
        "$(to_host_path "$PLUGIN_ROOT")" \
        "$(to_host_path "$SANDBOX")" \
        "$(to_host_path "$TEST_WORKSPACE")" \
        "$(to_host_path "$BASH")"

    [ "$status" -eq 0 ]
    grep -Fq 'keyword: from-stdin' "$STUB_LOG"
    grep -Fq 'literal: $(cat /should-not-run)' "$STUB_LOG"
}

@test "PowerShell wrapper status prefers Git Bash by default" {
    write_turn_state
    pwsh_bin="$(command -v pwsh.exe || command -v pwsh || true)"
    [ -n "$pwsh_bin" ] || skip "pwsh is not available"

    run "$pwsh_bin" -NoLogo -NoProfile -File "$(to_host_path "$PLUGIN_ROOT/Invoke-CodexMcpPlugin.ps1")" \
        -Command Status \
        -PluginRoot "$(to_host_path "$PLUGIN_ROOT")" \
        -CacheRoot "$(to_host_path "$SANDBOX")" \
        -WorkspacePath "$(to_host_path "$TEST_WORKSPACE")"

    [ "$status" -eq 0 ]
    grep -Fq "mcp.codex.status:" <<<"$output"
    grep -Fq "turnRequestId: 'req-helper-001'" <<<"$output"
}
