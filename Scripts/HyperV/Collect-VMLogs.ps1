#Requires -Version 5.1
<#
.SYNOPSIS
    Collects Windows event logs and arbitrary file paths from the local machine
    into a single zip archive.
.DESCRIPTION
    Designed to run INSIDE a Hyper-V VM via PowerShell Direct. Has no external
    module dependencies so it works on a clean Windows install.
    Writes the archive path to stdout for the orchestrator to read.
.PARAMETER OutputDirectory
    Directory where the zip archive is created.
.PARAMETER LastHours
    Only include event log entries from the last N hours. Default: 2.
.PARAMETER EventLogs
    Event log channel names to export as .evtx files.
    Default: Application, System, Microsoft-Windows-Installer/Operational.
.PARAMETER ExtraPaths
    Additional file or directory paths to include. Missing paths are skipped
    with a warning rather than failing the entire collection.
.OUTPUTS
    Full path of the created zip archive (written to stdout).
.EXAMPLE
    .\Collect-VMLogs.ps1 -OutputDirectory C:\Logs -LastHours 4 `
        -ExtraPaths 'C:\ProgramData\MyProduct\Logs','C:\Windows\Logs\CBS'
#>
param(
    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [int]$LastHours = 2,

    [string[]]$EventLogs = @(
        'Application',
        'System',
        'Microsoft-Windows-Installer/Operational'
    ),

    [string[]]$ExtraPaths = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-Status { param([string]$msg) Write-Host "[Collect-VMLogs] $msg" }

$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$stagingDir = Join-Path $env:TEMP "hvlogs_$timestamp"
$null = New-Item -ItemType Directory -Path $stagingDir -Force

# ── Event logs ──────────────────────────────────────────────────────────────
$logsDir = Join-Path $stagingDir 'EventLogs'
$null = New-Item -ItemType Directory -Path $logsDir -Force

# wevtutil XPath filter: entries within the last N hours
$cutoffMs = $LastHours * 3600 * 1000

foreach ($channel in $EventLogs) {
    $safeName = $channel -replace '[/\\:*?"<>|]', '_'
    $outFile  = Join-Path $logsDir "$safeName.evtx"
    Write-Status "Exporting: $channel"
    try {
        # /q: XPath filter, /ow: overwrite existing output file
        $xpQuery = "*[System[TimeCreated[timediff(@SystemTime) <= $cutoffMs]]]"
        & wevtutil.exe epl $channel $outFile "/q:$xpQuery" /ow:true 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Status "WARNING: wevtutil exited $LASTEXITCODE for '$channel'"
        }
    } catch {
        Write-Status "WARNING: Failed to export '$channel': $_"
    }
}

# ── Extra paths ──────────────────────────────────────────────────────────────
$filesDir = Join-Path $stagingDir 'Files'
$null = New-Item -ItemType Directory -Path $filesDir -Force

foreach ($src in $ExtraPaths) {
    # Expand wildcards in the leaf name (e.g. C:\Temp\MSI*.log)
    $resolved = @()
    try { $resolved = Resolve-Path -Path $src -ErrorAction SilentlyContinue } catch {}

    if (-not $resolved) {
        Write-Status "WARNING: Path not found, skipping: $src"
        continue
    }

    foreach ($r in $resolved) {
        $item    = Get-Item $r.Path -ErrorAction SilentlyContinue
        if (-not $item) { continue }

        $dest = Join-Path $filesDir $item.Name
        Write-Status "Copying: $($item.FullName)"
        try {
            Copy-Item -Path $item.FullName -Destination $dest -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Status "WARNING: Copy failed for '$($item.FullName)': $_"
        }
    }
}

# ── Package ──────────────────────────────────────────────────────────────────
if (-not (Test-Path $OutputDirectory)) {
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
}

$zipPath = Join-Path $OutputDirectory "VMlogs_$timestamp.zip"
Write-Status "Compressing to: $zipPath"
Compress-Archive -Path "$stagingDir\*" -DestinationPath $zipPath -Force

# ── Cleanup staging ──────────────────────────────────────────────────────────
Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Status "Done."

# Output the zip path for the orchestrator to capture
$zipPath
