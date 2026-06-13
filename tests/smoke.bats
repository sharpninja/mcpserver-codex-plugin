#!/usr/bin/env bats
# smoke.bats - Model C per-repo hook smoke test.
#
# Proves the migrated codex wrappers wire up to the canonical plugin core
# (lib/hook-lib.sh + lib/plugin-env.sh) and emit valid output, with no marker
# reachable and no network. This is the thin host-neutral smoke check that
# complements the CORE-MANIFEST.yaml checksum guard and the repo's
# host-specific tests; the shared-lib behavior itself is proven by the core
# fixtures in McpServer/plugins/core/test-fixtures.

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Codex wrapper locations (codex host places wrappers in lib/, depth ..).
SESSION_START_WRAPPER="$PLUGIN_ROOT/lib/session-start.sh"
USER_PROMPT_WRAPPER="$PLUGIN_ROOT/lib/user-prompt-submit.sh"

setup() {
    # Isolated, marker-free environment: a temp HOME and cwd with no
    # AGENTS-README-FIRST.yaml anywhere above them, and a temp plugin cache
    # root via PLUGIN_ROOT_OVERRIDE so nothing writes into the repo.
    SMOKE_TMP="$(mktemp -d)"
    mkdir -p "$SMOKE_TMP/home" "$SMOKE_TMP/cwd" "$SMOKE_TMP/cache"
}

teardown() {
    [ -n "${SMOKE_TMP:-}" ] && rm -rf "$SMOKE_TMP"
}

# run_wrapper <wrapper-path> - run a codex hook wrapper under the isolated,
# marker-free environment with empty stdin. Populates $status and $output.
run_wrapper() {
    local wrapper="$1"
    run env -i \
        HOME="$SMOKE_TMP/home" \
        PATH="$PATH" \
        PLUGIN_ROOT_OVERRIDE="$SMOKE_TMP/cache" \
        MCP_PLUGIN_ROOT="$PLUGIN_ROOT" \
        bash -c 'cd "$1" && bash "$2" </dev/null' _ "$SMOKE_TMP/cwd" "$wrapper"
}

# assert_valid_json <text> - prove the text parses as JSON. Prefers node
# (always present in CI per core-guard), and is host-neutral: when node is
# absent we fall back to a non-empty + brace-shaped check so the smoke test
# never depends on a network or a specific parser.
assert_valid_json() {
    local text="$1"
    [ -n "$text" ]
    if command -v node >/dev/null 2>&1; then
        printf '%s' "$text" | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))'
    else
        # Minimal structural sanity check when no JSON parser is available.
        case "$text" in
            "{"*"}"*) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

@test "wrappers and canonical lib are present after migration" {
    [ -s "$SESSION_START_WRAPPER" ]
    [ -s "$USER_PROMPT_WRAPPER" ]
    [ -s "$PLUGIN_ROOT/lib/hook-lib.sh" ]
    [ -s "$PLUGIN_ROOT/lib/plugin-env.sh" ]
    # Wrappers must delegate into the canonical hook-lib entry functions.
    grep -q 'lib/hook-lib.sh' "$SESSION_START_WRAPPER"
    grep -q 'session_start_main' "$SESSION_START_WRAPPER"
    grep -q 'lib/hook-lib.sh' "$USER_PROMPT_WRAPPER"
    grep -q 'user_prompt_submit_main' "$USER_PROMPT_WRAPPER"
}

@test "session-start wrapper emits valid JSON and signals untrusted with no marker" {
    run_wrapper "$SESSION_START_WRAPPER"
    # Codex cli-mode deliberately exits non-zero to signal MCP is untrusted;
    # the wrapper must still run cleanly (no crash) and emit valid JSON.
    [ "$status" -lt 100 ]
    assert_valid_json "$output"
    [[ "$output" == *'untrusted'* ]]
}

@test "user-prompt-submit wrapper exits 0 and emits valid JSON with no marker" {
    run_wrapper "$USER_PROMPT_WRAPPER"
    [ "$status" -eq 0 ]
    assert_valid_json "$output"
}
