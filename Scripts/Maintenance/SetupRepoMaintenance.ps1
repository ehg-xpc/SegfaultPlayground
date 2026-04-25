#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Registers the RepoMaintenance Windows Scheduled Task.

.DESCRIPTION
    Creates a task that runs Invoke-RepoMaintenance.ps1 daily at 3 AM using the current
    user's session. The task is configured with StartWhenAvailable so it catches up
    after sleep or reboot. Idempotent: re-running updates the task in place.

    If the legacy \\$env:USERNAME\DailyRepoSync task is present, it is unregistered
    first so the new RepoMaintenance task replaces it cleanly.

.PARAMETER Hour
    Hour of day to run the task (0-23). Defaults to 3.

.PARAMETER Minute
    Minute of the hour. Defaults to 0.

.EXAMPLE
    .\SetupRepoMaintenance.ps1
    .\SetupRepoMaintenance.ps1 -Hour 4 -Minute 30
#>

param(
    [int]$Hour   = 3,
    [int]$Minute = 0
)

$ErrorActionPreference = "Stop"

$taskName   = "RepoMaintenance"
$taskFolder = "\$env:USERNAME"
$taskPath   = "$taskFolder\$taskName"
$syncScript = Join-Path $PSScriptRoot "Invoke-RepoMaintenance.ps1"

if (-not (Test-Path $syncScript)) {
    Write-Host "[!] Invoke-RepoMaintenance.ps1 not found at: $syncScript" -ForegroundColor Red
    exit 1
}

# Migration: remove legacy DailyRepoSync task if present
try {
    $legacyTask = Get-ScheduledTask -TaskName "DailyRepoSync" -TaskPath "$taskFolder\" -ErrorAction SilentlyContinue
    if ($legacyTask) {
        Unregister-ScheduledTask -TaskName "DailyRepoSync" -TaskPath "$taskFolder\" -Confirm:$false
        Write-Host "[i] Removed legacy DailyRepoSync scheduled task" -ForegroundColor Cyan
    }
} catch {
    Write-Host "[!] Failed to remove legacy DailyRepoSync task: $_" -ForegroundColor Yellow
}

# Create task folder if it doesn't exist
$scheduler = New-Object -ComObject "Schedule.Service"
$scheduler.Connect()
$rootFolder = $scheduler.GetFolder("\")
try {
    $rootFolder.GetFolder($env:USERNAME) | Out-Null
} catch {
    $rootFolder.CreateFolder($env:USERNAME) | Out-Null
    Write-Host "[+] Created task folder: $taskFolder" -ForegroundColor Cyan
}

# Build the scheduled task
$triggerTime = (Get-Date).Date.AddHours($Hour).AddMinutes($Minute).ToString("HH:mm")

$action = New-ScheduledTaskAction `
    -Execute  "pwsh.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$syncScript`""

$trigger = New-ScheduledTaskTrigger -Daily -At $triggerTime

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -MultipleInstances IgnoreNew
$settings.WakeToRun = $false

$principal = New-ScheduledTaskPrincipal `
    -UserId    "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel  Highest

$task = New-ScheduledTask `
    -Action      $action `
    -Trigger     $trigger `
    -Settings    $settings `
    -Principal   $principal `
    -Description "Daily per-repo maintenance. Managed by SetupRepoMaintenance.ps1."

Register-ScheduledTask `
    -TaskName $taskName `
    -TaskPath $taskFolder `
    -InputObject $task `
    -Force | Out-Null

Write-Host "[OK] RepoMaintenance task registered: runs daily at $triggerTime (StartWhenAvailable)" -ForegroundColor Green
Write-Host "    Task path : $taskPath" -ForegroundColor Gray
Write-Host "    Script    : $syncScript" -ForegroundColor Gray
Write-Host "    Log file  : $env:LOCALAPPDATA\RepoMaintenance\RepoMaintenance.log" -ForegroundColor Gray
