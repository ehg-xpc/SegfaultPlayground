#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Symlink ~/.claude/CLAUDE.md to a personal preferences file.

.DESCRIPTION
    Creates a single file symlink from ~/.claude/CLAUDE.md to the file at
    -PreferencesFile. Existing non-symlink content is moved aside to
    <linkPath>.backup.<timestamp> first (skipped under -Force). Re-launches
    elevated if the OS rejects the symlink for lack of privilege.

.PARAMETER PreferencesFile
    Path to the preferences file the symlink should point at.

.PARAMETER Force
    Skip backup of existing non-symlink content; overwrite directly.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PreferencesFile,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PreferencesFile -PathType Leaf)) {
    Write-Error "Preferences file does not exist: $PreferencesFile"
    exit 1
}
$PreferencesFile = (Resolve-Path -LiteralPath $PreferencesFile).Path
$linkPath        = Join-Path $HOME '.claude' 'CLAUDE.md'

function Set-FileSymlink {
    param(
        [string]$Link,
        [string]$Target,
        [bool]$AllowOverwrite
    )

    $parent = Split-Path -Parent $Link
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $Link) {
        $existing = Get-Item -LiteralPath $Link -Force
        if ($existing.LinkType -eq 'SymbolicLink' -and $existing.Target -eq $Target) {
            Write-Host "  Already linked: $Link" -ForegroundColor Green
            return $true
        }
        if ($existing.LinkType -ne 'SymbolicLink' -and -not $AllowOverwrite) {
            $backup = "$Link.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Move-Item -LiteralPath $Link -Destination $backup -Force
            Write-Host "  Backed up existing file to: $backup" -ForegroundColor Yellow
        } else {
            Remove-Item -LiteralPath $Link -Force
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -Force -ErrorAction Stop | Out-Null
        Write-Host "  Linked: $Link -> $Target" -ForegroundColor Green
        return $true
    } catch {
        if ($_.Exception.Message -match 'privilege|administrator') { return $false }
        throw
    }
}

Write-Host ''
Write-Host 'Claude preferences' -ForegroundColor Cyan
Write-Host '==================' -ForegroundColor Cyan

$ok = Set-FileSymlink -Link $linkPath -Target $PreferencesFile -AllowOverwrite:$Force.IsPresent
if (-not $ok) {
    Write-Warning 'Creating file symlinks requires administrator privileges; relaunching elevated...'
    $relaunchArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -PreferencesFile `"$PreferencesFile`" -Force"
    Start-Process pwsh -ArgumentList $relaunchArgs -Verb RunAs -Wait
}

exit 0
