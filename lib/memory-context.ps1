#Requires -Version 7.0
<#
.SYNOPSIS
    Required-memory injection helpers for the always-on Codex UserPromptSubmit path.
.DESCRIPTION
    Loads memory-descriptor.json, fetches required memories through the plugin
    REPL/workflow surface (workflow.memory.list, scope Effective), and renders
    them with the host descriptor prefix and explicit None fallback.

    Fail-soft: log to stderr and continue when McpServer/memory is unavailable.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:McpMemoryContextDir = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($PSCommandPath) {
    Split-Path -Parent $PSCommandPath
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Get-McpMemoryPluginRoot {
    param([string]$PluginRoot)

    $candidates = @(
        $PluginRoot
        $env:MCP_PLUGIN_ROOT
        $env:CODEX_PLUGIN_ROOT
        $env:CLAUDE_PLUGIN_ROOT
        $env:COWORK_PLUGIN_ROOT
        $env:COPILOT_PLUGIN_ROOT
        $env:PLUGIN_ROOT
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return (Resolve-Path -LiteralPath $candidate).ProviderPath
        }
    }

    $cursor = $script:McpMemoryContextDir
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        $descriptorAtRoot = Join-Path $cursor 'memory-descriptor.json'
        if (Test-Path -LiteralPath $descriptorAtRoot -PathType Leaf) {
            return (Resolve-Path -LiteralPath $cursor).ProviderPath
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) {
            break
        }
        $cursor = $parent
    }

    return (Get-Location).ProviderPath
}

function Get-McpMemoryDescriptorPath {
    param(
        [string]$PluginRoot,
        [string]$DescriptorPath
    )

    if (-not [string]::IsNullOrWhiteSpace($DescriptorPath)) {
        return $DescriptorPath
    }
    if (-not [string]::IsNullOrWhiteSpace($env:MCP_MEMORY_DESCRIPTOR_PATH)) {
        return $env:MCP_MEMORY_DESCRIPTOR_PATH
    }

    $root = Get-McpMemoryPluginRoot -PluginRoot $PluginRoot
    return (Join-Path $root 'memory-descriptor.json')
}

function Get-McpMemoryDescriptor {
    param(
        [string]$PluginRoot,
        [string]$DescriptorPath
    )

    $path = Get-McpMemoryDescriptorPath -PluginRoot $PluginRoot -DescriptorPath $DescriptorPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [ordered]@{
            host = 'codex'
            path = $path
            loaded = $false
            injection = [ordered]@{
                requiredMemoriesPrefix = 'REQUIRED MEMORIES -'
                emptyFallback = 'REQUIRED MEMORIES - None.'
            }
            fallback = [ordered]@{
                localFailsafe = $true
                replayAfterAck = $true
            }
            tools = @()
            workflowMethods = [ordered]@{}
        }
    }

    $json = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json -Depth 20
    $prefix = 'REQUIRED MEMORIES -'
    $empty = 'REQUIRED MEMORIES - None.'
    $injection = Get-McpMemoryNoteProperty -Object $json -Name 'injection'
    $requiredPrefix = Get-McpMemoryNoteProperty -Object $injection -Name 'requiredMemoriesPrefix'
    $emptyFallback = Get-McpMemoryNoteProperty -Object $injection -Name 'emptyFallback'
    if ($requiredPrefix) { $prefix = [string]$requiredPrefix }
    if ($emptyFallback) { $empty = [string]$emptyFallback }

    $methods = [ordered]@{}
    $workflowMethods = Get-McpMemoryNoteProperty -Object $json -Name 'workflowMethods'
    if ($workflowMethods) {
        foreach ($prop in $workflowMethods.PSObject.Properties) {
            $methods[[string]$prop.Name] = [string]$prop.Value
        }
    }
    $tools = @(Get-McpMemoryNoteProperty -Object $json -Name 'tools')
    if ($methods.Count -eq 0) {
        foreach ($tool in $tools) {
            $name = [string]$tool
            if ($name -match '^memory_(?<verb>.+)$') {
                $methods[$name] = 'workflow.memory.{0}' -f $Matches['verb']
            }
        }
    }

    $fallback = Get-McpMemoryNoteProperty -Object $json -Name 'fallback'
    return [ordered]@{
        host = [string](Get-McpMemoryNoteProperty -Object $json -Name 'host')
        path = $path
        loaded = $true
        injection = [ordered]@{
            requiredMemoriesPrefix = $prefix
            emptyFallback = $empty
        }
        fallback = [ordered]@{
            localFailsafe = [bool](Get-McpMemoryNoteProperty -Object $fallback -Name 'localFailsafe')
            replayAfterAck = [bool](Get-McpMemoryNoteProperty -Object $fallback -Name 'replayAfterAck')
        }
        tools = $tools
        workflowMethods = $methods
    }
}

