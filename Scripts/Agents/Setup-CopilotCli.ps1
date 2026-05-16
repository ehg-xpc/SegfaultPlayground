#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Symlink ~/.copilot/copilot-instructions.md (and the VS Code user-level
    personal.instructions.md) to a personal preferences file.

.DESCRIPTION
    Creates two file symlinks pointing at -PreferencesFile:
      - ~/.copilot/copilot-instructions.md (Copilot CLI)
      - <Code/User>/prompts/personal.instructions.md (VS Code Copilot Chat,
        global user-level prompts dir)
    Existing non-symlink content at either path is moved aside to
    <linkPath>.backup.<timestamp> first (skipped under -Force). Re-launches
    elevated if the OS rejects the symlink for lack of privilege.

.PARAMETER PreferencesFile
    Path to the preferences file the symlinks should point at.

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

$copilotLink = Join-Path $HOME '.copilot' 'copilot-instructions.md'

# VS Code user prompts dir (platform-specific; XDG even on Windows for VS Code? No --
# VS Code uses APPDATA on Windows, ~/Library on macOS, XDG on Linux).
$vsCodeUserDir = if ($IsWindows -or $null -eq $IsWindows) {
    Join-Path $env:APPDATA 'Code\User'
} elseif ($IsMacOS) {
    Join-Path $HOME 'Library/Application Support/Code/User'
} else {
    $xdg = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
    Join-Path $xdg 'Code/User'
}
$vsCodeLink = Join-Path $vsCodeUserDir 'prompts' 'personal.instructions.md'

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
Write-Host 'Copilot preferences' -ForegroundColor Cyan
Write-Host '===================' -ForegroundColor Cyan

$ok1 = Set-FileSymlink -Link $copilotLink -Target $PreferencesFile -AllowOverwrite:$Force.IsPresent
$ok2 = Set-FileSymlink -Link $vsCodeLink  -Target $PreferencesFile -AllowOverwrite:$Force.IsPresent

if (-not ($ok1 -and $ok2)) {
    Write-Warning 'Creating file symlinks requires administrator privileges; relaunching elevated...'
    $relaunchArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -PreferencesFile `"$PreferencesFile`" -Force"
    Start-Process pwsh -ArgumentList $relaunchArgs -Verb RunAs -Wait
}

exit 0
