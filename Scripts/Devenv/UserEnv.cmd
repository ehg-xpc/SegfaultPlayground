@echo off
setlocal EnableDelayedExpansion
cls

set "REPO_NAME=%~1"

set EXEC_PATH=%~dp0
set SCRIPTS_FOLDER=%EXEC_PATH:~0,-1%\..
call :ResolvePath DEV_FOLDER "%SCRIPTS_FOLDER%\.."

set "REPO_SCRIPTS_PATH="

rem Handle repository setup if repository name is provided
if defined REPO_NAME (
    for /f "delims=" %%i in ('pwsh -ExecutionPolicy Bypass -File "%~dp0ManageRepository.ps1" -RepositoryName "!REPO_NAME!" 2^>nul') do (
        set "REPO_PATH=%%i"
    )
    
    if defined REPO_PATH (
        if exist "!REPO_PATH!" (
            cd /d "!REPO_PATH!"
            rem Check for repo-specific scripts folder (convention: Scripts\Repos\{RepositoryName})
            set "REPO_SCRIPTS_PATH=%SCRIPTS_FOLDER%\Repos\!REPO_NAME!"
            if not exist "!REPO_SCRIPTS_PATH!" (
                set "REPO_SCRIPTS_PATH="
            )
        ) else (
            echo Failed to setup repository '!REPO_NAME!'. Continuing with basic environment setup...
        )
    ) else (
        echo Failed to setup repository '!REPO_NAME!'. Continuing with basic environment setup...
    )
)

if defined REPO_PATH (
    set ROOT_FOLDER=!REPO_PATH!
) else (
    set ROOT_FOLDER=%CD%
)

pwsh -ExecutionPolicy Bypass -File "%~dp0ShowBanner.ps1"

rem Log repository info and inject agent context (after banner)
if defined REPO_NAME if defined REPO_PATH if exist "!REPO_PATH!" (
    echo Repository: !REPO_NAME!
    if defined REPO_SCRIPTS_PATH (
        echo Scripts: Repos\!REPO_NAME!
    )
    if exist "%~dp0SetupSharedAgentContext.ps1" (
        pwsh -ExecutionPolicy Bypass -File "%~dp0SetupSharedAgentContext.ps1" -RepoName "!REPO_NAME!" -RepoPath "!REPO_PATH!"
    )
    echo.
)

rem === Set aliases ===
doskey self=pushd "%DEV_FOLDER%"
doskey scripts=pushd "%SCRIPTS_FOLDER%"
doskey root=pushd "%ROOT_FOLDER%"
doskey rebuild=call "%SCRIPTS_FOLDER%\Rebuild.cmd"
doskey devsetup=call "%SCRIPTS_FOLDER%\devsetup.cmd"

:Done
rem Build PATH with repo-specific scripts first if defined
if defined REPO_SCRIPTS_PATH (
    set "PATH=%REPO_SCRIPTS_PATH%;%SCRIPTS_FOLDER%;%PATH%;%DEV_FOLDER%\Tools"
) else (
    set "PATH=%SCRIPTS_FOLDER%;%PATH%;%DEV_FOLDER%\Tools"
)

rem Propagate PATH back to parent scope before setlocal unwinds
endlocal & set "PATH=%PATH%"

exit /b

:ResolvePath
    set %1=%~dpfn2
    exit /b