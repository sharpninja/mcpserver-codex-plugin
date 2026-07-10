#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Status', 'Invoke', 'CompleteTurn')]
    [string]$Command = 'Status',

    [string]$Method,

    [string]$Params,

    [string]$ParamsPath,

    [string]$Response,

    [string]$ResponsePath,

    [string]$WorkspacePath = $(if ($env:MCP_WORKSPACE_PATH) { $env:MCP_WORKSPACE_PATH } elseif ($env:MCPSERVER_WORKSPACE_PATH) { $env:MCPSERVER_WORKSPACE_PATH } elseif ($env:CODEX_WORKSPACE_PATH) { $env:CODEX_WORKSPACE_PATH } elseif ($env:CODEX_PROJECT_DIR) { $env:CODEX_PROJECT_DIR } else { (Get-Location).ProviderPath }),

    [string]$PluginRoot = $(if ($env:MCP_PLUGIN_ROOT) { $env:MCP_PLUGIN_ROOT } elseif ($env:CODEX_PLUGIN_ROOT) { $env:CODEX_PLUGIN_ROOT } else { $PSScriptRoot }),

    [string]$CacheRoot,

    [string]$BashPath,

    [int]$TimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    return $resolved.ProviderPath
}

function Read-OptionalText {
    param(
        [string]$Inline,
        [bool]$HasInline,
        [string]$Path
    )

    if ($Path) {
        return [System.IO.File]::ReadAllText((Resolve-FullPath $Path))
    }

    if ($HasInline) {
        return $Inline
    }

    if ([Console]::IsInputRedirected) {
        return [Console]::In.ReadToEnd()
    }

    return ''
}

function Resolve-PowerShellExecutable {
    $command = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw 'Unable to find pwsh.exe. Install PowerShell 7 before using the MCP plugin.'
}

function Invoke-PowerShellPluginScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$StandardInput = ''
    )

    $pwsh = Resolve-PowerShellExecutable
    $pluginRootFull = Resolve-FullPath $PluginRoot
    $workspaceFull = Resolve-FullPath $WorkspacePath
    $cacheOverrideFull = if ($CacheRoot) {
        Resolve-FullPath $CacheRoot
    } elseif ($env:MCP_CACHE_DIR_OVERRIDE) {
        Resolve-FullPath $env:MCP_CACHE_DIR_OVERRIDE
    } else {
        $null
    }
    $legacyCacheRootFull = if (-not $cacheOverrideFull -and $env:PLUGIN_ROOT_OVERRIDE) {
        $legacyFull = Resolve-FullPath $env:PLUGIN_ROOT_OVERRIDE
        if (-not [string]::Equals($legacyFull.TrimEnd('\\'), $pluginRootFull.TrimEnd('\\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            $legacyFull
        }
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwsh
    $startInfo.WorkingDirectory = $workspaceFull
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('-NoLogo')
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-NonInteractive')
    $startInfo.ArgumentList.Add('-ExecutionPolicy')
    $startInfo.ArgumentList.Add('Bypass')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add($ScriptPath)
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.Environment['CODEX_PLUGIN_ROOT'] = $pluginRootFull
    $startInfo.Environment['MCP_PLUGIN_ROOT'] = $pluginRootFull
    [void]$startInfo.Environment.Remove('MCP_CACHE_DIR_OVERRIDE')
    [void]$startInfo.Environment.Remove('PLUGIN_ROOT_OVERRIDE')
    if ($cacheOverrideFull) {
        $startInfo.Environment['MCP_CACHE_DIR_OVERRIDE'] = $cacheOverrideFull
    } elseif ($legacyCacheRootFull) {
        $startInfo.Environment['PLUGIN_ROOT_OVERRIDE'] = $legacyCacheRootFull
    }
    $startInfo.Environment['MCP_WORKSPACE_PATH'] = $workspaceFull
    $startInfo.Environment['MCPSERVER_WORKSPACE_PATH'] = $workspaceFull
    $startInfo.Environment['MCP_WORKSPACE_START_DIR'] = $workspaceFull
    $startInfo.Environment['CODEX_WORKSPACE_PATH'] = $workspaceFull
    $startInfo.Environment['MCP_PLUGIN_HOST'] = 'codex'
    $startInfo.Environment['PLUGIN_AGENT_DEFAULT'] = 'Codex'
    $startInfo.Environment['PLUGIN_MODEL_DEFAULT'] = 'codex'
    $startInfo.Environment['PLUGIN_TAG'] = 'codex'
    $startInfo.Environment['MCP_AGENT_NAME'] = 'Codex'
    $startInfo.Environment['MCP_AGENT_ID'] = 'Codex'
    $startInfo.Environment['MCP_SESSION_AGENT'] = 'Codex'
    $startInfo.Environment['MCP_SESSION_MODEL'] = 'codex'
    $startInfo.Environment['CT2R_SOURCE_TYPE'] = 'Codex'
    $startInfo.Environment['CT2R_MODEL'] = 'codex'

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()

    if ($StandardInput.Length -gt 0) {
        $process.StandardInput.Write($StandardInput)
    }
    $process.StandardInput.Close()

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $boundedTimeout = [Math]::Max(1, $TimeoutSeconds)
    if (-not $process.WaitForExit($boundedTimeout * 1000)) {
        try {
            if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
                & "$env:WINDIR\System32\taskkill.exe" /PID $process.Id /T /F > $null 2> $null
            } else {
                $process.Kill($true)
            }
        } catch {
            try { $process.Kill() } catch { }
        }
        try { $process.StandardOutput.Close() } catch { }
        try { $process.StandardError.Close() } catch { }
        try { [void]$process.WaitForExit(5000) } catch { }
        try { [void]$stdoutTask.Wait(1000) } catch { }
        try { [void]$stderrTask.Wait(1000) } catch { }

        throw "Plugin command timed out after $boundedTimeout seconds: $ScriptPath"
    }

    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()

    if ($stderr.Length -gt 0) {
        [Console]::Error.Write($stderr)
    }

    if ($stdout.Length -gt 0) {
        Write-Output ($stdout.TrimEnd("`r", "`n"))
    }

    if ($process.ExitCode -ne 0) {
        $msg = "Plugin command failed with exit code $($process.ExitCode)."
        if ($stdout) { $msg += "`n" + $stdout }
        throw $msg
    }
}

$pluginRootFull = Resolve-FullPath $PluginRoot

switch ($Command) {
    'Status' {
        Invoke-PowerShellPluginScript -ScriptPath (Join-Path $pluginRootFull 'lib\mcp-status.ps1')
    }
    'Invoke' {
        if (-not $Method) {
            throw '-Method is required when -Command Invoke is used.'
        }

        $paramsText = Read-OptionalText -Inline $Params -HasInline:$($PSBoundParameters.ContainsKey('Params')) -Path $ParamsPath

        Invoke-PowerShellPluginScript -ScriptPath (Join-Path $pluginRootFull 'lib\repl-invoke.ps1') -Arguments @('-Method', $Method, '-ParamsYaml', ($paramsText ?? ''))
    }
    'CompleteTurn' {
        $responseText = Read-OptionalText -Inline $Response -HasInline:$($PSBoundParameters.ContainsKey('Response')) -Path $ResponsePath
        if (-not $responseText) {
            $responseText = 'Turn completed.'
        }

        Invoke-PowerShellPluginScript -ScriptPath (Join-Path $pluginRootFull 'lib\final-response.ps1') -StandardInput $responseText
    }
}
