<#
.SYNOPSIS
    Configures Stanley settings for this device.

.DESCRIPTION
    Sets the STANLEY_SETTINGS_FILE environment variable to point to the shared
    Stanley settings file in SharedConfig.
#>

$ErrorActionPreference = "Stop"

# Script is in: <repo>\Scripts\Devenv\SetupStanley.ps1
# SharedConfig is at: <repo>\SharedConfig
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$settingsFile = Join-Path $repoRoot "SharedConfig\stanley\server.settings.json"

if (-not (Test-Path $settingsFile)) {
    Write-Warning "Stanley settings file not found at: $settingsFile"
}

$current = [Environment]::GetEnvironmentVariable("STANLEY_SETTINGS_FILE", "User")
if ($current -ne $settingsFile) {
    [Environment]::SetEnvironmentVariable("STANLEY_SETTINGS_FILE", $settingsFile, "User")
    $env:STANLEY_SETTINGS_FILE = $settingsFile
    Write-Host "STANLEY_SETTINGS_FILE set to: $settingsFile"
}
