#Requires -Version 7.0

$script:OriginalCacheOverride = $env:MCP_CACHE_DIR_OVERRIDE
$script:OriginalAgentName = $env:MCP_AGENT_NAME
$script:OriginalFailsafeDir = $env:MCPSERVER_FAILSAFE_DIR

Describe 'REPL session-log persistence bridge' {
    BeforeEach {
        $script:TestRoot = Join-Path $env:TEMP ('mcp-repl-persistence-test-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($script:TestRoot)
        $script:FailsafeDir = Join-Path $script:TestRoot 'failsafe-pending'
        [void][System.IO.Directory]::CreateDirectory($script:FailsafeDir)
        $env:MCPSERVER_FAILSAFE_DIR = $script:FailsafeDir
        [System.IO.File]::WriteAllText((Join-Path $script:TestRoot 'session-state.yaml'), @"
sessionId: TestAgent-20260709T000000Z-plugin-session
agent: TestAgent
model: codex
status: verified
"@.Trim() + "`n")
        [System.IO.File]::WriteAllText((Join-Path $script:TestRoot 'current-turn.yaml'), @"
turnRequestId: req-20260709T000001Z-prompt-0001
queryTitle: Persistence test
queryText: Verify the persistence bridge
openedAt: 2026-07-09T00:00:01Z
status: in_progress
sessionId: TestAgent-20260709T000000Z-plugin-session
"@.Trim() + "`n")
        $env:MCP_CACHE_DIR_OVERRIDE = $script:TestRoot
        $env:MCP_AGENT_NAME = 'TestAgent'
    }

    AfterEach {
        if ($null -ne $script:OriginalFailsafeDir) {
            $env:MCPSERVER_FAILSAFE_DIR = $script:OriginalFailsafeDir
        } else {
            Remove-Item -LiteralPath Env:MCPSERVER_FAILSAFE_DIR -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $script:TestRoot) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    It 'submits the canonical SubmitAsync snapshot and accepts a durable result' {
        . (Join-Path $PSScriptRoot '..\lib\repl-invoke.ps1')
        function Invoke-ReplRaw {
            param([Parameter(Mandatory)][string]$Method, [string]$ParamsYaml = '')
            $script:ObservedMethod = $Method
            $script:ObservedPayload = $ParamsYaml
            return [pscustomobject]@{
                Success = $true
                Output = "type: result`npayload:`n  result:`n    persisted: true`n"
                Error = ''
                ExitCode = 0
            }
        }

        $result = Invoke-ReplPersistTurn `
            -RequestId 'req-20260709T000001Z-prompt-0001' `
            -Title 'Persistence test' `
            -Status 'completed' `
            -ResponseText 'completed'

        $result | Should -BeTrue
        $script:ObservedMethod | Should -Be 'client.SessionLog.SubmitAsync'
        $script:ObservedPayload | Should -Match 'sessionLog'
        $script:LastReplPersistenceDetails.persisted | Should -BeTrue
    }

    It 'reports the core failsafe path when close completes in degraded mode' {
        . (Join-Path $PSScriptRoot '..\lib\repl-invoke.ps1')
        function Assert-ReplCurrentTurnFresh {
            param([Parameter(Mandatory)][string]$Method)
            return $true
        }
        function Invoke-ReplRaw {
            param([Parameter(Mandatory)][string]$Method, [string]$ParamsYaml = '')
            return [pscustomobject]@{
                Success = $true
                Output = @"
type: result
payload:
  result:
    persisted: true
    degraded: true
    message: MCP Session Log persistence is degraded.
    failsafePath: C:\failsafe\turn.yaml
"@
                Error = ''
                ExitCode = 0
            }
        }

        $originalError = [Console]::Error
        $errorWriter = [System.IO.StringWriter]::new()
        [Console]::SetError($errorWriter)
        try {
            $result = Invoke-WorkflowCompleteTurn -ParamsYaml 'response: Done'
        } finally {
            [Console]::SetError($originalError)
            $errorWriter.Dispose()
        }

        $result | Should -BeTrue
        $errorWriter.ToString() | Should -Match 'degraded'
        $errorWriter.ToString() | Should -Match 'C:\\failsafe\\turn\.yaml'
    }
}

$env:MCP_CACHE_DIR_OVERRIDE = $script:OriginalCacheOverride
$env:MCP_AGENT_NAME = $script:OriginalAgentName
if ($null -ne $script:OriginalFailsafeDir) {
    $env:MCPSERVER_FAILSAFE_DIR = $script:OriginalFailsafeDir
} else {
    Remove-Item -LiteralPath Env:MCPSERVER_FAILSAFE_DIR -ErrorAction SilentlyContinue
}
