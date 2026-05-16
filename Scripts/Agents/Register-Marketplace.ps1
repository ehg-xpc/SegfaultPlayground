#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Register %dev_repo%\AI as a local plugin marketplace with the supported
    coding-agent CLIs (Claude Code, GitHub Copilot CLI), and install the
    plugins this device should always have available.

.DESCRIPTION
    The marketplace manifest at %dev_repo%\AI\.claude-plugin\marketplace.json
    is consumed by both Claude Code and Copilot CLI -- both look for that
    path. This script:

      1. Registers the marketplace path with each CLI.
      2. Installs the plugins listed in $autoInstallPlugins (user scope).

    The auto-install list lives in auto-install-plugins.txt next to this
    script -- one plugin name per line, # comments OK. Plugins absent from
    that file are left for manual install, typically with
    `claude plugin install <name>@<marketplace> --scope project` from inside
    the repo where they are useful, so they don't clutter unrelated repos.

    Both steps are idempotent: "already registered" / "already installed"
    output is treated as success.

    OpenCode does not consume this manifest format yet -- a separate path
    is tracked as a draft task and will be wired up later.

.PARAMETER Cli
    Optional. Restrict to a single CLI (claude or copilot). When omitted,
    both are processed.
#>

[CmdletBinding()]
param(
    [ValidateSet('claude', 'copilot')]
    [string]$Cli
)

$ErrorActionPreference = 'Stop'

$devRepo = $env:dev_repo
if (-not $devRepo) {
    Write-Error '%dev_repo% is not set; cannot locate AI marketplace.'
    exit 1
}

$marketplacePath = Join-Path $devRepo 'AI'
$manifestPath    = Join-Path $marketplacePath '.claude-plugin' 'marketplace.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Error "Marketplace manifest missing: $manifestPath"
    exit 1
}
$marketplacePath = (Resolve-Path -LiteralPath $marketplacePath).Path

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$marketplaceName = $manifest.name
if (-not $marketplaceName) {
    Write-Error "marketplace.json is missing the 'name' field."
    exit 1
}

# Plugins installed user-wide on every device. One name per line in
# auto-install-plugins.txt; comments and blank lines are ignored. Plugins
# absent from the file should be installed manually with --scope project.
$autoInstallFile = Join-Path $PSScriptRoot 'auto-install-plugins.txt'
$autoInstallPlugins = @()
if (Test-Path -LiteralPath $autoInstallFile -PathType Leaf) {
    $autoInstallPlugins = Get-Content -LiteralPath $autoInstallFile |
        Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' } |
        ForEach-Object { $_.Trim() }
} else {
    Write-Warning "Auto-install list missing: $autoInstallFile (registering marketplace only)"
}

function Register-Marketplace {
    param([string]$CliName, [string]$Path)

    $output = & $CliName plugin marketplace add $Path 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    Registered $Path" -ForegroundColor Green
        return
    }
    if ($output -match '(?i)already|exists|registered') {
        Write-Host "    Marketplace already registered" -ForegroundColor Green
        return
    }
    Write-Warning "Failed to register marketplace with ${CliName}: $($output.Trim())"
}

function Install-Plugin {
    param([string]$CliName, [string]$Spec)

    $output = & $CliName plugin install $Spec 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    Installed $Spec" -ForegroundColor Green
        return
    }
    if ($output -match '(?i)already installed|already exists') {
        Write-Host "    Already installed: $Spec" -ForegroundColor Green
        return
    }
    Write-Warning "Failed to install $Spec via ${CliName}: $($output.Trim())"
}

function Setup-OneCli {
    param([string]$CliName)

    if (-not (Get-Command $CliName -ErrorAction SilentlyContinue)) {
        Write-Host "  $CliName not on PATH; skipping." -ForegroundColor Yellow
        return
    }

    Write-Host "  $CliName" -ForegroundColor Cyan
    Register-Marketplace -CliName $CliName -Path $marketplacePath
    foreach ($name in $autoInstallPlugins) {
        Install-Plugin -CliName $CliName -Spec "$name@$marketplaceName"
    }
}

$clisToSetup = if ($Cli) { @($Cli) } else { @('claude', 'copilot') }

Write-Host ''
Write-Host 'Local plugin marketplace' -ForegroundColor Cyan
Write-Host '========================' -ForegroundColor Cyan
Write-Host "  Marketplace:  $marketplaceName ($marketplacePath)"
Write-Host "  Auto-install: $(if ($autoInstallPlugins) { $autoInstallPlugins -join ', ' } else { '(none)' })"

foreach ($cliName in $clisToSetup) {
    Setup-OneCli -CliName $cliName
}

exit 0
