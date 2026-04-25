#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Common per-repo daily sync: stash, switch to default branch, pull --ff-only.

.DESCRIPTION
    Idempotent baseline maintenance shared by all repos in the daily run.
    Invoked by Invoke-RepoMaintenance.ps1 before each repo's per-repo
    Invoke-Maintenance.ps1 (if any). Per-repo scripts may assume the repo
    is on its default branch and up to date when they run.

    Stashed changes are NOT auto-popped; surface them with `git stash list`.

.PARAMETER RepoPath
    Absolute path to the repository root.

.PARAMETER DefaultBranch
    Branch to checkout and pull (e.g. main, master).
#>

param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$DefaultBranch
)

$ErrorActionPreference = "Continue"

# Step 1: Stash any local changes
$status = git -C $RepoPath status --porcelain 2>&1
if (-not [string]::IsNullOrWhiteSpace($status)) {
    Write-Host "Stashing local changes..."
    $stashMsg = "RepoMaintenance auto-stash $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    git -C $RepoPath stash push -m $stashMsg
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: stash failed"
        exit 1
    }
}

# Step 2: Switch to default branch (if not already)
$branch = git -C $RepoPath symbolic-ref --short HEAD 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: detached HEAD, cannot proceed"
    exit 1
}
$branch = $branch.Trim()
if ($branch -ne $DefaultBranch) {
    Write-Host "Switching from '$branch' to '$DefaultBranch'..."
    git -C $RepoPath checkout $DefaultBranch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: checkout '$DefaultBranch' failed"
        exit 1
    }
}

# Step 3: Pull
Write-Host "Pulling from origin/$DefaultBranch..."
git -C $RepoPath pull --ff-only origin $DefaultBranch
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: pull failed"
    exit 1
}

exit 0
