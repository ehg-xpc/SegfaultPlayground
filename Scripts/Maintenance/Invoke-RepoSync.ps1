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
    $stashOutput = git -C $RepoPath stash push -m $stashMsg 2>&1
    $stashOutput | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        # Recover from line-ending normalization failures. When core.safecrlf
        # blocks a stash with "fatal: LF would be replaced by CRLF in <path>"
        # (or the inverse), re-checkout the offending paths to align the worktree
        # with the index, then retry. Without this, autocrlf drift on a single
        # file wedges every subsequent maintenance run on the affected repo.
        $stashText = ($stashOutput | Out-String)
        $affected = [regex]::Matches($stashText, 'would be replaced by (?:CRLF|LF) in (.+)') |
                    ForEach-Object { $_.Groups[1].Value.Trim() } |
                    Where-Object { $_ } |
                    Select-Object -Unique

        if ($affected.Count -eq 0) {
            Write-Host "ERROR: stash failed"
            exit 1
        }

        Write-Host "Stash blocked by line-ending mismatch on $($affected.Count) file(s); re-checking-out to normalize..."
        foreach ($file in $affected) {
            Write-Host "  git checkout -- $file"
            git -C $RepoPath checkout -- $file
            if ($LASTEXITCODE -ne 0) {
                Write-Host "ERROR: checkout failed for '$file'"
                exit 1
            }
        }

        # If normalization absorbed all of the dirt, no stash is needed.
        $status = git -C $RepoPath status --porcelain 2>&1
        if ([string]::IsNullOrWhiteSpace($status)) {
            Write-Host "Worktree clean after line-ending normalization; no stash needed."
        } else {
            Write-Host "Retrying stash after line-ending normalization..."
            git -C $RepoPath stash push -m $stashMsg
            if ($LASTEXITCODE -ne 0) {
                Write-Host "ERROR: stash failed after normalization"
                exit 1
            }
        }
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
