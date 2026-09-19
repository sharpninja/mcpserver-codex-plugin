#!/usr/bin/env bats

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SKILL="$PLUGIN_ROOT/skills/memory/SKILL.md"
DESCRIPTOR="$PLUGIN_ROOT/memory-descriptor.json"

@test "memory skill exists and loads" {
    [ -s "$SKILL" ]
    head -1 "$SKILL" | grep -q "^---$"
    grep -q "^name: memory" "$SKILL"
    grep -q "memory_remember" "$SKILL"
    grep -q "memory_recall" "$SKILL"
    grep -q "memory_explore" "$SKILL"
    grep -q "memory_consolidate" "$SKILL"
    grep -q "memory_promote" "$SKILL"
    grep -q "workflow.memory.remember" "$SKILL"
    grep -q "workflow.memory.recall" "$SKILL"
    grep -q "workflow.memory.list" "$SKILL"
    grep -q "lib/repl-invoke.ps1" "$SKILL"
    grep -q "lib/user-prompt-submit.ps1" "$SKILL"
    grep -q "skills/memory/scripts/invoke.ps1" "$SKILL"
    grep -qi "injection" "$SKILL"
    grep -qi "fallback" "$SKILL"
    grep -q "does not register native MCP" "$SKILL"
}

@test "memory descriptor exists and lists required verbs" {
    [ -s "$DESCRIPTOR" ]
    grep -q '"host": "codex"' "$DESCRIPTOR"
    grep -q "memory_remember" "$DESCRIPTOR"
    grep -q "memory_recall" "$DESCRIPTOR"
    grep -q "memory_explore" "$DESCRIPTOR"
    grep -q "memory_consolidate" "$DESCRIPTOR"
    grep -q "memory_promote" "$DESCRIPTOR"
    grep -q "workflow.memory.remember" "$DESCRIPTOR"
    grep -q "workflow.memory.list" "$DESCRIPTOR"
    grep -q "injection" "$DESCRIPTOR"
    grep -q "fallback" "$DESCRIPTOR"
    grep -q "workflowMethods" "$DESCRIPTOR"
}

@test "user-prompt-submit hook wires memory-descriptor injection" {
    local hook="$PLUGIN_ROOT/lib/user-prompt-submit.ps1"
    local helper="$PLUGIN_ROOT/lib/memory-context.ps1"
    [ -s "$hook" ]
    [ -s "$helper" ]
    grep -q "memory-context.ps1" "$hook"
    grep -q "Add-McpRequiredMemoryToHookOutput" "$hook"
    grep -q "memory-descriptor.json" "$helper"
    grep -q "workflow.memory.list" "$helper"
    grep -q "REQUIRED MEMORIES" "$helper"
}

@test "memory-context reads the descriptor and injects stubbed required memories" {
    run pwsh -NoLogo -NoProfile -NonInteractive -Command "
        Set-Location -LiteralPath '$PLUGIN_ROOT'
        . ./lib/memory-context.ps1
        \$descriptor = Get-McpMemoryDescriptor -PluginRoot '$PLUGIN_ROOT'
        if (-not \$descriptor.loaded) { throw 'descriptor was not loaded' }
        if (\$descriptor.path -notmatch 'memory-descriptor.json') { throw 'descriptor path was not used' }
        \$hookJson = '{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"status\":\"turn-opened\",\"additionalContext\":\"turn open\"}}'
        \$merged = Add-McpRequiredMemoryToHookOutput -HookOutput \$hookJson -PluginRoot '$PLUGIN_ROOT' -FetchOverride { '{\"payload\":{\"result\":{\"items\":[{\"id\":\"MEMORY-REQ-001\",\"text\":\"Raw memory text.\"}]}}}' }
        if (\$merged -notmatch 'REQUIRED MEMORIES - MEMORY-REQ-001: Raw memory text') { throw \$merged }
        \$empty = Get-McpRequiredMemoryContext -PluginRoot '$PLUGIN_ROOT' -FetchOverride { '' }
        if (\$empty -ne 'REQUIRED MEMORIES - None.') { throw \$empty }
        \$failed = Get-McpRequiredMemoryContext -PluginRoot '$PLUGIN_ROOT' -FetchOverride { throw 'unavailable' }
        if (\$failed -ne 'REQUIRED MEMORIES - None.') { throw \$failed }
    "
    [ "$status" -eq 0 ]
}

@test "user-prompt-submit attempts descriptor-driven injection with a stubbed fetch" {
    local tmp
    tmp="$(mktemp -d)"
    cat > "$tmp/memory-descriptor.json" <<'EOF'
{
  "host": "codex",
  "injection": {
    "requiredMemoriesPrefix": "REQUIRED MEMORIES -",
    "emptyFallback": "REQUIRED MEMORIES - None."
  },
  "workflowMethods": {
    "memory_list": "workflow.memory.list"
  }
}
EOF
    local log="$tmp/repl-log.txt"
    : > "$log"
    run env MCP_PLUGIN_ROOT="$PLUGIN_ROOT" \
        MCP_MEMORY_DESCRIPTOR_PATH="$tmp/memory-descriptor.json" \
        MCP_PLUGIN_REPL_LOG="$log" \
        MCP_MEMORY_REPL_RESPONSE=$'type: result\npayload:\n  result:\n    items:\n      - id: MEMORY-REQ-001\n        text: Injected from submit hook.\n' \
        MCP_CACHE_DIR_OVERRIDE="$tmp" \
        MCP_WORKSPACE_START_DIR="$tmp" \
        pwsh -NoLogo -NoProfile -NonInteractive -File "$PLUGIN_ROOT/lib/user-prompt-submit.ps1" -Params '{"prompt":"inject memories"}'
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "REQUIRED MEMORIES - MEMORY-REQ-001: Injected from submit hook."
    grep -q "workflow.memory.list" "$log"
    grep -q "scope: Effective" "$log"
    rm -rf "$tmp"
}
