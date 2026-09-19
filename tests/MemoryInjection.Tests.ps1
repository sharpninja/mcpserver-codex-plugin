#Requires -Version 7.0

Describe 'Codex UserPromptSubmit required-memory injection' {
    BeforeAll {
        $script:PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
        $script:MemoryContext = @(
            (Join-Path $script:PluginRoot 'lib/memory-context.ps1')
            (Join-Path $script:PluginRoot 'hooks/scripts/memory-context.ps1')
        ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        $script:UserPrompt = @(
            (Join-Path $script:PluginRoot 'lib/user-prompt-submit.ps1')
            (Join-Path $script:PluginRoot 'hooks/scripts/user-prompt-submit.ps1')
        ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        $script:InvokeScript = Join-Path $script:PluginRoot 'skills/memory/scripts/invoke.ps1'
        . $script:MemoryContext
    }

    BeforeEach {
        $script:SavedEnv = @{
            MCP_CACHE_DIR_OVERRIDE = $env:MCP_CACHE_DIR_OVERRIDE
            MCP_AGENT_NAME = $env:MCP_AGENT_NAME
            MCP_PLUGIN_REPL_LOG = $env:MCP_PLUGIN_REPL_LOG
            MCP_PLUGIN_REPL_RESPONSE = $env:MCP_PLUGIN_REPL_RESPONSE
            MCP_MEMORY_REPL_RESPONSE = $env:MCP_MEMORY_REPL_RESPONSE
            MCP_MEMORY_DESCRIPTOR_PATH = $env:MCP_MEMORY_DESCRIPTOR_PATH
            MCP_MEMORY_FETCH_ERROR = $env:MCP_MEMORY_FETCH_ERROR
            MCP_WORKSPACE_START_DIR = $env:MCP_WORKSPACE_START_DIR
            MCP_PLUGIN_ROOT = $env:MCP_PLUGIN_ROOT
            MCP_PLUGIN_HOST = $env:MCP_PLUGIN_HOST
        }

        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mcp-memory-inject-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($script:TestRoot)
        $env:MCP_PLUGIN_ROOT = $script:PluginRoot
        $env:MCP_PLUGIN_HOST = 'codex'
        $env:MCP_CACHE_DIR_OVERRIDE = $script:TestRoot
        $env:MCP_AGENT_NAME = 'Codex'
        $env:MCP_PLUGIN_REPL_LOG = Join-Path $script:TestRoot 'repl-log.txt'
        [System.IO.File]::WriteAllText($env:MCP_PLUGIN_REPL_LOG, '')
        $env:MCP_PLUGIN_REPL_RESPONSE = "type: result`npayload:`n  result:`n    ok: true`n"
        Remove-Item -LiteralPath Env:MCP_MEMORY_REPL_RESPONSE -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath Env:MCP_MEMORY_FETCH_ERROR -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath Env:MCP_MEMORY_DESCRIPTOR_PATH -ErrorAction SilentlyContinue

        $markerPath = Join-Path $script:TestRoot 'AGENTS-README-FIRST.yaml'
        [System.IO.File]::WriteAllText($markerPath, @"
workspace: TestWorkspace
workspacePath: $script:TestRoot
baseUrl: http://127.0.0.1:59999/mcpserver
apiKey: test-marker-key
"@.Trim() + "`n")
        $env:MCP_WORKSPACE_START_DIR = $script:TestRoot
        $resolvedMarker = (Resolve-Path -LiteralPath $markerPath).ProviderPath
        $markerMtime = (Get-Item -LiteralPath $resolvedMarker).LastWriteTimeUtc.ToString('O')
        [System.IO.File]::WriteAllText((Join-Path $script:TestRoot 'session-state.yaml'), @"
sessionId: Codex-20260714T000000Z-plugin-session
agent: Codex
status: verified
markerFilePath: '$resolvedMarker'
markerLastWriteUtc: '$markerMtime'
"@.Trim() + "`n")
    }

    AfterEach {
        foreach ($pair in $script:SavedEnv.GetEnumerator()) {
            if ($null -ne $pair.Value) {
                Set-Item -LiteralPath "Env:$($pair.Key)" -Value $pair.Value
            } else {
                Remove-Item -LiteralPath "Env:$($pair.Key)" -ErrorAction SilentlyContinue
            }
        }
        if (Test-Path -LiteralPath $script:TestRoot) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'loads the host descriptor and maps memory_* aliases to workflow.memory.*' {
        $descriptor = Get-McpMemoryDescriptor -PluginRoot $script:PluginRoot
        $descriptor.loaded | Should -BeTrue
        $descriptor.path | Should -Match 'memory-descriptor\.json$'
        $descriptor.host | Should -Be 'codex'
        $descriptor.injection.requiredMemoriesPrefix | Should -Be 'REQUIRED MEMORIES -'
        $descriptor.injection.emptyFallback | Should -Be 'REQUIRED MEMORIES - None.'
        Resolve-McpMemoryWorkflowMethod -Name 'memory_remember' -Descriptor $descriptor | Should -Be 'workflow.memory.remember'
        Resolve-McpMemoryWorkflowMethod -Name 'workflow.memory.list' -Descriptor $descriptor | Should -Be 'workflow.memory.list'
    }

    It 'renders explicit None when the stubbed memory fetch is empty' {
        $context = Get-McpRequiredMemoryContext -PluginRoot $script:PluginRoot -FetchOverride { '' }
        $context | Should -Be 'REQUIRED MEMORIES - None.'
    }

    It 'renders descriptor prefix plus raw memory text from a stubbed fetch' {
        $yaml = @'
type: result
payload:
  result:
    items:
      - id: MEMORY-REQ-001
        text: Raw memory text.
'@
        $context = Get-McpRequiredMemoryContext -PluginRoot $script:PluginRoot -FetchOverride { $yaml }
        $context | Should -Be 'REQUIRED MEMORIES - MEMORY-REQ-001: Raw memory text.'
    }

    It 'uses a custom descriptor path for prefix and empty fallback' {
        $custom = Join-Path $script:TestRoot 'custom-memory-descriptor.json'
        [System.IO.File]::WriteAllText($custom, (@{
            host = 'codex'
            injection = @{
                requiredMemoriesPrefix = 'CUSTOM MEMORIES -'
                emptyFallback = 'CUSTOM MEMORIES - None.'
            }
            tools = @('memory_list')
            workflowMethods = @{ memory_list = 'workflow.memory.list' }
        } | ConvertTo-Json -Depth 10))
        $env:MCP_MEMORY_DESCRIPTOR_PATH = $custom
        $context = Get-McpRequiredMemoryContext -PluginRoot $script:PluginRoot -FetchOverride { '' }
        $context | Should -Be 'CUSTOM MEMORIES - None.'
    }

    It 'fail-softs to None when the memory fetch throws' {
        $context = Get-McpRequiredMemoryContext -PluginRoot $script:PluginRoot -FetchOverride { throw 'mcp unavailable' }
        $context | Should -Be 'REQUIRED MEMORIES - None.'
    }

    It 'merges stubbed memories into UserPromptSubmit hook JSON using the descriptor' {
        $custom = Join-Path $script:TestRoot 'merge-memory-descriptor.json'
        [System.IO.File]::WriteAllText($custom, (@{
            host = 'codex'
            injection = @{
                requiredMemoriesPrefix = 'HOOK MEMORIES -'
                emptyFallback = 'HOOK MEMORIES - None.'
            }
            tools = @('memory_list')
        } | ConvertTo-Json -Depth 10))
        $hookJson = '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","status":"turn-opened","turnRequestId":"req-test","additionalContext":"session log turn req-test is now active."}}'
        $merged = Add-McpRequiredMemoryToHookOutput `
            -HookOutput $hookJson `
            -PluginRoot $script:PluginRoot `
            -DescriptorPath $custom `
            -FetchOverride { '{"payload":{"result":{"items":[{"id":"MEMORY-REQ-001","text":"Descriptor-driven injection."}]}}}' }
        $merged | Should -Match 'HOOK MEMORIES - MEMORY-REQ-001: Descriptor-driven injection\.'
        $merged | Should -Match 'session log turn req-test is now active\.'
        $obj = $merged | ConvertFrom-Json
        $obj.hookSpecificOutput.hookEventName | Should -Be 'UserPromptSubmit'
    }

    It 'user-prompt-submit reads the descriptor and injects stubbed memories into additionalContext' {
        $custom = Join-Path $script:TestRoot 'hook-memory-descriptor.json'
        [System.IO.File]::WriteAllText($custom, (@{
            host = 'codex'
            injection = @{
                requiredMemoriesPrefix = 'REQUIRED MEMORIES -'
                emptyFallback = 'REQUIRED MEMORIES - None.'
            }
            tools = @('memory_list')
            workflowMethods = @{ memory_list = 'workflow.memory.list' }
        } | ConvertTo-Json -Depth 10))
        $env:MCP_MEMORY_DESCRIPTOR_PATH = $custom
        $env:MCP_MEMORY_REPL_RESPONSE = @'
type: result
payload:
  result:
    items:
      - id: MEMORY-REQ-001
        text: Injected at the request boundary.
'@

        $params = @{ prompt = 'remember the current workspace convention' } | ConvertTo-Json -Compress
        $output = & $script:UserPrompt -Params $params 2>&1 | Out-String

        $output | Should -Match 'REQUIRED MEMORIES - MEMORY-REQ-001: Injected at the request boundary\.'
        $output | Should -Match 'additionalContext'
        $log = [System.IO.File]::ReadAllText($env:MCP_PLUGIN_REPL_LOG)
        $log | Should -Match 'workflow\.memory\.list'
        $log | Should -Match 'scope: Effective'
    }

    It 'user-prompt-submit injects explicit None and keeps going when memory fetch fails' {
        $env:MCP_MEMORY_FETCH_ERROR = '1'
        $params = @{ prompt = 'continue without memory server' } | ConvertTo-Json -Compress
        $output = & $script:UserPrompt -Params $params 2>&1 | Out-String

        $output | Should -Match 'REQUIRED MEMORIES - None\.'
        $LASTEXITCODE | Should -Be 0
    }

    It 'invoke.ps1 resolves memory_* aliases through the descriptor registry' {
        $env:MCP_MEMORY_REPL_RESPONSE = "type: result`npayload:`n  result:`n    ok: true`n"
        $null = & $script:InvokeScript -Name memory_recall -ParamsYaml "query: auth" -PluginRoot $script:PluginRoot
        $log = [System.IO.File]::ReadAllText($env:MCP_PLUGIN_REPL_LOG)
        $log | Should -Match 'workflow\.memory\.recall'
        $log | Should -Match 'query: auth'
    }
}
