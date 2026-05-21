@echo off
REM setup-agents.cmd
REM Purpose: Symlink or copy repository CLI preference files into personal CLI config locations.
REM Summary: Calls `Agents\Run-Setup.ps1` to wire repository-provided CLI preferences
REM          into user config locations. For each supported CLI it will create
REM          symlinks or copies of files under `Config/<cli>/preferences.md` into
REM          the CLI's expected home path (example: claude -> ~/.claude/CLAUDE.md,
REM          copilot -> ~/.copilot/copilot-instructions.md, opencode -> ~/.config/opencode/AGENTS.md).
REM          When no CLI token is provided the script configures all supported CLIs
REM          and may also perform VS Code user prompt linking for Copilot.
REM Behavior: Runs `Agents\Run-Setup.ps1` to wire up preferences for one or more CLIs.
REM Usage: setup-agents.cmd [claude|copilot|opencode] [-Force]
REM When no CLI is specified, the script will configure all supported CLIs.

setlocal
if /i "%~1"=="-h"     goto :usage
if /i "%~1"=="--help" goto :usage
if /i "%~1"=="/?"     goto :usage

REM Preserve all arguments for forwarding to the PowerShell setup script
set "REST=%*"

REM If the user specified a single CLI, jump to the handler that restricts the setup to that CLI.
if /i "%~1"=="claude"   goto :withcli
if /i "%~1"=="copilot"  goto :withcli
if /i "%~1"=="opencode" goto :withcli

REM No CLI specified -> wire up all three supported CLIs.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Agents\Run-Setup.ps1" %REST%
exit /b %ERRORLEVEL%

:withcli
set "CLI=%~1"
REM Remove the CLI token from the saved REST var so it is not passed twice to the PowerShell script
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
