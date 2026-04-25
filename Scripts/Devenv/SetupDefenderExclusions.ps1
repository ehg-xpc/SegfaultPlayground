#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Configures Windows Defender exclusions for development paths and processes.

.DESCRIPTION
    Adds path and process exclusions to Windows Defender for common development
    directories (repos, scoop, nuget, npm, uv) and executables (node, git, msbuild, etc.).

    Requires administrator privileges. Skips gracefully if Defender cmdlets are unavailable
    (e.g. on Server SKUs).

.EXAMPLE
    .\SetupDefenderExclusions.ps1
#>

$ErrorActionPreference = "Stop"

# Verify that the Defender cmdlets are available (may be absent on Server SKUs)
if (-not (Get-Command Add-MpPreference -ErrorAction SilentlyContinue)) {
    Write-Host "[!] Add-MpPreference not available, skipping Defender exclusions" -ForegroundColor Yellow
    exit 0
}

try {
    $current = Get-MpPreference
    $existingPaths = @($current.ExclusionPath    | Where-Object { $_ })
    $existingProcs = @($current.ExclusionProcess | Where-Object { $_ })

    # Resolve REPOS path
    $reposPath = [Environment]::GetEnvironmentVariable("REPOS", "User")
    if ([string]::IsNullOrEmpty($reposPath)) {
        # Derive: 4 levels up from Scripts/Devenv/
        $reposPath = Split-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    }

    $pathExclusions = @(
        $reposPath,
        (Join-Path $env:USERPROFILE "scoop"),
        (Join-Path $env:USERPROFILE ".nuget"),
        (Join-Path $env:LOCALAPPDATA "npm-cache"),
        (Join-Path $env:LOCALAPPDATA "uv"),
        (Join-Path $env:APPDATA "npm")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $processExclusions = @(
        "node.exe",
        "git.exe",
        "msbuild.exe",
        "cl.exe",
        "link.exe",
        "pwsh.exe",
        "powershell.exe",
        "python.exe",
        "uv.exe",
        "code.exe",
        "devenv.exe"
    )

    foreach ($path in $pathExclusions) {
        if ($existingPaths -contains $path) {
            Write-Host "[=] Defender path exclusion already set: $path" -ForegroundColor Gray
        } else {
            Add-MpPreference -ExclusionPath $path -ErrorAction Stop
            Write-Host "[+] Added Defender path exclusion: $path" -ForegroundColor Green
        }
    }

    foreach ($proc in $processExclusions) {
        if ($existingProcs -contains $proc) {
            Write-Host "[=] Defender process exclusion already set: $proc" -ForegroundColor Gray
        } else {
            Add-MpPreference -ExclusionProcess $proc -ErrorAction Stop
            Write-Host "[+] Added Defender process exclusion: $proc" -ForegroundColor Green
        }
    }

} catch {
    Write-Host "[!] Failed to configure Defender exclusions: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
