#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sets up GitHub Copilot shared configuration via granular symlinks.

.DESCRIPTION
    Instead of symlinking the entire ~/.copilot directory, this script creates
    individual symlinks for only the shareable items (copilot-instructions.md, agents/, skills/).
    Session data, auth tokens, logs, and runtime files remain local.

    Additionally, it symlinks copilot-instructions.md into the VS Code user
    prompts folder as personal.instructions.md, so the same instructions apply
    globally across all VS Code Copilot Chat workspaces.

    For each shareable item, the script handles these states:
      - Exists locally but not in repo:  moves to repo, then symlinks
      - Exists in both places:           backs up local, then symlinks to repo
      - Missing locally, exists in repo: creates symlink
      - Missing from both:              creates empty placeholder in repo, then symlinks

    If ~/.copilot is currently a whole-directory symlink (from an older setup),
    the script safely converts it to a real directory with granular symlinks.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\SetupSharedCopilot.ps1
    .\SetupSharedCopilot.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# --- Paths ---
$scriptDir      = Split-Path -Parent $PSCommandPath
$devRepoRoot    = Split-Path -Parent (Split-Path -Parent $scriptDir)
$repoConfigDir  = Join-Path $devRepoRoot "SharedConfig\copilot"
$homeCopilotDir = Join-Path $HOME ".copilot"

# Items to share via symlinks (everything else stays local)
$shareableItems = @(
    @{ Name = "copilot-instructions.md"; IsDirectory = $false }
    @{ Name = "agents";                  IsDirectory = $true  }
    @{ Name = "skills";                  IsDirectory = $true  }
)

# --- Header ---
Write-Host ""
Write-Host "GitHub Copilot CLI Shared Configuration Setup" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Repo config:   $repoConfigDir" -ForegroundColor Yellow
Write-Host "Home .copilot: $homeCopilotDir" -ForegroundColor Yellow
Write-Host "Shared items:  $($shareableItems.Name -join ', ')" -ForegroundColor Yellow
Write-Host ""

# --- Helper: create symlink with elevation fallback ---
function New-SymlinkWithElevation {
    param(
        [string]$Path,
        [string]$Target
    )

    try {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force -ErrorAction Stop | Out-Null
        return $true
    } catch {
        if ($_.Exception.Message -match "privilege|administrator") {
            Write-Warning "Creating symlinks requires administrator privileges."
            Write-Host "Re-launching script with elevation..." -ForegroundColor Yellow

            $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Force"
            Start-Process pwsh -ArgumentList $arguments -Verb RunAs -Wait

            # Check if the elevated run succeeded (verify first symlink)
            $firstItem = $shareableItems[0].Name
            $checkPath = Join-Path $homeCopilotDir $firstItem
            if ((Test-Path $checkPath) -and (Get-Item $checkPath).LinkType -eq "SymbolicLink") {
                return $null  # Signal that elevated process handled everything
            }
            return $false
        } else {
            throw
        }
    }
}

# --- Step 1: Ensure repo SharedConfig/copilot directory exists ---
if (-not (Test-Path $repoConfigDir)) {
    New-Item -ItemType Directory -Path $repoConfigDir -Force | Out-Null
    Write-Host "[+] Created repo config directory" -ForegroundColor Green
}

