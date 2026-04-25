#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Prevents RDP idle disconnection and Azure Dev Box auto-hibernate.

.DESCRIPTION
    Simulates minimal user activity by toggling ScrollLock (invisible to the user)
    every few minutes. This keeps the session "active" from the perspective of:
      - RDP idle-timeout policies (Terminal Services MaxIdleTime)
      - Azure Dev Box auto-stop / auto-hibernate schedules
      - Windows lock-screen timeout

    Designed to run as a scheduled task under the interactive session.
    Exits silently if no interactive desktop is available.
#>

$ErrorActionPreference = 'Stop'

# Only run when there is an interactive session (RDP or console).
# Under a disconnected TS session the input simulation would fail.
Add-Type -AssemblyName System.Windows.Forms

# Toggle ScrollLock twice (on then off) — net zero effect, but registers as
# keyboard input for idle-detection purposes.
[System.Windows.Forms.SendKeys]::SendWait("{SCROLLLOCK}")
Start-Sleep -Milliseconds 50
[System.Windows.Forms.SendKeys]::SendWait("{SCROLLLOCK}")
