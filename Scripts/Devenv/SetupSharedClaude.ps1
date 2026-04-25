#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sets up Claude Code shared configuration via granular symlinks.

.DESCRIPTION
    Instead of symlinking the entire ~/.claude directory, this script creates
    individual symlinks for only the shareable items (CLAUDE.md, rules/, hooks/, agents/).
    Session data, API keys, and runtime files remain local.

    For each shareable item, the script handles these states:
      - Exists locally but not in repo:  moves to repo, then symlinks
      - Exists in both places:           backs up local, then symlinks to repo
      - Missing locally, exists in repo: creates symlink
      - Missing from both:              creates empty placeholder in repo, then symlinks

    If ~/.claude is currently a whole-directory symlink (from an older setup),
    the script safely converts it to a real directory with granular symlinks.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\SetupSharedClaude.ps1
    .\SetupSharedClaude.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# --- Paths ---
$scriptDir    = Split-Path -Parent $PSCommandPath
$devRepoRoot  = Split-Path -Parent (Split-Path -Parent $scriptDir)
$repoConfigDir = Join-Path $devRepoRoot "SharedConfig\claude"
$homeClaudeDir = Join-Path $HOME ".claude"

# Items to share via symlinks (everything else stays local)
$shareableItems = @(
    @{ Name = "CLAUDE.md"; IsDirectory = $false }
    @{ Name = "rules";     IsDirectory = $true  }
    @{ Name = "hooks";     IsDirectory = $true  }
    @{ Name = "agents";    IsDirectory = $true  }
    @{ Name = "commands";  IsDirectory = $true  }
    @{ Name = "memory";    IsDirectory = $true  }
)

# --- Header ---
Write-Host ""
Write-Host "Claude Code Shared Configuration Setup" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Repo config:  $repoConfigDir" -ForegroundColor Yellow
Write-Host "Home .claude: $homeClaudeDir" -ForegroundColor Yellow
Write-Host "Shared items: $($shareableItems.Name -join ', ')" -ForegroundColor Yellow
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
            $checkPath = Join-Path $homeClaudeDir $firstItem
            if ((Test-Path $checkPath) -and (Get-Item $checkPath).LinkType -eq "SymbolicLink") {
                return $null  # Signal that elevated process handled everything
            }
            return $false
        } else {
            throw
        }
    }
}

# --- Step 1: Ensure repo SharedConfig/claude directory exists ---
if (-not (Test-Path $repoConfigDir)) {
    New-Item -ItemType Directory -Path $repoConfigDir -Force | Out-Null
    Write-Host "[+] Created repo config directory" -ForegroundColor Green
}

# --- Step 2: Ensure ~/.claude is a real directory (not a whole-directory symlink) ---
if (Test-Path $homeClaudeDir) {
    $homeDirItem = Get-Item $homeClaudeDir -Force
    if ($homeDirItem.LinkType -eq "SymbolicLink") {
        $oldTarget = $homeDirItem.Target
        Write-Warning "~/.claude is currently a whole-directory symlink to: $oldTarget"
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
        New-Item -ItemType Directory -Path $homeClaudeDir -Force | Out-Null

        # Restore non-shareable items
        foreach ($restoreItem in $restoreItems) {
            Copy-Item -Path $restoreItem.FullName -Destination $homeClaudeDir -Recurse -Force
        }

        Write-Host "[+] Converted ~/.claude to real directory (restored $($restoreItems.Count) local items)" -ForegroundColor Green
    }
} else {
    New-Item -ItemType Directory -Path $homeClaudeDir -Force | Out-Null
    Write-Host "[+] Created ~/.claude directory" -ForegroundColor Green
}

# --- Step 3: Process each shareable item ---
$backupDir = $null
$elevatedExit = $false

