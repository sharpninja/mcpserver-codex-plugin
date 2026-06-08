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

    [string]$WorkspacePath = (Get-Location).ProviderPath,

    [string]$PluginRoot = $PSScriptRoot,

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

function Resolve-BashExecutable {
    param([string]$Candidate)

    if ($Candidate) {
        return (Resolve-FullPath $Candidate)
    }

    $gitBash = Join-Path ${env:ProgramFiles} 'Git\bin\bash.exe'
    if (Test-Path -LiteralPath $gitBash) {
        return $gitBash
    }

    $command = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw 'Unable to find bash.exe. Install Git for Windows or pass -BashPath.'
}

function ConvertTo-BashPath {
    param([Parameter(Mandatory)][string]$Path)

    $full = Resolve-FullPath $Path
    if ($full -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $tail = $Matches[2] -replace '\\', '/'
        return "/$drive/$tail"
    }

    return ($full -replace '\\', '/')
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

function Invoke-BashPluginScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$StandardInput = ''
    )

    $bash = Resolve-BashExecutable $BashPath
    $pluginRootFull = Resolve-FullPath $PluginRoot
    $workspaceFull = Resolve-FullPath $WorkspacePath
    $cacheRootFull = if ($CacheRoot) { Resolve-FullPath $CacheRoot } elseif ($env:PLUGIN_ROOT_OVERRIDE) { Resolve-FullPath $env:PLUGIN_ROOT_OVERRIDE } else { $pluginRootFull }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $bash
    $startInfo.WorkingDirectory = $workspaceFull
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add((ConvertTo-BashPath $ScriptPath))
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.Environment['CODEX_PLUGIN_ROOT'] = $pluginRootFull
    $startInfo.Environment['PLUGIN_ROOT_OVERRIDE'] = $cacheRootFull
    $startInfo.Environment['MCP_WORKSPACE_PATH'] = $workspaceFull
    $startInfo.Environment['MCPSERVER_WORKSPACE_PATH'] = $workspaceFull

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

    if ($process.ExitCode -ne 0) {
        if ($stdout.Length -gt 0) {
            Write-Output ($stdout.TrimEnd("`r", "`n"))
        }

        throw "Plugin command failed with exit code $($process.ExitCode)."
    }

    if ($stdout.Length -gt 0) {
        Write-Output ($stdout.TrimEnd("`r", "`n"))
    }
}

$pluginRootFull = Resolve-FullPath $PluginRoot

switch ($Command) {
    'Status' {
        Invoke-BashPluginScript -ScriptPath (Join-Path $pluginRootFull 'lib\mcp.codex.status.sh')
    }
    'Invoke' {
        if (-not $Method) {
            throw '-Method is required when -Command Invoke is used.'
        }

        $paramsText = Read-OptionalText -Inline $Params -HasInline:$($PSBoundParameters.ContainsKey('Params')) -Path $ParamsPath

        Invoke-BashPluginScript -ScriptPath (Join-Path $pluginRootFull 'lib\repl-invoke.sh') -Arguments @($Method) -StandardInput ($paramsText ?? '')
    }
    'CompleteTurn' {
        $responseText = Read-OptionalText -Inline $Response -HasInline:$($PSBoundParameters.ContainsKey('Response')) -Path $ResponsePath
        if (-not $responseText) {
            $responseText = 'Turn completed.'
        }

        Invoke-BashPluginScript -ScriptPath (Join-Path $pluginRootFull 'lib\final-response.sh') -StandardInput $responseText
    }
}
