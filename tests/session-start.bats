#!/usr/bin/env bats

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SESSION_START="$PLUGIN_ROOT/lib/session-start.sh"

setup() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "$SANDBOX/cache" "$SANDBOX/bin" "$SANDBOX/workspace"

    cat > "$SANDBOX/workspace/AGENTS-README-FIRST.yaml" <<'EOF'
apiKey: test-api-key
port: 8765
baseUrl: http://127.0.0.1:8765
workspace: test-workspace
workspacePath: /tmp/test-workspace
pid: 1234
startedAt: 2026-04-19T00:00:00Z
markerWrittenAtUtc: 2026-04-19T00:00:00Z
serverStartedAtUtc: 2026-04-19T00:00:00Z
endpoints:
  health: /health
signature:
  canonicalization: marker-v1
  value: TRUSTED
EOF

    cat > "$SANDBOX/bin/openssl" <<'EOF'
#!/usr/bin/env bash
printf 'SHA2-256(stdin)= TRUSTED\n'
EOF
    chmod +x "$SANDBOX/bin/openssl"

    cat > "$SANDBOX/bin/curl" <<'EOF'
#!/usr/bin/env bash
url="$*"
nonce="$(printf '%s' "$url" | sed -n 's/.*nonce=\([^& ]*\).*/\1/p')"
printf '{"status":"ok","nonce":"%s"}\n' "$nonce"
EOF
    chmod +x "$SANDBOX/bin/curl"

    cat > "$SANDBOX/bin/mcpserver-repl" <<'EOF'
#!/usr/bin/env bash
printf 'type: response\npayload:\n  ok: true\n'
EOF
    chmod +x "$SANDBOX/bin/mcpserver-repl"

    export PATH="$SANDBOX/bin:$PATH"
    export PLUGIN_ROOT_OVERRIDE="$SANDBOX"
    export CODEX_PLUGIN_ROOT="$PLUGIN_ROOT"
    export MCP_SESSION_AGENT="Codex"
    export MCP_SESSION_MODEL="gpt-5.4"
    export MCP_SESSION_TITLE="Plugin Fix Session"
}

teardown() {
    rm -rf "$SANDBOX"
}

@test "session-start bootstraps cache and opens a session" {
    run bash "$SESSION_START" "$SANDBOX/workspace"
    [ "$status" -eq 0 ]
    grep -q '"status":"verified"' <<<"$output"
    grep -q '^status: verified' "$SANDBOX/cache/session-state.yaml"
    grep -q '^sessionId: Codex-' "$SANDBOX/cache/session-state.yaml"
    grep -q '^sourceType: Codex' "$SANDBOX/cache/session-state.yaml"
}
