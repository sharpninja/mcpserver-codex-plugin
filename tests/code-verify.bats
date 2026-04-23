#!/usr/bin/env bats

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
CODE_VERIFY="$PLUGIN_ROOT/lib/code-verify.sh"

setup() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "$SANDBOX/cache" "$SANDBOX/bin" "$SANDBOX/project"

    cat > "$SANDBOX/cache/current-turn.yaml" <<EOF
turnRequestId: req-test-code-verify-001
queryTitle: Code verify test
openedAt: 2026-04-19T00:00:00Z
status: in_progress
codeEdits: 0
lastBuildStatus: unknown
queryText: |
  Verify the build.
EOF

    cat > "$SANDBOX/project/Test.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
</Project>
EOF
    cat > "$SANDBOX/project/Test.cs" <<'EOF'
public static class TestFile {}
EOF

    cat > "$SANDBOX/bin/dotnet" <<'EOF'
#!/usr/bin/env bash
printf 'Build succeeded.\n'
EOF
    chmod +x "$SANDBOX/bin/dotnet"

    cat > "$SANDBOX/bin/mcpserver-repl" <<'EOF'
#!/usr/bin/env bash
printf 'type: response\npayload:\n  ok: true\n'
EOF
    chmod +x "$SANDBOX/bin/mcpserver-repl"

    export PATH="$SANDBOX/bin:$PATH"
    export CODEX_PLUGIN_ROOT="$PLUGIN_ROOT"
    export PLUGIN_ROOT_OVERRIDE="$SANDBOX"
}

teardown() {
    rm -rf "$SANDBOX"
}

@test "code-verify increments codeEdits exactly once via appendActions" {
    payload="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$SANDBOX/project/Test.cs\"}}"
    run bash "$CODE_VERIFY" <<<"$payload"
    [ "$status" -eq 0 ]
    grep -q '^codeEdits: 1' "$SANDBOX/cache/current-turn.yaml"
    grep -q '^lastBuildStatus: succeeded' "$SANDBOX/cache/current-turn.yaml"
}