# --- Step 2: Ensure ~/.copilot is a real directory (not a whole-directory symlink) ---
if (Test-Path $homeCopilotDir) {
    $homeDirItem = Get-Item $homeCopilotDir -Force
    if ($homeDirItem.LinkType -eq "SymbolicLink") {
        $oldTarget = $homeDirItem.Target
        Write-Warning "~/.copilot is currently a whole-directory symlink to: $oldTarget"
        Write-Host "This needs to be converted to a real directory with granular symlinks." -ForegroundColor Yellow

        if (-not $Force) {
            $response = Read-Host "Convert to real directory with granular symlinks? (y/N)"
            if ($response -ne 'y' -and $response -ne 'Y') {
                Write-Host "Aborted by user." -ForegroundColor Yellow
                exit 0
            }
        }

        # Collect non-shareable items from the old symlink target to restore later
        $shareableNames = $shareableItems.Name
        $restoreItems = @()
        if (Test-Path $oldTarget) {
            $restoreItems = Get-ChildItem -Path $oldTarget -Force | Where-Object {
                $shareableNames -notcontains $_.Name
            }
        }

        # Remove the directory symlink
        $homeDirItem.Delete()

        # Create real directory
        New-Item -ItemType Directory -Path $homeCopilotDir -Force | Out-Null

        # Restore non-shareable items
        foreach ($restoreItem in $restoreItems) {
            Copy-Item -Path $restoreItem.FullName -Destination $homeCopilotDir -Recurse -Force
        }

        Write-Host "[+] Converted ~/.copilot to real directory (restored $($restoreItems.Count) local items)" -ForegroundColor Green
    }
} else {
    New-Item -ItemType Directory -Path $homeCopilotDir -Force | Out-Null
    Write-Host "[+] Created ~/.copilot directory" -ForegroundColor Green
}

# --- Step 3: Process each shareable item ---
$backupDir = $null
$elevatedExit = $false

foreach ($item in $shareableItems) {
    $itemName = $item.Name
    $isDir    = $item.IsDirectory
    $repoPath = Join-Path $repoConfigDir $itemName
    $homePath = Join-Path $homeCopilotDir $itemName

    Write-Host ""
    Write-Host "--- $itemName ---" -ForegroundColor Cyan

    # Already a correct symlink? Skip.
    if (Test-Path $homePath) {
        $homeItem = Get-Item $homePath -Force
        if ($homeItem.LinkType -eq "SymbolicLink") {
            if ($homeItem.Target -eq $repoPath) {
                Write-Host "  Already symlinked correctly" -ForegroundColor Green
                continue
            } else {
                Write-Host "  Symlink points to wrong target ($($homeItem.Target)), removing..." -ForegroundColor Yellow
                $homeItem.Delete()
            }
        }
    }

    # Determine what exists and act accordingly
    $localExists = Test-Path $homePath
    $repoExists  = Test-Path $repoPath

    if ($localExists -and -not $repoExists) {
        # Local only -> move to repo
        Write-Host "  Moving to repo..." -ForegroundColor Yellow
        $repoParent = Split-Path $repoPath -Parent
        if (-not (Test-Path $repoParent)) {
            New-Item -ItemType Directory -Path $repoParent -Force | Out-Null
        }
        Move-Item -Path $homePath -Destination $repoPath -Force
        Write-Host "  Moved to repo" -ForegroundColor Green

    } elseif ($localExists -and $repoExists) {
        # Both exist -> backup local, use repo version
        if (-not $backupDir) {
            $backupDir = Join-Path $HOME ".copilot.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }
        Write-Host "  Backing up local copy to $backupDir\$itemName" -ForegroundColor Yellow
        Move-Item -Path $homePath -Destination (Join-Path $backupDir $itemName) -Force
        Write-Host "  Backed up" -ForegroundColor Green

    } elseif (-not $localExists -and -not $repoExists) {
        # Neither exists -> create placeholder in repo
        if ($isDir) {
            New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
        } else {
            New-Item -ItemType File -Path $repoPath -Force | Out-Null
        }
        Write-Host "  Created empty placeholder in repo" -ForegroundColor Yellow

    } else {
        # Only in repo -> just need to create symlink
        Write-Host "  Found in repo, creating symlink..." -ForegroundColor Yellow
    }

    # Create the symlink
    $result = New-SymlinkWithElevation -Path $homePath -Target $repoPath
    if ($result -eq $null) {
        # Elevated process took over and handled everything
        $elevatedExit = $true
        break
    } elseif ($result) {
        Write-Host "  Symlinked" -ForegroundColor Green
    } else {
        Write-Host "  FAILED to create symlink" -ForegroundColor Red
    }
}

if ($elevatedExit) {
    # The elevated process ran this script to completion, verify and report
    Write-Host ""
    $allGood = $true
    foreach ($item in $shareableItems) {
        $homePath = Join-Path $homeCopilotDir $item.Name
        if ((Test-Path $homePath) -and (Get-Item $homePath -Force).LinkType -eq "SymbolicLink") {
            Write-Host "[OK] $($item.Name)" -ForegroundColor Green
        } else {
            Write-Host "[!!] $($item.Name) - symlink missing" -ForegroundColor Red
            $allGood = $false
        }
    }
    if ($allGood) {
        Write-Host ""
        Write-Host "All symlinks created successfully by elevated process." -ForegroundColor Green
    }
    exit 0
}

# --- Summary ---
Write-Host ""
Write-Host "Setup Complete" -ForegroundColor Cyan
Write-Host "==============" -ForegroundColor Cyan
Write-Host ""
Write-Host "Shared (version-controlled):" -ForegroundColor Green
foreach ($item in $shareableItems) {
    $homePath = Join-Path $homeCopilotDir $item.Name
    $repoPath = Join-Path $repoConfigDir $item.Name
    Write-Host "  ~/.copilot/$($item.Name) -> $repoPath" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Local only (not shared):" -ForegroundColor Yellow
Write-Host "  config.json, command-history-state.json, mcp-config.json, lsp-config.json," -ForegroundColor Gray
Write-Host "  session-state/, logs/, pkg/, ide/" -ForegroundColor Gray
if ($backupDir) {
    Write-Host ""
    Write-Host "Backups saved to: $backupDir" -ForegroundColor Yellow
}
Write-Host ""

# --- Step 4: Symlink copilot-instructions.md into VS Code user prompts folder ---
$vsCodePromptsDir = Join-Path $env:APPDATA "Code\User\prompts"
$vsCodeInstructionsLink = Join-Path $vsCodePromptsDir "personal.instructions.md"
$repoInstructionsFile = Join-Path $repoConfigDir "copilot-instructions.md"

Write-Host "VS Code User-Level Instructions" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $vsCodePromptsDir)) {
    New-Item -ItemType Directory -Path $vsCodePromptsDir -Force | Out-Null
    Write-Host "[+] Created VS Code prompts directory" -ForegroundColor Green
}

