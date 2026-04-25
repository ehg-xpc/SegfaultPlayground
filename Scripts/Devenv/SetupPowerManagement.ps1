# SetupPowerManagement.ps1
# Disables hibernation, Modern Standby (S0 Low Power Idle), and sleep/monitor
# timeouts on AC power. Prevents the machine from entering unwanted low-power
# states that interfere with long-running builds and remote sessions.
#
# Registry keys:
#   HibernateEnabled      = 0  -> disable hibernate
#   HiberFileType          = 0  -> disable reduced hiberfile (fast startup)
#   PlatformAoAcOverride   = 0  -> disable Modern Standby network activity
#
# Power config:
#   standby-timeout-ac     = 0  -> never sleep on AC
#   monitor-timeout-ac     = 0  -> never turn off display on AC

param([switch]$Quiet)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$regBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'

Set-ItemProperty -Path $regBase -Name HibernateEnabled    -Value 0 -Type DWord
Set-ItemProperty -Path $regBase -Name HiberFileType        -Value 0 -Type DWord
Set-ItemProperty -Path $regBase -Name PlatformAoAcOverride -Value 0 -Type DWord

powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change monitor-timeout-ac 0 | Out-Null

# Disable hibernate via powercfg (also removes hiberfil.sys on next boot)
powercfg /hibernate off 2>$null

if (-not $Quiet) {
    Write-Host "Registry keys set:" -ForegroundColor Cyan
    Write-Host "  HibernateEnabled = 0" -ForegroundColor Green
    Write-Host "  HiberFileType = 0" -ForegroundColor Green
    Write-Host "  PlatformAoAcOverride = 0" -ForegroundColor Green
    Write-Host "  standby-timeout-ac = 0" -ForegroundColor Green
    Write-Host "  monitor-timeout-ac = 0" -ForegroundColor Green
    Write-Host ""
    Write-Host "Verification:" -ForegroundColor Cyan
    powercfg /a
    Write-Host ""
    Write-Host "Power management configured. Hibernate and S0 Low Power Idle should be disabled." -ForegroundColor Cyan
}
