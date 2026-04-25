<#
.SYNOPSIS
    Resets Scoop buckets to clean state by resolving git merge conflicts.

.DESCRIPTION
    This script resets all Scoop buckets to their remote state, discarding any local changes
    that might be causing merge conflicts during package installations.

.EXAMPLE
    .\ResetScoopBuckets.ps1
#>

Write-Host "Resetting Scoop buckets to clean state..." -ForegroundColor Cyan

$SCOOP_ROOT = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE 'scoop' }
$BUCKETS = Join-Path $SCOOP_ROOT 'buckets'

Get-ChildItem $BUCKETS -Directory | ForEach-Object {
    Write-Host "Resetting bucket: $($_.Name)" -ForegroundColor Yellow
    
    Push-Location $_.FullName
    if (Test-Path '.git') {
        try {
            git fetch origin 2>&1 | Out-Null
            $default = (git remote show origin) -match 'HEAD branch' | ForEach-Object { $_.Split(':')[-1].Trim() }
            if (-not $default) { $default = 'master' }
            git reset --hard "origin/$default" 2>&1 | Out-Null
            git clean -fdx 2>&1 | Out-Null
            
            Write-Host "[✓] Reset bucket: $($_.Name)" -ForegroundColor Green
        } catch {
            Write-Host "[✗] Failed to reset bucket: $($_.Name) - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Pop-Location
}

Write-Host "Running scoop update..." -ForegroundColor Cyan
scoop update

Write-Host "Bucket reset complete" -ForegroundColor Green
