#Requires -Version 7.0

Describe 'Claude plugin skill guidance' {
    BeforeAll {
        $script:PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
        $script:SkillsRoot = Join-Path $script:PluginRoot 'skills'
    }

    It 'TEST-MCP-PLUGIN-PSONLY-001 sync-logs treats deprecated workflow metadata as success and blocks REST fallback' {
        $content = [System.IO.File]::ReadAllText((Join-Path $script:SkillsRoot 'sync-logs\SKILL.md'))

        $content | Should -Match ([regex]::Escape('deprecated: true'))
        $content | Should -Match 'migration metadata only'
        $content | Should -Match 'does not mean the wrapper is broken'
        $content | Should -Match 'empty `workflow\.sessionlog\.queryHistory` result is a valid result'
        $content | Should -Match 'Do not fall back to raw REST'
    }

    It 'TEST-MCP-PLUGIN-PSONLY-001 session skill treats deprecated workflow metadata and empty history as valid wrapper outcomes' {
        $content = [System.IO.File]::ReadAllText((Join-Path $script:SkillsRoot 'session\SKILL.md'))

        $content | Should -Match ([regex]::Escape('deprecated: true'))
        $content | Should -Match 'success metadata'
        $content | Should -Match 'not a failure signal'
        $content | Should -Match 'valid no-match result'
        $content | Should -Match 'Re-check the workspace current directory'
    }

    It 'TEST-MCP-CLEARSESSION-001 clear-session skill ends session, clears context best-effort, reloads instruction file and profile, reports ready' {
        $content = [System.IO.File]::ReadAllText((Join-Path $script:SkillsRoot 'clear-session\SKILL.md'))

        # Step 1 - end the MCP session through the workflow wrapper, never raw REST
        $content | Should -Match 'workflow\.sessionlog\.completeTurn'
        # Step 2 - best-effort programmatic clear, then per-host manual clear commands
        $content | Should -Match 'best-effort'
        $content | Should -Match ([regex]::Escape('/clear'))
        $content | Should -Match ([regex]::Escape('/new'))
        $content | Should -Match 'New Task'
        # Step 3 - reload the host-selected agent instruction file
        $content | Should -Match 'CLAUDE\.md'
        $content | Should -Match 'AGENTS\.md'
        # Step 4 - run the add-profile skill
        $content | Should -Match 'add-profile'
        # Step 5 - report ready
        $content | Should -Match 'Report ready|Ready for the next request'
        # PowerShell-only: no forbidden bash/node/.sh references in the shared skill
        $content | Should -Not -Match '(?i)\bbash\b'
        $content | Should -Not -Match '(?i)\.sh\b'
    }
}
