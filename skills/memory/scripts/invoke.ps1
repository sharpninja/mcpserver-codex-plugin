#Requires -Version 7.0
<#
.SYNOPSIS
    Dispatches memory_* aliases to the plugin's workflow.memory.* REPL methods.
.DESCRIPTION
    Resolves names from memory-descriptor.json workflowMethods and invokes
    lib/repl-invoke.ps1 (or the MCP_PLUGIN_REPL_LOG test seam). Does not claim
    native MCP tools that this plugin does not register.
#>
[CmdletBinding()]
param(
    [string]$Name,
    [string]$Method,
    [string]$ParamsYaml = '',
    [string]$PluginRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedPluginRoot = if ($PluginRoot) {
    $PluginRoot
} elseif ($env:MCP_PLUGIN_ROOT) {
    $env:MCP_PLUGIN_ROOT
} else {
    (Resolve-Path -LiteralPath (Join-Path $scriptDir '../../..')).ProviderPath
}

$memoryContext = $null
foreach ($rel in @('lib/memory-context.ps1', 'hooks/scripts/memory-context.ps1')) {
    $candidate = Join-Path $resolvedPluginRoot $rel
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $memoryContext = $candidate
        break
    }
}
if (-not $memoryContext) {
    throw "memory-context.ps1 was not found under $resolvedPluginRoot"
}
. $memoryContext

$descriptor = Get-McpMemoryDescriptor -PluginRoot $resolvedPluginRoot
$requested = if ($Method) { $Method } elseif ($Name) { $Name } else {
    throw 'Specify -Name memory_* or -Method workflow.memory.*'
}
$resolvedMethod = Resolve-McpMemoryWorkflowMethod -Name $requested -Descriptor $descriptor
Invoke-McpMemoryWorkflow -Method $resolvedMethod -ParamsYaml $ParamsYaml -PluginRoot $resolvedPluginRoot
