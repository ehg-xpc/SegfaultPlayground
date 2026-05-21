@echo off
REM devsetup.cmd
REM Purpose: Launch the repository device/setup helper `Devenv\SetupDevice.ps1` in PowerShell.
REM Summary: Orchestrates full device provisioning via `Devenv\SetupDevice.ps1`.
REM          That PS1 entrypoint validates elevation and then runs idempotent
REM          sub-scripts which install package managers (Scoop/winget), install
REM          packages, configure PATH and environment variables, register
REM          Defender exclusions, configure Windows Terminal and prompts,
REM          register scheduled tasks (KeepAlive, RepoMaintenance), and wire
REM          up CLI preferences and marketplace plugins (Agents/*).
REM Behavior: If the calling shell already has administrative rights the script invokes `pwsh` directly.
REM           Otherwise it elevates by launching PowerShell with `Start-Process -Verb RunAs` to run pwsh elevated.
REM Usage:   devsetup.cmd [args]
REM Example: devsetup.cmd -Force -Verbose

setlocal enabledelayedexpansion

REM Path to the PowerShell setup script relative to this script's location
set "SCRIPT=%~dp0Devenv\SetupDevice.ps1"

REM Build a comma-separated list of quoted args for PowerShell's ArgumentList
REM This is used when constructing the -ArgumentList for Start-Process so all args are forwarded.
set "PS_ARGS='-NoExit','-ExecutionPolicy','Bypass','-File','%SCRIPT%'"
for %%A in (%*) do set "PS_ARGS=!PS_ARGS!,'%%A'"

REM Check if already running as admin; skip elevation if so
net session >nul 2>&1
if %errorlevel% == 0 (
    REM Already elevated: run pwsh directly so the window remains open after the script completes
    pwsh -NoExit -ExecutionPolicy Bypass -File "%SCRIPT%" %*
) else (
    REM Not elevated: request elevation and pass the same arguments to the elevated pwsh process
    powershell -NoProfile -Command "Start-Process pwsh -ArgumentList @(%PS_ARGS%) -Verb RunAs"
)
