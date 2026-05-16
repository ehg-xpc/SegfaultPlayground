@echo off
setlocal enabledelayedexpansion

set "SCRIPT=%~dp0Devenv\SetupDevice.ps1"

:: Build a comma-separated list of quoted args for PowerShell's ArgumentList
set "PS_ARGS='-NoExit','-ExecutionPolicy','Bypass','-File','%SCRIPT%'"
for %%A in (%*) do set "PS_ARGS=!PS_ARGS!,'%%A'"

:: Check if already running as admin; skip elevation if so
net session >nul 2>&1
if %errorlevel% == 0 (
    pwsh -NoExit -ExecutionPolicy Bypass -File "%SCRIPT%" %*
) else (
    powershell -NoProfile -Command "Start-Process pwsh -ArgumentList @(%PS_ARGS%) -Verb RunAs"
)
