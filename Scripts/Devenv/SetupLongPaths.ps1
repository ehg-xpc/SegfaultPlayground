# SetupLongPaths.ps1
# Enables long path support (>260 chars) for both Windows and Git.
# Required for repos with deeply nested files (e.g. SCCM packages with GUIDs).
#
# - Windows registry: removes the MAX_PATH limitation OS-wide (requires admin)
# - Git core.longpaths: allows git to handle long paths in checkouts/worktrees

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Write-Host "Enabling Windows long path support..." -ForegroundColor Cyan
$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
$current = Get-ItemProperty -Path $regPath -Name LongPathsEnabled -ErrorAction SilentlyContinue

if ($current.LongPathsEnabled -eq 1) {
    Write-Host "  Already enabled in registry." -ForegroundColor Green
} else {
    Set-ItemProperty -Path $regPath -Name LongPathsEnabled -Value 1 -Type DWord
    Write-Host "  Registry key set. A reboot may be required for full effect." -ForegroundColor Yellow
}

Write-Host "Enabling git core.longpaths globally..." -ForegroundColor Cyan
$gitValue = git config --global --get core.longpaths 2>$null

if ($gitValue -eq 'true') {
    Write-Host "  Already enabled in git." -ForegroundColor Green
} else {
    git config --global core.longpaths true
    Write-Host "  Done." -ForegroundColor Green
}

Write-Host "`nLong path support is configured." -ForegroundColor Cyan
