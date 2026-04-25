@echo off
:: build-agent-image.cmd - Build the ado-agent Docker image
::
:: Usage:
::   build-agent-image.cmd
::
:: Builds the image tagged as 'ado-agent' from Docker/ado-agent/Dockerfile.

setlocal

set "REPO_ROOT=%~dp0.."
set "CONTEXT=%REPO_ROOT%\Docker\ado-agent"

echo [build-agent-image] Building ado-agent image...
docker build -t ado-agent "%CONTEXT%"

if %errorlevel% neq 0 (
    echo [build-agent-image] Build failed.
    exit /b %errorlevel%
)

echo [build-agent-image] Build complete. Verifying claude CLI...
docker run --rm ado-agent claude --dangerously-skip-permissions --version

if %errorlevel% neq 0 (
    echo [build-agent-image] Verification failed: claude --version did not succeed.
    exit /b %errorlevel%
)

echo [build-agent-image] Image ado-agent is ready.
endlocal
