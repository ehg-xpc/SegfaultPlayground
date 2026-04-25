#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Daily per-repo maintenance orchestrator.

.DESCRIPTION
    For each cloned repo in RepositoryConfig.json:
      1. Run Invoke-RepoSync.ps1 to stash, switch to the default branch, and
         pull --ff-only (skipped if the repo sets "skipCommonSync": true).
      2. If a per-repo Invoke-Maintenance.ps1 exists under Scripts/Repos/<RepoName>/,
         invoke it with -RepoPath <absolute repo root>.

    Per-repo Invoke-Maintenance.ps1 scripts may assume the common sync has run
    successfully when they start. If common sync fails for a repo, the per-repo
    script is skipped and the orchestrator moves on to the next repo.

    Logs to: $env:LOCALAPPDATA\RepoMaintenance\RepoMaintenance.log

.NOTES
    Designed to run unattended via Windows Task Scheduler.
#>

$ErrorActionPreference = "Continue"

# --- Logging setup ---
$logDir  = Join-Path $env:LOCALAPPDATA "RepoMaintenance"
$logFile = Join-Path $logDir "RepoMaintenance.log"

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

# Trim log file if it exceeds 10 MB (keep the last 1000 lines)
if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 10MB) {
    $tail = Get-Content $logFile -Tail 1000
    Set-Content -Path $logFile -Value $tail
    Write-Log "Log file trimmed (was > 10 MB)"
}

Write-Log "=== RepoMaintenance started on $env:COMPUTERNAME ==="

# --- Load config ---
$scriptsRoot = Split-Path $PSScriptRoot -Parent
$configPath  = Join-Path $scriptsRoot "Devenv" "RepositoryConfig.json"

if (-not (Test-Path $configPath)) {
    Write-Log "RepositoryConfig.json not found at: $configPath" "ERROR"
    exit 1
}

$config           = Get-Content $configPath -Raw | ConvertFrom-Json
$baseRepos        = [Environment]::ExpandEnvironmentVariables($config.baseReposPath)
$commonSyncScript = Join-Path $PSScriptRoot "Invoke-RepoSync.ps1"

# --- Iterate repos: common sync first, then per-repo maintenance script if present ---
foreach ($repoName in $config.repositories.PSObject.Properties.Name) {
    $repoDef  = $config.repositories.$repoName
    $repoPath = Join-Path $baseRepos $repoDef.folderName

    if (-not (Test-Path (Join-Path $repoPath ".git"))) {
        Write-Log "[$repoName] Not cloned, skipping" "SKIP"
        continue
    }

    # Common sync (unless opted out)
    $commonOk = $true
    if ($repoDef.skipCommonSync -eq $true) {
        Write-Log "[$repoName] Skipping common sync (skipCommonSync=true)"
    } else {
        $repoBranch = if ($repoDef.defaultBranch) { $repoDef.defaultBranch } else { $config.defaultBranch }
        Write-Log "[$repoName] Running common sync (branch: $repoBranch)..."
        $output = & $commonSyncScript -RepoPath $repoPath -DefaultBranch $repoBranch 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-Log "[$repoName] Common sync OK: $($output.Trim())" "OK"
        } else {
            Write-Log "[$repoName] Common sync failed (exit $LASTEXITCODE): $($output.Trim())" "ERROR"
            $commonOk = $false
        }
    }

    if (-not $commonOk) {
        # Repo not in a known state -- don't run the per-repo script
        continue
    }

    # Per-repo maintenance script (optional)
    $maintenanceScript = Join-Path $scriptsRoot "Repos" $repoName "Invoke-Maintenance.ps1"
    if (-not (Test-Path $maintenanceScript)) {
        continue
    }

    Write-Log "[$repoName] Running maintenance script..."
    $output = & $maintenanceScript -RepoPath $repoPath 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Log "[$repoName] Maintenance OK: $($output.Trim())" "OK"
    } else {
        Write-Log "[$repoName] Maintenance failed (exit $LASTEXITCODE): $($output.Trim())" "ERROR"
    }
}

Write-Log "=== RepoMaintenance complete ==="