if (Test-Path $vsCodeInstructionsLink) {
    $linkItem = Get-Item $vsCodeInstructionsLink -Force
    if ($linkItem.LinkType -eq "SymbolicLink" -and $linkItem.Target -eq $repoInstructionsFile) {
        Write-Host "  personal.instructions.md already symlinked correctly" -ForegroundColor Green
    } else {
        if ($linkItem.LinkType -eq "SymbolicLink") {
            Write-Host "  Symlink points to wrong target, updating..." -ForegroundColor Yellow
        } else {
            Write-Host "  Replacing existing file with symlink..." -ForegroundColor Yellow
            if (-not $backupDir) {
                $backupDir = Join-Path $HOME ".copilot.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            }
            Copy-Item -Path $vsCodeInstructionsLink -Destination (Join-Path $backupDir "personal.instructions.md") -Force
            Write-Host "  Backed up to $backupDir" -ForegroundColor Green
        }
        Remove-Item $vsCodeInstructionsLink -Force
        $result = New-SymlinkWithElevation -Path $vsCodeInstructionsLink -Target $repoInstructionsFile
        if ($result) {
            Write-Host "  Symlinked personal.instructions.md" -ForegroundColor Green
        } else {
            Write-Host "  FAILED to create symlink" -ForegroundColor Red
        }
    }
} else {
    $result = New-SymlinkWithElevation -Path $vsCodeInstructionsLink -Target $repoInstructionsFile
    if ($result) {
        Write-Host "  Symlinked personal.instructions.md" -ForegroundColor Green
    } else {
        Write-Host "  FAILED to create symlink" -ForegroundColor Red
    }
}

Write-Host "  $vsCodeInstructionsLink -> $repoInstructionsFile" -ForegroundColor Gray
Write-Host ""