function Get-McpMemoryNoteProperty {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Resolve-McpMemoryWorkflowMethod {
    param(
        [Parameter(Mandatory)][string]$Name,
        $Descriptor
    )

    $trimmed = $Name.Trim()
    if ($trimmed -match '^workflow\.memory\.[A-Za-z][A-Za-z0-9]*$') {
        return $trimmed
    }

    if ($Descriptor -and $Descriptor.workflowMethods -and $Descriptor.workflowMethods.Contains($trimmed)) {
        return [string]$Descriptor.workflowMethods[$trimmed]
    }

    if ($trimmed -match '^memory_(?<verb>.+)$') {
        return 'workflow.memory.{0}' -f $Matches['verb']
    }

    throw "Unsupported memory tool alias: $Name"
}

function ConvertTo-McpMemoryItems {
    param([string]$Response)

    $items = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($Response)) {
        return @()
    }

    $payload = $null
    $trimmed = $Response.Trim()
    try {
        if ($trimmed.StartsWith('{') -or $trimmed.StartsWith('[')) {
            $payload = $trimmed | ConvertFrom-Json -Depth 20
        }
    } catch {
        $payload = $null
    }

    if ($null -eq $payload) {
        $yamlHelper = Join-Path (Get-McpMemoryPluginRoot) 'lib/yaml-object-mutation.ps1'
        if (Test-Path -LiteralPath $yamlHelper -PathType Leaf) {
            try {
                . $yamlHelper
                Import-McpYamlSerializer
                $payload = ConvertFrom-Yaml -Yaml $trimmed -Ordered -ErrorAction Stop
            } catch {
                $payload = $null
            }
        }
    }

    $rawItems = @()
    if ($payload -is [System.Collections.IDictionary] -or ($null -ne $payload -and $payload.PSObject)) {
        $result = $null
        if ($payload -is [System.Collections.IDictionary]) {
            if ($payload.Contains('payload')) { $result = $payload['payload'] }
            elseif ($payload.Contains('result')) { $result = $payload['result'] }
            else { $result = $payload }
            if ($result -is [System.Collections.IDictionary]) {
                if ($result.Contains('result')) { $result = $result['result'] }
                if ($result -is [System.Collections.IDictionary]) {
                    if ($result.Contains('items')) { $rawItems = @($result['items']) }
                    elseif ($result.Contains('Items')) { $rawItems = @($result['Items']) }
                } elseif ($result -is [System.Collections.IEnumerable] -and $result -isnot [string]) {
                    $rawItems = @($result)
                }
            }
        } else {
            $node = $payload
            if ($node.payload) { $node = $node.payload }
            if ($node.result) { $node = $node.result }
            if ($node.items) { $rawItems = @($node.items) }
            elseif ($node.Items) { $rawItems = @($node.Items) }
            elseif ($node -is [System.Collections.IEnumerable] -and $node -isnot [string]) {
                $rawItems = @($node)
            }
        }
    }

    foreach ($item in $rawItems) {
        if ($null -eq $item) { continue }
        $id = $null
        $text = $null
        if ($item -is [System.Collections.IDictionary]) {
            $id = if ($item.Contains('id')) { $item['id'] } elseif ($item.Contains('Id')) { $item['Id'] } else { $null }
            $text = if ($item.Contains('text')) { $item['text'] } elseif ($item.Contains('Text')) { $item['Text'] } else { $null }
        } else {
            $id = $item.id
            if (-not $id) { $id = $item.Id }
            $text = $item.text
            if ($null -eq $text) { $text = $item.Text }
        }
        if ([string]::IsNullOrWhiteSpace([string]$id) -or $null -eq $text) { continue }
        $items.Add([ordered]@{ id = [string]$id; text = [string]$text })
    }

    if ($items.Count -gt 0) {
        return @($items)
    }

    $currentId = ''
    $currentText = ''
    foreach ($line in ($trimmed -split "`r?`n")) {
        if ($line -match '^\s*-?\s*[Ii]d:\s*(.+)$') {
            if ($currentId -and $null -ne $currentText) {
                $items.Add([ordered]@{ id = $currentId; text = $currentText })
            }
            $currentId = $Matches[1].Trim().Trim('"').Trim("'")
            $currentText = ''
            continue
        }
        if ($line -match '^\s*[Tt]ext:\s*(.*)$') {
            $currentText = $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    if ($currentId -and $null -ne $currentText) {
        $items.Add([ordered]@{ id = $currentId; text = $currentText })
    }

    return @($items)
}

function Invoke-McpMemoryWorkflow {
    param(
        [Parameter(Mandatory)][string]$Method,
        [string]$ParamsYaml = '',
        [string]$PluginRoot
    )

    if ($env:MCP_MEMORY_FETCH_ERROR -eq '1') {
        throw 'MCP_MEMORY_FETCH_ERROR is set'
    }

    if ($env:MCP_PLUGIN_REPL_LOG) {
        $entry = @(
            "method: $Method"
            'params: |'
            (($ParamsYaml -replace "`r`n", "`n" -replace "`r", "`n") -split "`n" | ForEach-Object { "  $_" })
            '---'
        ) -join "`n"
        Add-Content -LiteralPath $env:MCP_PLUGIN_REPL_LOG -Value $entry
        if (-not [string]::IsNullOrWhiteSpace($env:MCP_MEMORY_REPL_RESPONSE)) {
            return [string]$env:MCP_MEMORY_REPL_RESPONSE
        }
        if (-not [string]::IsNullOrWhiteSpace($env:MCP_PLUGIN_REPL_RESPONSE)) {
            return [string]$env:MCP_PLUGIN_REPL_RESPONSE
        }
        return ''
    }

    if (-not [string]::IsNullOrWhiteSpace($env:MCP_MEMORY_REPL_RESPONSE)) {
        return [string]$env:MCP_MEMORY_REPL_RESPONSE
    }

    $root = Get-McpMemoryPluginRoot -PluginRoot $PluginRoot
    $repl = Join-Path $root 'lib/repl-invoke.ps1'
    if (-not (Test-Path -LiteralPath $repl -PathType Leaf)) {
        throw "repl-invoke.ps1 was not found under $root"
    }

    $timeoutSeconds = 6
    if ($env:MCP_MEMORY_REPL_TIMEOUT_SECONDS) {
        $parsed = 0
        if ([int]::TryParse([string]$env:MCP_MEMORY_REPL_TIMEOUT_SECONDS, [ref]$parsed) -and $parsed -gt 0) {
            $timeoutSeconds = $parsed
        }
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Get-Command pwsh -ErrorAction Stop).Source
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $repl, '-Method', $Method, '-ParamsYaml', $ParamsYaml)) {
        $psi.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::Start($psi)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
        try { $process.Kill($true) } catch { }
        try { [void]$process.WaitForExit(2000) } catch { }
        throw "workflow method $Method timed out after ${timeoutSeconds}s"
    }

    $stderrText = ''
    try { $stderrText = [string]$stderrTask.Result } catch { }
    if ($stderrText) {
        [Console]::Error.WriteLine($stderrText.Trim())
    }
    if ($process.ExitCode -ne 0) {
        throw "workflow method $Method failed with exit code $($process.ExitCode)"
    }
    $stdoutText = ''
    try { $stdoutText = [string]$stdoutTask.Result } catch { }
    return $stdoutText.Trim()
}

