@echo off
setlocal
if /i "%~1"=="-h"     goto :usage
if /i "%~1"=="--help" goto :usage
if /i "%~1"=="/?"     goto :usage

set "REST=%*"
if /i "%~1"=="claude"   goto :withcli
if /i "%~1"=="copilot"  goto :withcli
if /i "%~1"=="opencode" goto :withcli

REM No CLI specified -> wire up all three.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Agents\Run-Setup.ps1" %REST%
exit /b %ERRORLEVEL%

:withcli
set "CLI=%~1"
call set "REST=%%REST:*%CLI%=%%"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Agents\Run-Setup.ps1" -Cli "%CLI%" %REST%
exit /b %ERRORLEVEL%

:usage
echo Usage: setup-agents.cmd [^<claude^|copilot^|opencode^>] [-Force]
echo.
echo Symlinks personal preferences from %%dev_repo%%\Config\^<cli^>\preferences.md
echo into the CLI's home file:
echo   claude   -^> ~/.claude/CLAUDE.md
echo   copilot  -^> ~/.copilot/copilot-instructions.md   (and the VS Code user prompt link)
echo   opencode -^> ~/.config/opencode/AGENTS.md
echo.
echo When no CLI is specified, wires up all three.
exit /b 1
