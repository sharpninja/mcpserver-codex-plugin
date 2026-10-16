#Requires -Version 7.0
# SPDX-License-Identifier: Apache-2.0

# TR-MCP-MEMORY-008 AC-001 (PLAN-SESSIONTRIAGEFIX-001 F2, triage-report-834cec2e): the memory skill wrapper finds this plugin's
# memory-context.ps1 and dispatches memory_* names to workflow.memory.* methods through it.
# Mock gate: the dispatch assertion is proven against fixture plugin roots built from this repository's own wrapper and descriptor and a
# stand-in helper, and rejects a root without the helper, a helper outside the wrapper's search paths, and a helper that dispatches to
# another method. Binding: the same assertion against this repository's wrapper, helper and descriptor, through the helper's
# MCP_PLUGIN_REPL_LOG seam. Nothing here reaches a server.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
    $script:WrapperRelative = 'skills/memory/scripts/invoke.ps1'

    # Runs a plugin root's memory wrapper in a child pwsh with the helper's REPL log seam; returns the exit code, output and log text.
    function Invoke-MemoryWrapperProcess {
        param([Parameter(Mandatory)][string]$PluginRoot, [Parameter(Mandatory)][string]$Name)
        $log = Join-Path ([System.IO.Path]::GetTempPath()) ('memory-wrapper-' + [guid]::NewGuid().ToString('N') + '.log')
        $psi = [System.Diagnostics.ProcessStartInfo]::new((Get-Command pwsh -ErrorAction Stop).Source)
        foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', (Join-Path $PluginRoot $script:WrapperRelative), '-Name', $Name, '-PluginRoot', $PluginRoot)) {
            $psi.ArgumentList.Add($argument)
        }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        foreach ($inherited in 'MCP_PLUGIN_ROOT', 'MCP_MEMORY_DESCRIPTOR_PATH', 'MCP_MEMORY_FETCH_ERROR', 'MCP_MEMORY_REPL_RESPONSE') { [void]$psi.Environment.Remove($inherited) }
        $psi.Environment['MCP_PLUGIN_REPL_LOG'] = $log
        $psi.Environment['MCP_PLUGIN_REPL_RESPONSE'] = "type: result`npayload:`n  result:`n    ok: true"
        $process = [System.Diagnostics.Process]::Start($psi)
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $exited = $process.WaitForExit(60000)
        if (-not $exited) { try { $process.Kill($true) } catch { $null = $_ } }
        try {
            return [pscustomobject]@{
                ExitCode = $(if ($exited) { $process.ExitCode } else { $null })
                Stdout = $(if ($exited) { $stdout.Result } else { '' })
                Stderr = $(if ($exited) { $stderr.Result } else { '' })
                Log = $(if (Test-Path -LiteralPath $log) { [System.IO.File]::ReadAllText($log) } else { '' })
            }
        } finally {
            Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
        }
    }

    # TR-MCP-MEMORY-008 AC-001: the wrapper found its helper, exited 0, and dispatched memory_list to workflow.memory.list.
    function Assert-MemoryDispatchOutcome {
        param([Parameter(Mandatory)]$Outcome)
        $Outcome.Stderr | Should -Not -Match 'memory-context\.ps1 was not found'
        $Outcome.ExitCode | Should -Be 0 -Because "stderr: $($Outcome.Stderr)"
        $Outcome.Log | Should -Match '(?m)^method: workflow\.memory\.list\s*$'
    }

    # A temporary plugin root holding this repository's wrapper and descriptor and, unless HelperRelative is empty, a stand-in helper at
    # HelperRelative whose dispatch sends every name to DispatchMethod through the same MCP_PLUGIN_REPL_LOG seam.
    function Initialize-MemoryFixtureRoot {
        param([string]$HelperRelative = 'hooks/scripts/memory-context.ps1', [string]$DispatchMethod = 'workflow.memory.list')
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('memory-fixture-' + [guid]::NewGuid().ToString('N'))
        $wrapperTarget = Join-Path $root $script:WrapperRelative
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $wrapperTarget))
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot $script:WrapperRelative) -Destination $wrapperTarget
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'memory-descriptor.json') -Destination (Join-Path $root 'memory-descriptor.json')
        if ($HelperRelative) {
            $helper = Join-Path $root $HelperRelative
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $helper))
            $body = @(
                'function Get-McpMemoryDescriptor { param([string]$PluginRoot, [string]$DescriptorPath) [ordered]@{ loaded = $true; workflowMethods = [ordered]@{} } }'
                ('function Resolve-McpMemoryWorkflowMethod {{ param([string]$Name, $Descriptor) ''{0}'' }}' -f $DispatchMethod)
                'function Invoke-McpMemoryWorkflow { param([string]$Method, [string]$ParamsYaml, [string]$PluginRoot) Add-Content -LiteralPath $env:MCP_PLUGIN_REPL_LOG -Value "method: $Method"; $env:MCP_PLUGIN_REPL_RESPONSE }'
            ) -join [Environment]::NewLine
            [System.IO.File]::WriteAllText($helper, $body)
        }
        return $root
    }
}

Describe 'TR-MCP-MEMORY-008 AC-001 memory wrapper helper (mock gate)' {
    It 'MemoryDispatchAssertion_AcceptsHelperInSearchPathAndRejectsMissingMisplacedOrWrongDispatch' {
        $roots = [System.Collections.Generic.List[string]]::new()
        try {
            $correct = Initialize-MemoryFixtureRoot
            $roots.Add($correct)
            Assert-MemoryDispatchOutcome -Outcome (Invoke-MemoryWrapperProcess -PluginRoot $correct -Name 'memory_list')

            # Negative controls: no helper, a helper where no wrapper looks, and a helper that dispatches memory_list elsewhere.
            $missing = Initialize-MemoryFixtureRoot -HelperRelative ''
            $roots.Add($missing)
            { Assert-MemoryDispatchOutcome -Outcome (Invoke-MemoryWrapperProcess -PluginRoot $missing -Name 'memory_list') } | Should -Throw
            $misplaced = Initialize-MemoryFixtureRoot -HelperRelative 'skills/memory/memory-context.ps1'
            $roots.Add($misplaced)
            { Assert-MemoryDispatchOutcome -Outcome (Invoke-MemoryWrapperProcess -PluginRoot $misplaced -Name 'memory_list') } | Should -Throw
            $wrongDispatch = Initialize-MemoryFixtureRoot -DispatchMethod 'workflow.memory.remember'
            $roots.Add($wrongDispatch)
            { Assert-MemoryDispatchOutcome -Outcome (Invoke-MemoryWrapperProcess -PluginRoot $wrongDispatch -Name 'memory_list') } | Should -Throw
        } finally {
            foreach ($root in $roots) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'TR-MCP-MEMORY-008 AC-001 memory wrapper helper (binding)' {
    It 'MemoryWrapper_ThisPlugin_DispatchesThroughItsHelper' {
        Assert-MemoryDispatchOutcome -Outcome (Invoke-MemoryWrapperProcess -PluginRoot $script:RepoRoot -Name 'memory_list')
    }
}