foreach ($item in $shareableItems) {
    $itemName = $item.Name
    $isDir    = $item.IsDirectory
    $repoPath = Join-Path $repoConfigDir $itemName
    $homePath = Join-Path $homeClaudeDir $itemName

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
        # Local only → move to repo
        Write-Host "  Moving to repo..." -ForegroundColor Yellow
        $repoParent = Split-Path $repoPath -Parent
        if (-not (Test-Path $repoParent)) {
            New-Item -ItemType Directory -Path $repoParent -Force | Out-Null
        }
        Move-Item -Path $homePath -Destination $repoPath -Force
        Write-Host "  Moved to repo" -ForegroundColor Green

    } elseif ($localExists -and $repoExists) {
        # Both exist → backup local, use repo version
        if (-not $backupDir) {
            $backupDir = Join-Path $HOME ".claude.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }
        Write-Host "  Backing up local copy to $backupDir\$itemName" -ForegroundColor Yellow
        Move-Item -Path $homePath -Destination (Join-Path $backupDir $itemName) -Force
        Write-Host "  Backed up" -ForegroundColor Green

    } elseif (-not $localExists -and -not $repoExists) {
        # Neither exists → create placeholder in repo
        if ($isDir) {
            New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
        } else {
            New-Item -ItemType File -Path $repoPath -Force | Out-Null
        }
        Write-Host "  Created empty placeholder in repo" -ForegroundColor Yellow

    } else {
        # Only in repo → just need to create symlink
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
        $homePath = Join-Path $homeClaudeDir $item.Name
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

# --- Step 4: Auto-register Claude Code hooks from ~/.claude/hooks/ into settings.json ---
#
# Hook scripts follow the naming convention: <EventName>--<Matcher>.sh (double-dash separator).
#
#   <EventName> is one of the Claude Code hook events:
#     SessionStart, InstructionsLoaded, UserPromptSubmit, PreToolUse, PermissionRequest,
#     PostToolUse, PostToolUseFailure, Notification, SubagentStart, SubagentStop, Stop,
#     TeammateIdle, TaskCompleted, ConfigChange, WorktreeCreate, WorktreeRemove,
#     PreCompact, SessionEnd.
#
#   <Matcher> is the matcher regex for tool/notification events (e.g. Bash, Edit, Edit_Write
#     where _ maps to | since | is not valid in filenames).
#
#   Scripts without a matcher use just <EventName>.sh (e.g. Stop.sh).
#   Files that don't match either pattern are skipped with a warning.
#

$hooksDir = Join-Path $homeClaudeDir "hooks"
$settingsPath = Join-Path $homeClaudeDir "settings.json"

Write-Host ""
Write-Host "--- Hook Registration ---" -ForegroundColor Cyan

# Load or initialize settings
if (Test-Path $settingsPath) {
    $settingsJson = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    $settingsJson = [pscustomobject]@{}
}

# Scan for hook scripts
$hookScripts = @()
if (Test-Path $hooksDir) {
    $hookScripts = Get-ChildItem -Path $hooksDir -Filter "*.sh" | Where-Object { $_.Name -ne ".gitkeep" }
}

if ($hookScripts.Count -eq 0) {
    # No hook scripts — remove hooks key if present
    if ($settingsJson.PSObject.Properties['hooks']) {
        $settingsJson.PSObject.Properties.Remove('hooks')
        $settingsJson | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8
        Write-Host "  No hook scripts found, removed hooks from settings.json" -ForegroundColor Yellow
    } else {
        Write-Host "  No hook scripts found, nothing to register" -ForegroundColor Gray
    }
} else {
    # Parse scripts and build hooks structure grouped by event+matcher
    $hookEntries = @{}  # key = EventName, value = hashtable of matcher -> list of command paths

    foreach ($script in $hookScripts) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($script.Name)

        if ($baseName -match '^([A-Za-z]+)--(.+)$') {
            $eventName = $Matches[1]
            $matcher   = $Matches[2] -replace '_', '|'
        } elseif ($baseName -match '^([A-Za-z]+)$') {
            $eventName = $Matches[1]
            $matcher   = $null
        } else {
            Write-Warning "  Skipping '$($script.Name)' - does not match hook naming convention"
            continue
        }

        $commandPath = $script.FullName -replace '\\', '/'

        if (-not $hookEntries.ContainsKey($eventName)) {
            $hookEntries[$eventName] = @{}
        }

        $matcherKey = if ($matcher) { $matcher } else { '' }
        if (-not $hookEntries[$eventName].ContainsKey($matcherKey)) {
            $hookEntries[$eventName][$matcherKey] = @()
        }
        $hookEntries[$eventName][$matcherKey] += $commandPath
    }

    # Build the hooks object for settings.json
    $hooksObject = @{}
    foreach ($eventName in $hookEntries.Keys) {
        $eventEntries = @()
        foreach ($matcherKey in $hookEntries[$eventName].Keys) {
            $entry = @{
                hooks = @()
            }
            if ($matcherKey -ne '') {
                $entry['matcher'] = $matcherKey
            }
            foreach ($cmdPath in $hookEntries[$eventName][$matcherKey]) {
                $entry['hooks'] += @{
                    type    = 'command'
                    command = $cmdPath
                }
            }
            $eventEntries += $entry
        }
        $hooksObject[$eventName] = $eventEntries
    }

    # Merge into settings — replace only the hooks key
    if ($settingsJson.PSObject.Properties['hooks']) {
        $settingsJson.PSObject.Properties.Remove('hooks')
    }
    $settingsJson | Add-Member -NotePropertyName 'hooks' -NotePropertyValue $hooksObject

    $settingsJson | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8

    $totalScripts = ($hookScripts | Measure-Object).Count
    Write-Host "  Registered $totalScripts hook script(s) into settings.json" -ForegroundColor Green
}

# --- Step 5: Ensure baseline permissions are in settings.json ---
#
# Ensures a generous allow-list for near-autonomous coding agent execution.
# Includes file tools, common dev commands, and safe defaults.
#

Write-Host ""
Write-Host "--- Baseline Permissions ---" -ForegroundColor Cyan

# Reload settings in case hook registration modified the file
if (Test-Path $settingsPath) {
    $settingsJson = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    $settingsJson = [pscustomobject]@{}
}

$requiredPermissions = @(
    # File tools — unrestricted
    "Read",
    "Edit",
    "Write",

    # Agent context shared dir (~/.stanley/)
    "Read(~/.stanley/**)",
    "Write(~/.stanley/**)",

    # Dev commands
    "Bash(git *)",
    "Bash(gh *)",
    "Bash(az *)",
    "Bash(npm *)",
    "Bash(npx *)",
    "Bash(node *)",
    "Bash(tsc *)",
    "Bash(uv *)",
    "Bash(uv run *)",
    "Bash(cargo *)",
    "Bash(dotnet *)",
    "Bash(pwsh *)",
    "Bash(powershell *)",
    "Bash(cmd *)",
    "Bash(cmd.exe *)",

    # Build and test
    "Bash(make *)",
    "Bash(cmake *)",
    "Bash(msbuild *)",
    "Bash(vitest *)",
    "Bash(jest *)",
    "Bash(pytest *)",

    # Filesystem and shell basics
    "Bash(ls *)",
    "Bash(ls)",
    "Bash(pwd)",
    "Bash(cat *)",
    "Bash(head *)",
    "Bash(tail *)",
    "Bash(find)",
    "Bash(find *)",
    "Bash(grep *)",
    "Bash(rg *)",
    "Bash(wc *)",
    "Bash(diff *)",
    "Bash(mkdir *)",
    "Bash(cp *)",
    "Bash(mv *)",
    "Bash(touch *)",
    "Bash(echo *)",
    "Bash(which *)",
    "Bash(where *)",
    "Bash(file *)",
    "Bash(sort *)",
    "Bash(uniq *)",
    "Bash(sed *)",
    "Bash(awk *)",
    "Bash(tr *)",
    "Bash(cut *)",
    "Bash(xargs *)",
    "Bash(env *)",
    "Bash(printenv *)",
    "Bash(cd *)",

    # Version checks
    "Bash(* --version)",
    "Bash(* --help)"
)

# Ensure permissions.allow exists
if (-not $settingsJson.PSObject.Properties['permissions']) {
    $settingsJson | Add-Member -NotePropertyName 'permissions' -NotePropertyValue ([pscustomobject]@{})
}
if (-not $settingsJson.permissions.PSObject.Properties['allow']) {
    $settingsJson.permissions | Add-Member -NotePropertyName 'allow' -NotePropertyValue @()
}

$existingAllow = @($settingsJson.permissions.allow)
$added = 0

foreach ($perm in $requiredPermissions) {
    if ($existingAllow -notcontains $perm) {
        $existingAllow += $perm
        $added++
    }
}

$settingsJson.permissions.allow = $existingAllow
$settingsJson | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8

if ($added -gt 0) {
    Write-Host "  Added $added permission(s) to settings.json" -ForegroundColor Green
} else {
    Write-Host "  All baseline permissions already present" -ForegroundColor Gray
}

# --- Summary ---
Write-Host ""
Write-Host "Setup Complete" -ForegroundColor Cyan
Write-Host "==============" -ForegroundColor Cyan
Write-Host ""
Write-Host "Shared (version-controlled):" -ForegroundColor Green
foreach ($item in $shareableItems) {
    $homePath = Join-Path $homeClaudeDir $item.Name
    $repoPath = Join-Path $repoConfigDir $item.Name
    Write-Host "  ~/.claude/$($item.Name) -> $repoPath" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Local only (not shared):" -ForegroundColor Yellow
Write-Host "  config.json, settings.json, history, projects, sessions, etc." -ForegroundColor Gray
if ($backupDir) {
    Write-Host ""
    Write-Host "Backups saved to: $backupDir" -ForegroundColor Yellow
}
Write-Host ""
