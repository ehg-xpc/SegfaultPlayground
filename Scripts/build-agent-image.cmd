@echo off
:: build-agent-image.cmd - Build the dev-node Docker image
::
:: Usage:
::   build-agent-image.cmd
::
:: Builds the image tagged as 'dev-node' from Docker/dev-node/Dockerfile.

setlocal

set "REPO_ROOT=%~dp0.."
set "CONTEXT=%REPO_ROOT%\Docker\dev-node"

echo [build-agent-image] Building dev-node image...
docker build -t dev-node "%CONTEXT%"

if %errorlevel% neq 0 (
    echo [build-agent-image] Build failed.
    exit /b %errorlevel%
)

echo [build-agent-image] Build complete. Verifying CLIs...
docker run --rm dev-node claude --version
docker run --rm dev-node opencode --version
docker run --rm dev-node gh --version

if %errorlevel% neq 0 (
    echo [build-agent-image] Verification failed.
    exit /b %errorlevel%
)

echo [build-agent-image] Image dev-node is ready.
endlocal
