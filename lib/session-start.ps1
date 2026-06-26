#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pluginRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir '..')).ProviderPath
$env:MCP_PLUGIN_ROOT = $pluginRoot
$env:MCP_PLUGIN_HOST = 'codex'

& (Join-Path $pluginRoot 'lib\plugin-hook.ps1') -HookName 'session-start' -HostName 'codex' -CacheMode 'flat' @RemainingArguments
if (Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue) {
    exit $global:LASTEXITCODE
}

exit 0
