#Requires -Version 7.0

# TR-MCP-REPL-012 (BUG-TRIAGE-072): REPL invocation timeouts must be per-method so long-running
# requirement/agent methods (workflow.todo.analyzeRequirements, requirements generate/ingest) get an
# extended, env-configurable budget while sessionlog methods keep the short 30s default.

Describe 'Per-method REPL timeout' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\lib\repl-invoke.ps1')
    }

    BeforeEach {
        $script:SavedEnv = @{
            REPL_TIMEOUT = $env:REPL_TIMEOUT
            REPL_LONG_TIMEOUT = $env:REPL_LONG_TIMEOUT
        }
        Remove-Item -LiteralPath Env:REPL_TIMEOUT -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath Env:REPL_LONG_TIMEOUT -ErrorAction SilentlyContinue
    }

    AfterEach {
        foreach ($pair in $script:SavedEnv.GetEnumerator()) {
            if ($null -ne $pair.Value) { Set-Item -LiteralPath "Env:$($pair.Key)" -Value $pair.Value }
            else { Remove-Item -LiteralPath "Env:$($pair.Key)" -ErrorAction SilentlyContinue }
        }
    }

    It 'gives analyzeRequirements an extended budget and keeps sessionlog at the short default' {
        Get-ReplMethodTimeoutSeconds 'workflow.todo.analyzeRequirements' | Should -BeGreaterThan 30
        Get-ReplMethodTimeoutSeconds 'workflow.requirements.generateDocument' | Should -BeGreaterThan 30
        Get-ReplMethodTimeoutSeconds 'workflow.sessionlog.completeTurn' | Should -Be 30
        Get-ReplMethodTimeoutSeconds 'workflow.sessionlog.beginTurn' | Should -Be 30
    }

    It 'honors REPL_TIMEOUT for the short default and REPL_LONG_TIMEOUT for long methods' {
        $env:REPL_TIMEOUT = '45'
        $env:REPL_LONG_TIMEOUT = '600'
        Get-ReplMethodTimeoutSeconds 'workflow.sessionlog.completeTurn' | Should -Be 45
        Get-ReplMethodTimeoutSeconds 'workflow.todo.analyzeRequirements' | Should -Be 600
    }
}
