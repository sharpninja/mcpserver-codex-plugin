#Requires -Version 7.0

Describe 'Official plugin PowerShell native smoke' {
    BeforeAll {
        $script:PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
        $codexWrapper = Join-Path $script:PluginRoot 'lib\session-start.ps1'
        $familyWrapper = Join-Path $script:PluginRoot 'hooks\scripts\session-start.ps1'
        $script:SessionStart = if (Test-Path -LiteralPath $codexWrapper) { $codexWrapper } else { $familyWrapper }
        $script:UserPrompt = if (Test-Path -LiteralPath (Join-Path $script:PluginRoot 'lib\user-prompt-submit.ps1')) {
            Join-Path $script:PluginRoot 'lib\user-prompt-submit.ps1'
        } else {
            Join-Path $script:PluginRoot 'hooks\scripts\user-prompt-submit.ps1'
        }
    }

    It 'PowerShell session-start wrapper exists and is non-empty' {
        Test-Path -LiteralPath $script:SessionStart -PathType Leaf | Should -BeTrue
        (Get-Item -LiteralPath $script:SessionStart).Length | Should -BeGreaterThan 0
    }

    It 'PowerShell user-prompt-submit wrapper exists and is non-empty' {
        Test-Path -LiteralPath $script:UserPrompt -PathType Leaf | Should -BeTrue
        (Get-Item -LiteralPath $script:UserPrompt).Length | Should -BeGreaterThan 0
    }

    It 'runtime wrappers are PowerShell, not bash' {
        $script:SessionStart | Should -Match '\.ps1$'
        Get-ChildItem -LiteralPath (Split-Path -Parent $script:SessionStart) -Filter 'session-start.sh' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty
    }

    It 'CORE-MANIFEST.yaml exists' {
        Test-Path -LiteralPath (Join-Path $script:PluginRoot 'CORE-MANIFEST.yaml') | Should -BeTrue
    }

    It 'canonical lib-ps entrypoints exist' {
        Test-Path -LiteralPath (Join-Path $script:PluginRoot 'lib\plugin-hook.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:PluginRoot 'lib\repl-invoke.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:PluginRoot 'lib\plugin-env.ps1') | Should -BeTrue
    }

    It 'session-start wrapper emits JSON without crashing when no marker is present' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('p19-native-smoke-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($tmp)
        $saved = @{}
        foreach ($name in @(
                'MCP_WORKSPACE_PATH',
                'MCPSERVER_WORKSPACE_PATH',
                'MCP_WORKSPACE_START_DIR',
                'MCP_CACHE_DIR_OVERRIDE',
                'CLAUDE_PROJECT_DIR',
                'CODEX_CWD',
                'CODEX_WORKSPACE_PATH',
                'GROK_WORKSPACE_PATH',
                'PLUGIN_ROOT_OVERRIDE')) {
            $saved[$name] = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
        $env:MCP_CACHE_DIR_OVERRIDE = Join-Path $tmp 'cache'
        $env:MCP_WORKSPACE_START_DIR = $tmp
        $savedLocation = (Get-Location).Path
        try {
            Set-Location -LiteralPath $tmp
            $output = & pwsh.exe -NoProfile -NonInteractive -File $script:SessionStart 2>&1 | ForEach-Object { $_.ToString() }
            $text = ($output -join [Environment]::NewLine).Trim()
            $exit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
            ($exit -lt 100) | Should -BeTrue
            [string]::IsNullOrWhiteSpace($text) | Should -BeFalse
            $jsonLine = ($text -split [Environment]::NewLine | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
            [string]::IsNullOrWhiteSpace($jsonLine) | Should -BeFalse
            { $null = $jsonLine | ConvertFrom-Json } | Should -Not -Throw
        }
        finally {
            Set-Location -LiteralPath $savedLocation
            foreach ($name in $saved.Keys) {
                if ($null -ne $saved[$name]) { Set-Item -LiteralPath "Env:$name" -Value $saved[$name] }
                else { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
            }
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
