#Requires -Version 7.0

# triage-report-7c84e6437f7b42d0a67fbe32679a686a: an inherited MCP_WORKSPACE_PATH from another
# workspace (leaked through a host process or persistent console) must not out-rank the
# marker-bearing current directory, or every repl call re-binds marker trust, API keys, and
# session logs to the wrong workspace while the cache directory stays local.

Describe 'Resolve-ReplWorkspaceDirectory precedence' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\lib\repl-invoke.ps1')
    }

    BeforeEach {
        $script:SavedEnv = @{
            MCP_WORKSPACE_PATH = $env:MCP_WORKSPACE_PATH
            MCPSERVER_WORKSPACE_PATH = $env:MCPSERVER_WORKSPACE_PATH
            MCP_WORKSPACE_START_DIR = $env:MCP_WORKSPACE_START_DIR
            CLAUDE_PROJECT_DIR = $env:CLAUDE_PROJECT_DIR
        }
        foreach ($name in @($script:SavedEnv.Keys)) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }

        $script:SavedLocation = (Get-Location).Path
        $script:WorkspaceA = Join-Path $env:TEMP ('mcp-ws-a-' + [guid]::NewGuid().ToString('N'))
        $script:WorkspaceB = Join-Path $env:TEMP ('mcp-ws-b-' + [guid]::NewGuid().ToString('N'))
        $script:MarkerlessDir = Join-Path $env:TEMP ('mcp-ws-none-' + [guid]::NewGuid().ToString('N'))
        foreach ($dir in @($script:WorkspaceA, $script:WorkspaceB, $script:MarkerlessDir)) {
            [void][System.IO.Directory]::CreateDirectory($dir)
        }
        [System.IO.File]::WriteAllText((Join-Path $script:WorkspaceA 'AGENTS-README-FIRST.yaml'), "workspace: A`n")
        [System.IO.File]::WriteAllText((Join-Path $script:WorkspaceB 'AGENTS-README-FIRST.yaml'), "workspace: B`n")
    }

    AfterEach {
        Set-Location -LiteralPath $script:SavedLocation
        foreach ($pair in $script:SavedEnv.GetEnumerator()) {
            if ($null -ne $pair.Value) {
                Set-Item -LiteralPath "Env:$($pair.Key)" -Value $pair.Value
            } else {
                Remove-Item -LiteralPath "Env:$($pair.Key)" -ErrorAction SilentlyContinue
            }
        }
        foreach ($dir in @($script:WorkspaceA, $script:WorkspaceB, $script:MarkerlessDir)) {
            if (Test-Path -LiteralPath $dir) {
                Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'prefers the marker-bearing current directory over an inherited MCP_WORKSPACE_PATH' {
        Set-Location -LiteralPath $script:WorkspaceA
        $env:MCP_WORKSPACE_PATH = $script:WorkspaceB

        $resolved = Resolve-ReplWorkspaceDirectory

        $resolved | Should -Be ((Resolve-Path -LiteralPath $script:WorkspaceA).ProviderPath)
    }

    It 'falls back to MCP_WORKSPACE_PATH when the current directory has no marker' {
        Set-Location -LiteralPath $script:MarkerlessDir
        $env:MCP_WORKSPACE_PATH = $script:WorkspaceB

        $resolved = Resolve-ReplWorkspaceDirectory

        $resolved | Should -Be ((Resolve-Path -LiteralPath $script:WorkspaceB).ProviderPath)
    }

    It 'falls back to the current directory when no workspace env vars are set' {
        Set-Location -LiteralPath $script:MarkerlessDir

        $resolved = Resolve-ReplWorkspaceDirectory

        $resolved | Should -Be ((Resolve-Path -LiteralPath $script:MarkerlessDir).ProviderPath)
    }
}
