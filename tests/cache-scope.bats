#!/usr/bin/env bats

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    SANDBOX="$(mktemp -d)"
    export PLUGIN_ROOT_OVERRIDE="$SANDBOX"
    unset MCP_SESSION_ID MCP_WORKSPACE_PATH MCPSERVER_WORKSPACE_PATH
    # shellcheck source=../lib/cache-scope.sh
    source "$PLUGIN_ROOT/lib/cache-scope.sh"
}

teardown() {
    rm -rf "$SANDBOX"
}

@test "cache scope separates different workspaces" {
    mkdir -p "$SANDBOX/workspace-a" "$SANDBOX/workspace-b"

    cache_scope_init "$SANDBOX" "$SANDBOX/workspace-a"
    cache_scope_select_session "Codex-20260512T000000Z-a"
    a_cache="$CACHE_DIR"
    printf 'workspace: a\n' > "$a_cache/current-turn.yaml"

    cache_scope_init "$SANDBOX" "$SANDBOX/workspace-b"
    cache_scope_select_session "Codex-20260512T000000Z-b"
    b_cache="$CACHE_DIR"
    printf 'workspace: b\n' > "$b_cache/current-turn.yaml"

    [ "$a_cache" != "$b_cache" ]
    grep -q '^workspace: a' "$a_cache/current-turn.yaml"
    grep -q '^workspace: b' "$b_cache/current-turn.yaml"
}

@test "cache scope separates multiple MCP sessions in one workspace" {
    mkdir -p "$SANDBOX/workspace"

    cache_scope_init "$SANDBOX" "$SANDBOX/workspace"
    cache_scope_select_session "Codex-20260512T000000Z-first"
    first_cache="$CACHE_DIR"
    printf 'session: first\n' > "$first_cache/current-turn.yaml"

    cache_scope_select_session "Codex-20260512T000000Z-second"
    second_cache="$CACHE_DIR"
    printf 'session: second\n' > "$second_cache/current-turn.yaml"

    [ "$first_cache" != "$second_cache" ]
    grep -q '^session: first' "$first_cache/current-turn.yaml"
    grep -q '^session: second' "$second_cache/current-turn.yaml"

    cache_scope_init "$SANDBOX" "$SANDBOX/workspace"
    [ "$CACHE_DIR" = "$second_cache" ]
}
