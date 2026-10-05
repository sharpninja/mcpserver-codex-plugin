$ErrorActionPreference = 'Stop'

if (Get-Command qbrain-ai-repl -ErrorAction SilentlyContinue) { exit 0 }
if (Get-Command mcpserver-repl -ErrorAction SilentlyContinue) { exit 0 }

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "gh CLI not found. Install GitHub CLI to auto-install qbrain-ai-repl or mcpserver-repl."
    exit 1
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Error "dotnet CLI not found. Install .NET 9+ SDK."
    exit 1
}

$candidates = @(
    @{ Pattern = 'QBrainAI.Repl.*.nupkg'; PackageId = 'QBrainAI.Repl'; Command = 'qbrain-ai-repl' },
    @{ Pattern = 'SharpNinja.McpServer.Repl.*.nupkg'; PackageId = 'SharpNinja.McpServer.Repl'; Command = 'mcpserver-repl' }
)

foreach ($candidate in $candidates) {
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("qbrain-ai-repl-" + $PID + "-" + $candidate.Command)
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    try {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & gh release download --repo sharpninja/McpServer --pattern $candidate.Pattern --dir $tmpDir
        $downloadExit = $LASTEXITCODE
        $ErrorActionPreference = $previous
        if ($downloadExit -ne 0) { continue }

        $nupkg = Get-ChildItem -Path $tmpDir -Filter $candidate.Pattern | Select-Object -First 1
        if (-not $nupkg) { continue }

        & dotnet tool install --global --add-source $tmpDir $candidate.PackageId
        if (Get-Command $candidate.Command -ErrorAction SilentlyContinue) {
            Write-Host ($candidate.Command + " installed successfully.")
            exit 0
        }
    }
    finally {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Error "qbrain-ai-repl or mcpserver-repl not on PATH after install."
exit 1
