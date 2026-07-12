#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Params,

    [string]$ParamsPath,

    [Parameter(ValueFromPipeline = $true)]
    [object]$InputObject,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pluginRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir '..')).ProviderPath
$env:MCP_PLUGIN_ROOT = $pluginRoot
$env:MCP_PLUGIN_HOST = 'codex'

$hookParams = $Params
if (-not $hookParams -and $null -ne $InputObject) {
    if ($InputObject -is [string]) {
        $hookParams = [string]$InputObject
    } else {
        $hookParams = $InputObject | ConvertTo-Json -Depth 20 -Compress
    }
}

$hookArguments = @{
    HookName = 'code-verify'
    HostName = 'codex'
    CacheMode = 'scoped'
}
if ($hookParams) { $hookArguments.Params = $hookParams }
if ($ParamsPath) { $hookArguments.ParamsPath = $ParamsPath }

& (Join-Path $pluginRoot 'lib\plugin-hook.ps1') @hookArguments @RemainingArguments
if (Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue) {
    exit $global:LASTEXITCODE
}

exit 0