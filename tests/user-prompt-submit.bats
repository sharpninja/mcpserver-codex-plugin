#!/usr/bin/env bats

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
USER_PROMPT_SUBMIT="$PLUGIN_ROOT/lib/user-prompt-submit.sh"

setup() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "$SANDBOX/cache" "$SANDBOX/bin"

    cat > "$SANDBOX/cache/session-state.yaml" <<'EOF'
status: verified
sessionId: Codex-20260423T000000Z-test
sourceType: Codex
title: Prompt submit test
model: gpt-5.4
started: 2026-04-23T00:00:00Z
lastUpdated: 2026-04-23T00:00:00Z
workspacePath: "/tmp/ws"
workspace: "test"
baseUrl: "http://localhost:1"
timestamp: "2026-04-23T00:00:00Z"
EOF

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

@test "user-prompt-submit opens a turn, writes cache, and emits MCP-first reminder" {
    payload='{"prompt":"Investigate the failing Android flow."}'

    run bash "$USER_PROMPT_SUBMIT" <<<"$payload"

    [ "$status" -eq 0 ]
    grep -q '"status":"turn-opened"' <<<"$output"
    [ -f "$SANDBOX/cache/current-turn.yaml" ]
    grep -q '^status: in_progress' "$SANDBOX/cache/current-turn.yaml"
    grep -q '^turnRequestId: req-' "$SANDBOX/cache/current-turn.yaml"

    if command -v python3 >/dev/null 2>&1; then
        python3 - <<'PY' "$output"
import json
import sys

doc = json.loads(sys.argv[1])
context = doc["hookSpecificOutput"]["additionalContext"]
assert "Prefer session/task state and recent checkpoints" in context
assert "Use TODO and requirements tools only as needed." in context
assert "adb_step for screenshot -> inspect -> act -> screenshot loops." in context
assert "Run code-verify.sh after source edits and stop-gate.sh before the final response." in context
assert context.index("Prefer session/task state and recent checkpoints") < context.index("Run code-verify.sh after source edits")
PY
    elif command -v node >/dev/null 2>&1; then
        node -e '
const doc = JSON.parse(process.argv[1]);
const context = doc.hookSpecificOutput.additionalContext;
if (!context.includes("Prefer session/task state and recent checkpoints")) process.exit(1);
if (!context.includes("Use TODO and requirements tools only as needed.")) process.exit(1);
if (!context.includes("adb_step for screenshot -> inspect -> act -> screenshot loops.")) process.exit(1);
if (!context.includes("Run code-verify.sh after source edits and stop-gate.sh before the final response.")) process.exit(1);
if (context.indexOf("Prefer session/task state and recent checkpoints") >= context.indexOf("Run code-verify.sh after source edits")) process.exit(1);
' "$output"
    else
        skip "No JSON parser available for hook output validation"
    fi
}
