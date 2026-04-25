#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Injects shared agent context into a repo's CLAUDE.local.md and sets up symlinks.

.DESCRIPTION
    Sets up agent context for a repository during worktree initialization.

    1. Reads AgentContext/INSTRUCTIONS.md (global instructions for all repos).
    2. Reads ~/.claude/memory/*.md (shared cross-project memory).
    3. Reads AgentContext/{RepoName}/Memory/*.md (repo-specific persistent memory).
    4. Writes/updates a delimited block in {RepoPath}/CLAUDE.local.md, preserving
       any content the user has added outside the markers.
    5. Creates ~/.stanley/shared/{RepoName} as a symlink to AgentContext/{RepoName}/.
    6. Creates ~/.stanley/tasks/{RepoName}/ for local agent tasks.
    7. Migrates any existing tasks from AgentContext/{RepoName}/Tasks/ to local tasks dir.

    The injected block is delimited by:
        <!-- AGENT-CONTEXT:BEGIN -->
        <!-- AGENT-CONTEXT:END -->

    Safe to run on every worktree setup — only the block between the markers is updated.

.PARAMETER RepoName
    The repository name (e.g. "MyRepo").
    Used to determine which memory files to load and where symlinks should point.

.PARAMETER RepoPath
    Full path to the repository root. Required. Typically "." when called from install commands.

.EXAMPLE
    .\SetupSharedAgentContext.ps1 -RepoName "Stanley" -RepoPath "."
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoName,

    [Parameter(Mandatory = $true)]
    [string]$RepoPath
)

$ErrorActionPreference = "Stop"

$scriptDir   = Split-Path -Parent $PSCommandPath
$devRepoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$configPath  = Join-Path $scriptDir "RepositoryConfig.json"
$config      = Get-Content $configPath -Raw | ConvertFrom-Json
$baseRepos   = [Environment]::ExpandEnvironmentVariables($config.baseReposPath)
$agentCtxDir = Join-Path $baseRepos $config.repositories.AgentContext.folderName

$markerBegin = "<!-- AGENT-CONTEXT:BEGIN -->"
$markerEnd   = "<!-- AGENT-CONTEXT:END -->"

# Validate that the repo path exists
if (-not (Test-Path $RepoPath)) {
    Write-Error "Repository path does not exist: $RepoPath"
    exit 1
}

# Clone AgentContext repo if not present
if (-not (Test-Path $agentCtxDir)) {
    Write-Host "[+] Cloning AgentContext repo..." -ForegroundColor Cyan
    $agentCtxUrl = $config.repositories.AgentContext.url
    git clone $agentCtxUrl $agentCtxDir
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to clone AgentContext repo from $agentCtxUrl"
        exit 1
    }
}

# --- Build block content ---
$blockLines = [System.Collections.Generic.List[string]]::new()
$blockLines.Add($markerBegin)
$blockLines.Add("<!-- Auto-generated -->")
$blockLines.Add("")

$instructionsFile = Join-Path $agentCtxDir "INSTRUCTIONS.md"
if (Test-Path $instructionsFile) {
    $blockLines.Add((Get-Content $instructionsFile -Raw).TrimEnd())
    $blockLines.Add("")
}

$sharedMemoryDir = Join-Path (Join-Path $HOME ".claude") "memory"
if (Test-Path $sharedMemoryDir) {
    $sharedMemoryFiles = Get-ChildItem $sharedMemoryDir -Filter "*.md" | Sort-Object Name
    foreach ($file in $sharedMemoryFiles) {
        $memoryContent = (Get-Content $file.FullName -Raw).TrimEnd()
        if ($memoryContent) {
            $blockLines.Add($memoryContent)
            $blockLines.Add("")
        }
    }
}

$memoryDir = Join-Path (Join-Path $agentCtxDir $RepoName) "Memory"
if (Test-Path $memoryDir) {
    $memoryFiles = Get-ChildItem $memoryDir -Filter "*.md" | Sort-Object Name
    foreach ($file in $memoryFiles) {
        $memoryContent = (Get-Content $file.FullName -Raw).TrimEnd()
        if ($memoryContent -and $memoryContent -notmatch "^#\s+\S+\s+.+\s+Memory\s*$") {
            $blockLines.Add($memoryContent)
            $blockLines.Add("")
        }
    }
}

$blockLines.Add($markerEnd)

$newBlock = $blockLines -join "`n"

# --- Update CLAUDE.local.md ---
$claudeLocalMd = Join-Path $RepoPath "CLAUDE.local.md"

if (-not (Test-Path $claudeLocalMd)) {
    # File doesn't exist — create it with just the block
    Set-Content -Path $claudeLocalMd -Value $newBlock -Encoding UTF8
    Write-Host "[+] Created CLAUDE.local.md for $RepoName" -ForegroundColor Green
} else {
    $existing = Get-Content $claudeLocalMd -Raw

    if ($existing -match [regex]::Escape($markerBegin)) {
        # Replace existing block (between markers, inclusive)
        $pattern     = "(?s)" + [regex]::Escape($markerBegin) + ".*?" + [regex]::Escape($markerEnd)
        $updated     = [regex]::Replace($existing.TrimEnd(), $pattern, $newBlock)
        Set-Content -Path $claudeLocalMd -Value $updated -Encoding UTF8
        Write-Host "[~] Inited agent context for $RepoName" -ForegroundColor Cyan
    } else {
        # No markers found — prepend the block, preserving existing user content
        $updated = $newBlock + "`n`n" + $existing.TrimStart()
        Set-Content -Path $claudeLocalMd -Value $updated -Encoding UTF8
        Write-Host "[~] Prepended agent context block to existing CLAUDE.local.md for $RepoName" -ForegroundColor Cyan
    }
}

# --- Create ~/.stanley/shared/{RepoName} symlink to AgentContext/{RepoName} ---
$stanleySharedDir = Join-Path $HOME ".stanley" "shared"
if (-not (Test-Path $stanleySharedDir)) {
    New-Item -ItemType Directory -Path $stanleySharedDir -Force | Out-Null
}

$sharedLink   = Join-Path $stanleySharedDir $RepoName
$sharedTarget = Join-Path $agentCtxDir $RepoName

if (Test-Path $sharedLink -PathType Any) {
    $existing = Get-Item $sharedLink -Force
    if ($existing.LinkType -in @("SymbolicLink", "Junction")) {
        if ($existing.Target -ne $sharedTarget) {
            $existing.Delete()
            Write-Host "[~] Removed stale shared link (was -> $($existing.Target))" -ForegroundColor Yellow
        } else {
            $sharedLink = $null
        }
    }
}

if ($sharedLink) {
    if (-not (Test-Path $sharedTarget)) {
        New-Item -ItemType Directory -Path $sharedTarget -Force | Out-Null
        Write-Host "[+] Created agent context directory: $sharedTarget" -ForegroundColor Green
    }
    try {
        New-Item -ItemType Junction -Path $sharedLink -Target $sharedTarget -Force | Out-Null
        Write-Host "[+] Created ~/.stanley/shared/$RepoName -> $sharedTarget" -ForegroundColor Green
    } catch {
        Write-Warning "Could not create shared junction: $_"
    }
}

# --- Ensure ~/.agent-context symlink points to AgentContext repo root ---
$agentCtxLink = Join-Path $HOME ".agent-context"

if (Test-Path $agentCtxLink -PathType Any) {
    $existing = Get-Item $agentCtxLink -Force
    if ($existing.LinkType -in @("SymbolicLink", "Junction")) {
        if ($existing.Target -ne $agentCtxDir) {
            $existing.Delete()
            Write-Host "[~] Updated ~/.agent-context (was -> $($existing.Target))" -ForegroundColor Yellow
        } else {
            $agentCtxLink = $null
        }
    }
}

if ($agentCtxLink) {
    try {
        New-Item -ItemType Junction -Path $agentCtxLink -Target $agentCtxDir -Force | Out-Null
        Write-Host "[+] Created ~/.agent-context -> $agentCtxDir" -ForegroundColor Green
    } catch {
        Write-Warning "Could not create ~/.agent-context junction: $_"
    }
}

# --- Create ~/.stanley/tasks/{RepoName}/ for local agent tasks ---
$localTasksDir = Join-Path $HOME ".stanley" "tasks" $RepoName
if (-not (Test-Path $localTasksDir)) {
    New-Item -ItemType Directory -Path $localTasksDir -Force | Out-Null
    Write-Host "[+] Created local tasks dir: $localTasksDir" -ForegroundColor Green
}

# --- Migrate tasks from AgentContext/{RepoName}/Tasks/ if they exist ---
$agentCtxTasksDir = Join-Path $agentCtxDir $RepoName "Tasks"
if (Test-Path $agentCtxTasksDir) {
    $taskFiles = Get-ChildItem $agentCtxTasksDir -Filter "*.md" -ErrorAction SilentlyContinue
    foreach ($file in $taskFiles) {
        if ($file.Name -eq ".gitkeep") { continue }
        $dest = Join-Path $localTasksDir $file.Name
        if (-not (Test-Path $dest)) {
            Copy-Item -Path $file.FullName -Destination $dest
            Write-Host "  [>] Migrated task: $($file.Name)" -ForegroundColor Cyan
        }
    }
}

# --- Remove legacy .context junction if it exists ---
$legacyContext = Join-Path $RepoPath ".context"
if (Test-Path $legacyContext -PathType Any) {
    $legacyItem = Get-Item $legacyContext -Force
    if ($legacyItem.LinkType -in @("SymbolicLink", "Junction")) {
        $legacyItem.Delete()
        Write-Host "[~] Removed legacy .context junction" -ForegroundColor Yellow
    }
}
