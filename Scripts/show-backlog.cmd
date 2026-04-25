@echo off
setlocal

set "SCRIPT=%~dp0_show-backlog.py"
set "FORMAT="
set "ARGS="

:parse
if "%~1"=="" goto run
if /i "%~1"=="--format" (
    set "FORMAT=1"
    shift
    goto parse
)
if /i "%~1"=="-f" (
    set "FORMAT=1"
    shift
    goto parse
)
set "ARGS=%ARGS% %1"
shift
goto parse

:run
if defined FORMAT (
    uv run python "%SCRIPT%" %ARGS% | glow
) else (
    uv run python "%SCRIPT%" %ARGS%
)