function Get-McpRequiredMemoryItems {
    param(
        [string]$PluginRoot,
        [scriptblock]$FetchOverride
    )

    if ($FetchOverride) {
        $response = & $FetchOverride
        return @(ConvertTo-McpMemoryItems -Response ([string]$response))
    }

    $response = Invoke-McpMemoryWorkflow `
        -Method 'workflow.memory.list' `
        -ParamsYaml 'scope: Effective' `
        -PluginRoot $PluginRoot
    return @(ConvertTo-McpMemoryItems -Response $response)
}

function Format-McpRequiredMemoryContext {
    param(
        $Descriptor,
        $Items
    )

    $prefix = 'REQUIRED MEMORIES -'
    $empty = 'REQUIRED MEMORIES - None.'
    if ($Descriptor -and $Descriptor.injection) {
        if ($Descriptor.injection.requiredMemoriesPrefix) {
            $prefix = [string]$Descriptor.injection.requiredMemoriesPrefix
        }
        if ($Descriptor.injection.emptyFallback) {
            $empty = [string]$Descriptor.injection.emptyFallback
        }
    }

    $rows = @($Items | Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.id) })
    if ($rows.Count -eq 0) {
        return $empty
    }

    $lines = foreach ($row in $rows) {
        $text = [string]$row.text
        $normalized = $text.Replace("`r`n", "`n").Replace("`r", "`n")
        $parts = $normalized -split "`n", 2
        $first = '{0} {1}: {2}' -f $prefix.TrimEnd(), [string]$row.id, $parts[0]
        if ($parts.Count -gt 1 -and -not [string]::IsNullOrEmpty($parts[1])) {
            $first + "`n" + $parts[1]
        } else {
            $first
        }
    }
    return ($lines -join "`n")
}

