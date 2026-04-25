#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Registers a scheduled task that keeps the session alive.

.DESCRIPTION
    Creates a task that runs KeepAlive.ps1 every N minutes to simulate user
    activity. This prevents RDP idle disconnection and Azure Dev Box
    auto-hibernate from kicking in during long builds or remote sessions.

    Also sets RDP session-timeout registry policies to "never" so that
    Terminal Services doesn't disconnect or limit idle sessions.

    Idempotent: re-running updates the task and registry in place.

.PARAMETER IntervalMinutes
    How often to fire the keep-alive, in minutes. Defaults to 4.

.EXAMPLE
    .\SetupKeepAlive.ps1
    .\SetupKeepAlive.ps1 -IntervalMinutes 2
#>

param(
    [int]$IntervalMinutes = 4
)

$ErrorActionPreference = "Stop"

# ── RDP session-timeout policies ────────────────────────────────────────────
# These require admin; skip gracefully when running unprivileged.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Write-Host "Setting RDP session-timeout policies to disabled..." -ForegroundColor Cyan

    $tsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
    if (-not (Test-Path $tsPath)) {
        New-Item -Path $tsPath -Force | Out-Null
    }

    # MaxIdleTime: milliseconds before an idle session is disconnected (0 = never)
    Set-ItemProperty -Path $tsPath -Name "MaxIdleTime"           -Value 0 -Type DWord
    # MaxDisconnectionTime: ms before a disconnected session is ended (0 = never)
    Set-ItemProperty -Path $tsPath -Name "MaxDisconnectionTime"  -Value 0 -Type DWord
    # fResetBroken: don't terminate broken connections automatically
    Set-ItemProperty -Path $tsPath -Name "fResetBroken"          -Value 0 -Type DWord

    Write-Host "  MaxIdleTime = 0 (never)" -ForegroundColor Green
    Write-Host "  MaxDisconnectionTime = 0 (never)" -ForegroundColor Green
    Write-Host "  fResetBroken = 0 (keep broken sessions)" -ForegroundColor Green
} else {
    Write-Host "[i] Skipping RDP timeout registry (requires admin)" -ForegroundColor Yellow
}

# ── Scheduled task ──────────────────────────────────────────────────────────
$taskName   = "KeepAlive"
$taskFolder = "\$env:USERNAME"
$keepAliveScript = Join-Path $PSScriptRoot "KeepAlive.ps1"

if (-not (Test-Path $keepAliveScript)) {
    Write-Host "[!] KeepAlive.ps1 not found at: $keepAliveScript" -ForegroundColor Red
    exit 1
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

$action = New-ScheduledTaskAction `
    -Execute  "pwsh.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$keepAliveScript`""

# RepetitionInterval trigger: fire every N minutes, indefinitely, starting at logon.
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At "00:00" `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)).Repetition

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries
$settings.WakeToRun          = $false
$settings.DisallowStartOnRemoteAppSession = $false

$principal = New-ScheduledTaskPrincipal `
    -UserId    "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive

$task = New-ScheduledTask `
    -Action      $action `
    -Trigger     $trigger `
    -Settings    $settings `
    -Principal   $principal `
    -Description "Simulates minimal input every $IntervalMinutes min to prevent RDP idle disconnect and Azure Dev Box auto-hibernate. Managed by SetupKeepAlive.ps1."

Register-ScheduledTask `
    -TaskName $taskName `
    -TaskPath $taskFolder `
    -InputObject $task `
    -Force | Out-Null

Write-Host "[+] KeepAlive task registered: fires every $IntervalMinutes minutes at logon" -ForegroundColor Green
Write-Host "    Task path : $taskFolder\$taskName" -ForegroundColor Gray
Write-Host "    Script    : $keepAliveScript" -ForegroundColor Gray
