#Requires -Version 7.0

# TR-MCP-REPL-011 (BUG-TRIAGE-085): composed plugin session ids must use a PascalCase source-type
# agent segment (never lowercase 'default') so they satisfy the server regex, and openSession must
# persist an explicit sessionId into session-state.yaml instead of being a no-op.

Describe 'Canonical PascalCase agent + openSession persistence' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\lib\repl-invoke.ps1')
    }

    It 'maps default and lowercase hosts to a PascalCase agent matching the server regex' {
        (Get-ReplCanonicalAgentName 'default') | Should -Match '^[A-Z][A-Za-z0-9]*$'
        (Get-ReplCanonicalAgentName 'default') | Should -BeExactly 'Default'
        Get-ReplCanonicalAgentName 'claude-code' | Should -Be 'ClaudeCode'
        Get-ReplCanonicalAgentName 'claudecode' | Should -Be 'ClaudeCode'
        Get-ReplCanonicalAgentName 'codex' | Should -Be 'Codex'
        Get-ReplCanonicalAgentName 'grok' | Should -Be 'GrokCode'
    }

    It 'openSession persists the explicit sessionId into session-state.yaml' {
        $savedCache = $env:MCP_CACHE_DIR_OVERRIDE
        $testRoot = Join-Path $env:TEMP ('mcp-opensession-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($testRoot)
        $env:MCP_CACHE_DIR_OVERRIDE = $testRoot
        try {
            $ok = Invoke-WorkflowOpenSession -ParamsYaml "sessionId: ClaudeCode-20260716T030000Z-explicit"
            $ok | Should -BeTrue

            $state = Read-McpYamlObject -Path (Join-Path $testRoot 'session-state.yaml')
            [string]$state['sessionId'] | Should -Be 'ClaudeCode-20260716T030000Z-explicit'
            [string]$state['status'] | Should -Be 'verified'
        }
        finally {
            if ($null -ne $savedCache) { $env:MCP_CACHE_DIR_OVERRIDE = $savedCache }
            else { Remove-Item -LiteralPath Env:MCP_CACHE_DIR_OVERRIDE -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