function Get-McpRequiredMemoryContext {
    param(
        [string]$PluginRoot,
        [string]$DescriptorPath,
        [scriptblock]$FetchOverride
    )

    $descriptor = $null
    try {
        $descriptor = Get-McpMemoryDescriptor -PluginRoot $PluginRoot -DescriptorPath $DescriptorPath
    } catch {
        [Console]::Error.WriteLine("required-memory descriptor load failed: $($_.Exception.Message)")
        $descriptor = $null
    }

    try {
        $items = Get-McpRequiredMemoryItems -PluginRoot $PluginRoot -FetchOverride $FetchOverride
        return (Format-McpRequiredMemoryContext -Descriptor $descriptor -Items $items)
    } catch {
        [Console]::Error.WriteLine("required-memory injection skipped: $($_.Exception.Message)")
        if ($descriptor -and $descriptor.injection -and $descriptor.injection.emptyFallback) {
            return [string]$descriptor.injection.emptyFallback
        }
        return 'REQUIRED MEMORIES - None.'
    }
}

function Add-McpRequiredMemoryToHookOutput {
    param(
        [string]$HookOutput,
        [string]$PluginRoot,
        [string]$DescriptorPath,
        [scriptblock]$FetchOverride
    )

    $context = Get-McpRequiredMemoryContext -PluginRoot $PluginRoot -DescriptorPath $DescriptorPath -FetchOverride $FetchOverride
    if ([string]::IsNullOrWhiteSpace($HookOutput)) {
        return (@{
            hookSpecificOutput = [ordered]@{
                hookEventName = 'UserPromptSubmit'
                status = 'memory-injected'
                additionalContext = $context
            }
        } | ConvertTo-Json -Depth 20 -Compress)
    }

    $jsonLine = $null
    foreach ($line in ($HookOutput -split "`r?`n")) {
        $candidate = $line.Trim()
        if ($candidate.StartsWith('{') -and $candidate.EndsWith('}')) {
            $jsonLine = $candidate
        }
    }

    if (-not $jsonLine) {
        return $HookOutput
    }

    try {
        $obj = $jsonLine | ConvertFrom-Json -Depth 20 -ErrorAction Stop
    } catch {
        return $HookOutput
    }

    if (-not $obj.hookSpecificOutput) {
        return $HookOutput
    }

    $hso = [ordered]@{}
    foreach ($prop in $obj.hookSpecificOutput.PSObject.Properties) {
        $hso[$prop.Name] = $prop.Value
    }

    $existing = if ($hso.Contains('additionalContext')) { [string]$hso['additionalContext'] } else { '' }
    if ([string]::IsNullOrWhiteSpace($existing)) {
        $hso['additionalContext'] = $context
    } elseif ($existing.Contains($context)) {
        $hso['additionalContext'] = $existing
    } else {
        $hso['additionalContext'] = $context + "`n`n" + $existing
    }

    $result = [ordered]@{}
    foreach ($prop in $obj.PSObject.Properties) {
        if ($prop.Name -eq 'hookSpecificOutput') {
            $result[$prop.Name] = $hso
        } else {
            $result[$prop.Name] = $prop.Value
        }
    }
    if (-not $result.Contains('hookSpecificOutput')) {
        $result['hookSpecificOutput'] = $hso
    }

    return ($result | ConvertTo-Json -Depth 20 -Compress)
}
