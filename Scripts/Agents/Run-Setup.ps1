#!/usr/bin/env pwsh
<#
.SYNOPSIS
    setup-agents.cmd entry point. Wires personal preferences for one or all
    coding CLIs from %dev_repo%\Config\<cli>\preferences.md.
    CLIs whose preferences.md file does not exist are silently skipped.

    It does this by creating symlinks on the files each CLI expect, and point them
    to a single preference file. 

    Note: A "symlink" (symbolic link) is a filesystem shortcut that points
    to another file or directory. Accessing the symlink acts like accessing
    the target; if the target is removed or moved the symlink becomes
    dangling (it points to a non-existent target).

.PARAMETER Cli
    Which CLI's preferences to wire up: claude, copilot, or opencode.
    Optional -- when omitted, all three are wired up in sequence.

.PARAMETER Force
    Forwarded to the per-CLI script. Skips backup of any existing
    non-symlink content at the link path.
#>

[CmdletBinding()]
param(
    [ValidateSet('claude', 'copilot', 'opencode')]
    [string]$Cli,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$devRepo = $env:dev_repo
if (-not $devRepo) {
    Write-Error '%dev_repo% is not set; cannot locate Config\<cli>\preferences.md.'
    exit 1
}
if (-not (Test-Path -LiteralPath $devRepo -PathType Container)) {
    Write-Error "dev_repo path does not exist: $devRepo"
    exit 1
}
$devRepo = (Resolve-Path -LiteralPath $devRepo).Path

$clisToSetup = if ($Cli) { @($Cli) } else { @('claude', 'copilot', 'opencode') }

foreach ($cliName in $clisToSetup) {
    $prefsPath = Join-Path $devRepo 'Config' $cliName 'preferences.md'
    if (-not (Test-Path -LiteralPath $prefsPath -PathType Leaf)) {
        Write-Host "Preferences file not found, skipping ${cliName}: $prefsPath" -ForegroundColor DarkGray
        continue
    }

    $script = switch ($cliName) {
        'claude'   { Join-Path $PSScriptRoot 'Setup-ClaudeCli.ps1' }
        'copilot'  { Join-Path $PSScriptRoot 'Setup-CopilotCli.ps1' }
        'opencode' { Join-Path $PSScriptRoot 'Setup-OpenCodeCli.ps1' }
    }

    $params = @{ PreferencesFile = $prefsPath }
    if ($Force) { $params['Force'] = $true }

    & $script @params
    if ($LASTEXITCODE -ne 0) {
        Write-Error "$([System.IO.Path]::GetFileName($script)) failed (exit $LASTEXITCODE)."
        exit $LASTEXITCODE
    }
}

exit 0
