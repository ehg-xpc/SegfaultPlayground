<#
.SYNOPSIS
    Configures a new device with your preferred development environment setup.

.DESCRIPTION
    This script automates the setup of a new development device by:
    1. Installing Scoop and winget package managers if not present
    2. Installing essential development tools via Scoop and winget
    3. Installing Node.js and Python
    4. Running existing configuration scripts (SetupWindowsTerminal, SetupBeyondCompare, etc.)
    5. Configuring Windows Defender exclusions for dev paths and processes

    The script gracefully handles already-installed components and can be run multiple times safely.

.PARAMETER ExplorerSettings
    Apply Windows Explorer settings (Dark Mode and Taskbar configuration). Skipped by default.

.PARAMETER RemoteNode
    Configure power management, PowerToys Keep Awake, and KeepAlive scheduled task so the device
    stays on and reachable. Intended for remote dev nodes; skipped by default on personal machines.

.PARAMETER FullSetup
    Install additional components like Docker Desktop that are skipped by default.

.EXAMPLE
    .\SetupDevice.ps1

.EXAMPLE
    .\SetupDevice.ps1 -ExplorerSettings

.EXAMPLE
    .\SetupDevice.ps1 -RemoteNode

.EXAMPLE
    .\SetupDevice.ps1 -FullSetup

.NOTES
    Must be run from an elevated PowerShell session.

#>

param(
    [switch]$ExplorerSettings,
    [switch]$RemoteNode,
    [switch]$FullSetup
)

$ErrorActionPreference = "Stop"

# Require administrator privileges before doing anything else.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: SetupDevice.ps1 must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click Windows Terminal / PowerShell and choose 'Run as administrator', then re-run." -ForegroundColor Cyan
    exit 1
}

# Validate and install PowerShell 7+ if needed
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "PowerShell 7+ is required. Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host "Attempting to install PowerShell 7 via winget..." -ForegroundColor Cyan
    
    # Check if winget is available
    $wingetAvailable = $false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $wingetAvailable = $true
    } else {
        # Try to find winget via App Installer
        $appInstaller = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
        if ($appInstaller -and $appInstaller.InstallLocation) {
            $wingetPath = Join-Path $appInstaller.InstallLocation "winget.exe"
            if (Test-Path $wingetPath) {
                $env:Path = "$($appInstaller.InstallLocation);$env:Path"
                $wingetAvailable = $true
            }
        }
    }
    
    if ($wingetAvailable) {
        try {
            winget install --id Microsoft.PowerShell --source winget --scope machine --silent --accept-source-agreements --accept-package-agreements
            Write-Host "`nPowerShell 7 has been installed. Please restart this script in PowerShell 7." -ForegroundColor Green
            Write-Host "You can launch it from Start Menu or run: pwsh.exe" -ForegroundColor Cyan
            exit 0
        } catch {
            Write-Host "Failed to install PowerShell via winget: $_" -ForegroundColor Red
        }
    }
    
    # If we get here, installation failed or winget not available
    Write-Host "`nERROR: Could not automatically install PowerShell 7." -ForegroundColor Red
    Write-Host "Please install manually from: https://aka.ms/powershell-release" -ForegroundColor Cyan
    Write-Host "Or via winget: winget install Microsoft.PowerShell" -ForegroundColor Cyan
    exit 1
}

# Track errors during execution
$script:errors = @()

# Verbose output from sub-scripts is appended here instead of being shown in
# the terminal. The path is announced at start and again in the final summary.
$script:logFile = Join-Path $env:TEMP ("SetupDevice-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function Add-ErrorRecord {
    param([string]$Component, [string]$Message)
    $script:errors += @{
        Component = $Component
        Message = $Message
    }
}

function Invoke-SubScript {
    <#
    .SYNOPSIS
        Runs a child setup script and appends all of its output streams to the
        SetupDevice log file instead of the terminal.
    .DESCRIPTION
        Keeps the parent terminal output focused on high-level progress while
        still preserving the full sub-script output for troubleshooting. Any
        terminating error is captured, surfaced as a one-line failure in the
        terminal, and recorded against the supplied $Component label.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [object[]]$ArgumentList = @(),
        [string]$Component
    )

    $name = Split-Path $Path -Leaf
    if (-not $Component) { $Component = $name }

    if (-not (Test-Path $Path)) {
        Write-Info "$name not found, skipping"
        return
    }

    Write-Info "Running $name (output -> log file)..."
    "`n=== $(Get-Date -Format o) :: $name ===" | Out-File -FilePath $script:logFile -Append -Encoding UTF8

    try {
        & $Path @ArgumentList *>&1 | Out-File -FilePath $script:logFile -Append -Encoding UTF8
        Write-Success "$name completed"
    } catch {
        $errorMsg = "${name} failed: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Write-Info "See log for details: $script:logFile"
        Add-ErrorRecord $Component $errorMsg
    }
}

# Color-coded output functions
function Write-Section {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[i] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor Red
}

function Update-SessionPath {
    <#
    .SYNOPSIS
        Safely adds missing paths from User and Machine PATH into the current session.
    .DESCRIPTION
        Pulls both User and Machine scopes (in that order) and appends any directory
        that is not already present in the current session's PATH. Reading both scopes
        is required because some packages (e.g. winget --scope machine, Git for Windows,
        PowerShell 7) only register themselves in Machine PATH. Existing $env:Path
        entries are preserved.
    #>
    # Build a set of already-present entries using exact, case-insensitive comparison
    # so that 'C:\Tools\x' is not falsely treated as already present when 'C:\Tools\xyz'
    # is on PATH.
    $current = @{}
    foreach ($entry in $env:Path -split ';') {
        $trimmed = $entry.TrimEnd('\').Trim()
        if ($trimmed) { $current[$trimmed.ToLowerInvariant()] = $true }
    }

    $userPath    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $candidates  = @()
    if ($userPath)    { $candidates += ($userPath    -split ';') }
    if ($machinePath) { $candidates += ($machinePath -split ';') }

    $pathsToAdd = foreach ($entry in $candidates) {
        $trimmed = $entry.TrimEnd('\').Trim()
        if (-not $trimmed) { continue }
        $key = $trimmed.ToLowerInvariant()
        if ($current.ContainsKey($key)) { continue }
        if (-not (Test-Path $trimmed -ErrorAction SilentlyContinue)) { continue }
        $current[$key] = $true
        $trimmed
    }

    if ($pathsToAdd) {
        $env:Path = $env:Path + ";" + ($pathsToAdd -join ";")
        Write-Verbose "Added $($pathsToAdd.Count) path(s) to current session"
        return $pathsToAdd.Count
    }
    return 0
}

function Add-PathEntry {
    <#
    .SYNOPSIS
        Idempotently adds a directory to the registry PATH (User or Machine) and
        the current session PATH, with optional binary verification.
    .DESCRIPTION
        Replaces the half-dozen ad-hoc "if ($userPath -notlike "*$dir*") { write }"
        blocks scattered through this script. Uses normalized, case-insensitive,
        exact-match deduplication so 'C:\Tools\x' is not falsely treated as
        present when 'C:\Tools\xyz' is on PATH (substring match was a long-standing
        bug in the per-tool helpers).

        Refuses to write a directory that does not exist on disk so we don't
        litter PATH with paths from failed installers.

        When VerifyCommand is provided, runs Get-Command afterwards and records a
        structured failure via Add-ErrorRecord if the binary still isn't
        resolvable -- making install-time PATH problems visible in the final
        summary instead of surfacing as runtime "command not found" later.

        Also warns when the User PATH would approach the 2047-char Windows limit.
    #>
    param(
        [Parameter(Mandatory)][string]$Directory,
        [ValidateSet('User','Machine')][string]$Scope = 'User',
        [string]$VerifyCommand,
        [string]$Component
    )

    if (-not $Directory) { return $false }
    $normalized = $Directory.Trim().TrimEnd('\')
    if (-not $normalized) { return $false }

    if (-not (Test-Path $normalized -ErrorAction SilentlyContinue)) {
        Write-Info "PATH target does not exist (skipped): $normalized"
        return $false
    }

    $key = $normalized.ToLowerInvariant()

    # Registry scope (persistent)
    $current = [Environment]::GetEnvironmentVariable("Path", $Scope)
    $alreadyInScope = $false
    if ($current) {
        foreach ($entry in $current -split ';') {
            $candidate = $entry.Trim().TrimEnd('\').ToLowerInvariant()
            if ($candidate -eq $key) { $alreadyInScope = $true; break }
        }
    }

    if (-not $alreadyInScope) {
        $projectedLength = if ($current) { $current.Length + 1 + $normalized.Length } else { $normalized.Length }
        if ($Scope -eq 'User' -and $projectedLength -gt 1900) {
            Write-Info "WARNING: User PATH would reach $projectedLength chars after adding '$normalized' (Windows limit ~2047). Consider pruning stale entries."
        }
        $newValue = if ($current) { "$current;$normalized" } else { $normalized }
        [Environment]::SetEnvironmentVariable("Path", $newValue, $Scope)
        Write-Success "Added to $Scope PATH: $normalized"
    }

    # Current session
    $alreadyInSession = $false
    foreach ($entry in $env:Path -split ';') {
        $candidate = $entry.Trim().TrimEnd('\').ToLowerInvariant()
        if ($candidate -eq $key) { $alreadyInSession = $true; break }
    }
    if (-not $alreadyInSession) {
        $env:Path = if ($env:Path) { "$env:Path;$normalized" } else { $normalized }
    }

    # Verification: confirm the tool is actually resolvable now
    if ($VerifyCommand) {
        if (Get-Command $VerifyCommand -ErrorAction SilentlyContinue) {
            return $true
        }
        $label = if ($Component) { $Component } else { "PATH ($VerifyCommand)" }
        $msg = "$VerifyCommand still not resolvable after adding $normalized to PATH"
        Write-ErrorMsg $msg
        Add-ErrorRecord $label $msg
        return $false
    }
    return $true
}

function Add-ScoopShimsToPath {
    <#
    .SYNOPSIS
        Ensures the Scoop shims directory is on PATH so Scoop-installed CLIs
        (git, delta, micro, jq, ...) are discoverable without a terminal restart.
    #>
    $shims = Join-Path $env:USERPROFILE "scoop\shims"
    Add-PathEntry -Directory $shims -Scope User -Component "Scoop shims" | Out-Null
}

function Install-Winget {
    # Check if winget is available in current session
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Success "Winget is already installed and available"
        return $true
    }
    
    # Winget may be installed but not available in PowerShell 7+ sessions
    # Check if App Installer package exists
    $appInstaller = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
    
    if ($appInstaller) {
        # Found App Installer - try to add winget to PATH
        $wingetPath = Join-Path $appInstaller.InstallLocation "winget.exe"
        
        if (Test-Path $wingetPath) {
            Write-Info "Found winget at: $wingetPath"
            Write-Info "Adding winget directory to PATH..."
            
            # Add to current session
            $env:Path = "$($appInstaller.InstallLocation);$env:Path"
            
            # Verify it works now
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-Success "Winget is now available in this session"
                return $true
            } else {
                $errorMsg = "App Installer is installed but winget still not accessible. You may need to restart Windows."
                Write-ErrorMsg $errorMsg
                Add-ErrorRecord "Winget" $errorMsg
                return $false
            }
        } else {
            $errorMsg = "App Installer package exists but winget.exe not found at expected location."
            Write-ErrorMsg $errorMsg
            Add-ErrorRecord "Winget" $errorMsg
            return $false
        }
    }
    
    # App Installer not installed - inform user to install manually
    $errorMsg = "Winget (App Installer) is not installed. Please install it from the Microsoft Store."
    Write-ErrorMsg $errorMsg
    Add-ErrorRecord "Winget" $errorMsg
    Write-Info "Visit: https://www.microsoft.com/p/app-installer/9nblggh4nns1"
    return $false
}

function Set-ScoopEnvironmentVariable {
    Write-Info "Setting up SCOOP environment variable..."
    
    # Default Scoop location is in user profile
    $defaultScoopPath = Join-Path $env:USERPROFILE "scoop"
    
    # Check if SCOOP environment variable is already set
    $currentScoop = [Environment]::GetEnvironmentVariable("SCOOP", "User")
    
    if ([string]::IsNullOrEmpty($currentScoop)) {
        # If not set, use the default location
        if (Test-Path $defaultScoopPath) {
            Write-Info "Detected Scoop installation at: $defaultScoopPath"
            [Environment]::SetEnvironmentVariable("SCOOP", $defaultScoopPath, "User")
            $env:SCOOP = $defaultScoopPath
            Write-Success "SCOOP environment variable set to: $defaultScoopPath"
        } else {
            Write-Info "SCOOP environment variable not set, but installation path not found yet"
        }
    } else {
        $env:SCOOP = $currentScoop
        Write-Success "SCOOP environment variable already set to: $currentScoop"
    }
}


function Install-Scoop {
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Success "Scoop is already installed"
        # Ensure SCOOP environment variable is set even if already installed
        Set-ScoopEnvironmentVariable
        return $true
    }

    Write-Info "Installing Scoop package manager..."

    try {
        # Set execution policy for current user
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

        # Download and install Scoop. -RunAsAdmin is required because
        # SetupDevice.ps1 runs elevated and Scoop's installer otherwise refuses.
        Invoke-Expression "& { $(Invoke-RestMethod get.scoop.sh) } -RunAsAdmin"
        
        Write-Success "Scoop installed successfully"
        
        # Add Scoop paths to current session if not already present
        Update-SessionPath | Out-Null

        # Set SCOOP environment variable immediately after installation
        Set-ScoopEnvironmentVariable
        
        return $true
        
    } catch {
        $errorMsg = "Failed to install Scoop: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "Scoop" $errorMsg
        return $false
    }
}

function Install-ScoopBuckets {
    # Check if scoop is available
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Info "Scoop is not available, skipping bucket installation"
        return
    }
    
    $buckets = @("extras", "versions", "nerd-fonts")
    
    Write-Info "Adding Scoop buckets..."
    foreach ($bucket in $buckets) {
        try {
            scoop bucket add $bucket 2>$null
            Write-Success "Added bucket: $bucket"
        } catch {
            Write-Info "Bucket $bucket already exists or failed to add"
        }
    }
}

function Install-ScoopPackages {
    # Check if scoop is available
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Info "Scoop is not available, skipping Scoop package installations"
        Add-ErrorRecord "Scoop Packages" "Skipped because Scoop is not installed"
        return
    }
    
    $packagesFile = Join-Path $PSScriptRoot "scoop-packages.txt"
    if (-not (Test-Path $packagesFile)) {
        Write-ErrorMsg "Scoop packages list not found: $packagesFile"
        Add-ErrorRecord "Scoop Packages" "Packages file not found: $packagesFile"
        return
    }
    $packages = Get-Content $packagesFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' } | ForEach-Object { $_.Trim() }

    Write-Info "Installing Scoop packages..."
    $bucketResetNeeded = $false
    $failedPackages = @()
    
    foreach ($package in $packages) {
        try {
            $installed = scoop list $package 2>$null
            if ($installed) {
                Write-Success "$package is already installed"
            } else {
                Write-Info "Installing $package..."
                $output = scoop install $package 2>&1 | Out-String
                if ($output -match "Your local changes.*would be overwritten by merge") {
                    Write-Info "Detected Scoop bucket merge conflict for $package"
                    $bucketResetNeeded = $true
                    $failedPackages += $package
                    throw "Bucket merge conflict detected"
                }
                Write-Success "Installed $package"
            }
        } catch {
            $errorMsg = $_.Exception.Message
            if ($errorMsg -match "Your local changes.*would be overwritten by merge" -or $errorMsg -match "Bucket merge conflict") {
                Write-Info "Package $package failed due to bucket conflict"
                if (-not $bucketResetNeeded) {
                    $bucketResetNeeded = $true
                }
                if ($failedPackages -notcontains $package) {
                    $failedPackages += $package
                }
            } else {
                Write-ErrorMsg "Failed to install ${package}: $errorMsg"
                Add-ErrorRecord "Scoop Package: $package" "Failed to install ${package}: $errorMsg"
            }
        }
    }
    
    # If bucket reset is needed, reset and retry failed packages
    if ($bucketResetNeeded) {
        Write-Info "Attempting to fix Scoop buckets and retry installations..."

        $resetScript = Join-Path $PSScriptRoot "ResetScoopBuckets.ps1"
        Invoke-SubScript -Path $resetScript -Component "ResetScoopBuckets"

        Write-Info "Retrying failed package installations..."
        foreach ($package in $failedPackages) {
            try {
                $installed = scoop list $package 2>$null
                if (-not $installed) {
                    Write-Info "Retrying installation of $package..."
                    scoop install $package 2>&1 | Out-Null
                    Write-Success "Installed $package on retry"
                }
            } catch {
                $errorMsg = "Still unable to install ${package}: $($_.Exception.Message)"
                Write-ErrorMsg $errorMsg
                Add-ErrorRecord "Scoop Package: $package" $errorMsg
            }
        }
    }

    # Refresh PATH so newly installed shims are available in this session
    Update-SessionPath | Out-Null
}

function Install-WingetPackages {
    # Check if winget is available
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Info "Winget is not available, skipping winget package installations"
        Add-ErrorRecord "Winget Packages" "Skipped because winget is not installed"
        return
    }
    
    $packagesFile = Join-Path $PSScriptRoot "winget-packages.txt"
    if (-not (Test-Path $packagesFile)) {
        Write-ErrorMsg "Winget packages list not found: $packagesFile"
        Add-ErrorRecord "Winget Packages" "Packages file not found: $packagesFile"
        return
    }
    $packages = Get-Content $packagesFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' } | ForEach-Object { $_.Trim() }

    Write-Info "Installing winget packages..."
    foreach ($package in $packages) {
        try {
            # Check if package is already installed using exit code (text matching is
            # unreliable because winget truncates long IDs in table output and may format
            # differently for machine-scoped vs user-scoped installs)
            Write-Info "Checking if $package is installed..."

            winget list --id $package --exact --accept-source-agreements 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Success "$package is already installed"
            } else {
                Write-Info "Installing $package..."
                winget install --id $package --source winget --scope user --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
                
                # Verify installation
                winget list --id $package --exact --accept-source-agreements 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Installed $package"
                } else {
                    Write-Info "$package installation completed (verification unclear)"
                }
            }
        } catch {
            $errorMsg = "Failed to install ${package}: $($_.Exception.Message)"
            Write-ErrorMsg $errorMsg
            Add-ErrorRecord "Winget Package: $package" $errorMsg
        }
    }
    
    # Refresh PATH to include newly installed tools from user PATH
    $added = Update-SessionPath
    if ($added -gt 0) {
        Write-Info "Added $added new path(s) to current session"
    }
}

function Install-DockerDesktop {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Info "Winget is not available, skipping Docker Desktop installation"
        return
    }

    winget list --id Docker.DockerDesktop --exact --accept-source-agreements 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Docker Desktop is already installed"
        return
    }

    Write-Info "Installing Docker Desktop..."
    # Docker Desktop requires machine scope; do not pass --scope user
    $installOutput = winget install --id Docker.DockerDesktop --source winget --silent --accept-source-agreements --accept-package-agreements 2>&1
    $installExitCode = $LASTEXITCODE

    winget list --id Docker.DockerDesktop --exact --accept-source-agreements 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Installed Docker Desktop"
    } else {
        $errorMsg = "Docker Desktop installation failed (exit code $installExitCode): $installOutput"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "Docker Desktop" $errorMsg
    }
}

function Disable-AppExecutionAliases {
    <#
    .SYNOPSIS
        Removes Windows App Execution Alias stubs in %LOCALAPPDATA%\Microsoft\WindowsApps
        so they do not shadow real binaries on PATH.
    .DESCRIPTION
        App Execution Aliases are 0-byte NTFS reparse points that redirect to a
        Microsoft Store install prompt when invoked. We can't uninstall the AppX
        package that provides them (often DesktopAppInstaller, which also
        provides winget) but we can safely delete the alias stubs themselves.

        Generalized from the original Python-only helper so future shadowing
        cases (or any tool that ships an installable Store stub) can be added
        with a single line in the Aliases list.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Aliases,
        [string]$Component = "App Execution Aliases"
    )

    $storeAppsPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
    foreach ($alias in $Aliases) {
        $aliasPath = Join-Path $storeAppsPath $alias
        if (Test-Path $aliasPath) {
            try {
                Remove-Item $aliasPath -Force -ErrorAction Stop
                Write-Success "Removed app execution alias: $alias"
            } catch {
                Write-ErrorMsg "Could not remove ${alias}: $($_.Exception.Message)"
                Add-ErrorRecord $Component "Failed to remove ${alias}: $($_.Exception.Message)"
            }
        } else {
            Write-Success "Alias already removed: $alias"
        }
    }
}

function Install-Python {
    Write-Info "Installing Python 3.12.1 via uv..."

    # Check if uv is available
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Info "uv not found in PATH. Adding user PATH entries..."
        Update-SessionPath | Out-Null

        if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
            Write-ErrorMsg "uv is not available. Cannot install Python."
            Add-ErrorRecord "Python" "uv not available"
            return
        }
    }

    # Disable Windows Store Python aliases that interfere with uv-managed Python.
    # The python.exe/python3.exe stubs redirect to a Store install prompt and
    # shadow uv-managed Python on PATH.
    Disable-AppExecutionAliases -Aliases @("python.exe", "python3.exe") -Component "Python Aliases"

    try {
        # Check if Python is installed via Scoop and remove it
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            $installedPython = scoop list python 2>&1 | Out-String
            if ($installedPython -match "python") {
                Write-Info "Python installed via Scoop detected. Uninstalling to use uv-managed Python..."
                try {
                    scoop uninstall python 2>&1 | Out-Null
                    Write-Success "Scoop-managed Python uninstalled"
                } catch {
                    Write-Info "Could not uninstall Scoop Python (non-fatal): $($_.Exception.Message)"
                }
            }
        }
        
        # Check if Python 3.12.1 is already installed via uv
        $uvPythonList = uv python list 2>&1 | Out-String
        if ($uvPythonList -match "3\.12\.1") {
            Write-Success "Python 3.12.1 is already installed via uv"
            # Pin to 3.12.1 globally
            uv python pin 3.12.1 2>&1 | Out-Null
        } else {
            Write-Info "Installing Python 3.12.1 via uv..."
            uv python install 3.12.1 2>&1 | Out-Null
            
            # Pin to 3.12.1 globally
            Write-Info "Setting Python 3.12.1 as default..."
            uv python pin 3.12.1 2>&1 | Out-Null
            
            Write-Success "Python 3.12.1 installed via uv"
        }

        # uv-managed Python isn't placed on PATH (it's invoked via 'uv run' or
        # an active venv), so no session-PATH refresh is needed here.

        # Verify installation
        $pythonVersion = uv python list 2>&1 | Out-String
        if ($pythonVersion -match "3\.12\.1") {
            Write-Success "Python 3.12.1 verified"
        } else {
            Write-Info "Python 3.12.1 installed but verification unclear"
        }
        
    } catch {
        $errorMsg = "Failed to install Python: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "Python" $errorMsg
    }
}

function Install-NodeJS {
    Write-Info "Installing Node.js via nvm..."

    # nvm-windows installed via Scoop does not add itself to PATH automatically;
    # ensure it is on PATH before we try to invoke it.
    if (-not (Get-Command nvm -ErrorAction SilentlyContinue)) {
        $nvmDir = Get-NvmRootDir
        if ($nvmDir) {
            Add-PathEntry -Directory $nvmDir -Scope User -Component "Node.js" | Out-Null
        }
        if (-not (Get-Command nvm -ErrorAction SilentlyContinue)) {
            Write-ErrorMsg "nvm is not available. Please ensure it was installed correctly."
            Add-ErrorRecord "Node.js" "nvm not available"
            return
        }
    }

    try {
        # Check the installed version via the filesystem instead of capturing nvm output.
        # nvm-windows shows a GUI "Terminal Only" dialog when its stdout/stderr is redirected
        # to a pipe by PowerShell output capture ($var = nvm ...).
        $nvmHome = if ($env:NVM_HOME) { $env:NVM_HOME } else { Join-Path $env:APPDATA "nvm" }
        if (Test-Path (Join-Path $nvmHome "v24.0.0")) {
            Write-Success "Node.js 24.0.0 is already installed"
            nvm use 24.0.0
        } else {
            Write-Info "Installing Node.js 24.0.0..."
            nvm install 24.0.0
            nvm use 24.0.0
            Write-Success "Node.js 24.0.0 installed and activated"
        }

        # nvm-windows places node/npm in a symlink directory it manages; ensure it
        # is on PATH so the rest of this script (npm credprovider, etc.) can find node.
        $nodeSymlink = Get-NodeSymlinkDir
        if ($nodeSymlink) {
            Add-PathEntry -Directory $nodeSymlink -Scope User -Component "Node.js" | Out-Null
        }

        $nodeVersion = node --version 2>$null
        if ($nodeVersion) {
            Write-Success "Node.js version: $nodeVersion"
        }
    } catch {
        $errorMsg = "Failed to install Node.js: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "Node.js" $errorMsg
    }
}

function Install-ClaudeCode {
    Write-Info "Installing Claude Code CLI..."

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Success "Claude Code CLI is already installed"
        return
    }

    try {
        Write-Info "Running Claude Code official installer..."
        Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
        Write-Success "Claude Code CLI installer completed"
    } catch {
        $errorMsg = "Failed to install Claude Code CLI: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "Claude Code" $errorMsg
        return
    }

    # PATH registration for %USERPROFILE%\.local\bin happens in Reconcile-ToolPaths
    # so we don't litter PATH with an entry for a failed install.
}

function Install-NpmArtifactsCredProvider {
    Write-Info "Installing npm Azure Artifacts credential provider..."

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Update-SessionPath | Out-Null
        if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
            $errorMsg = "npm is not available. Ensure Node.js was installed correctly."
            Write-ErrorMsg $errorMsg
            Add-ErrorRecord "npm Artifacts CredProvider" $errorMsg
            return
        }
    }

    try {
        $installed = npm list -g @microsoft/artifacts-npm-credprovider --depth=0 2>$null | Out-String
        if ($installed -match "artifacts-npm-credprovider") {
            Write-Success "npm Azure Artifacts credential provider is already installed"
        } else {
            Write-Info "Installing @microsoft/artifacts-npm-credprovider..."
            npm install --global @microsoft/artifacts-npm-credprovider --registry https://pkgs.dev.azure.com/artifacts-public/PublicTools/_packaging/AzureArtifacts/npm/registry/ 2>&1 | Out-Null
            Write-Success "npm Azure Artifacts credential provider installed"
        }
    } catch {
        $errorMsg = "Failed to install npm Artifacts credential provider: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "npm Artifacts CredProvider" $errorMsg
    }
}

function Configure-Uv {
    Write-Info "Configuring uv Python package manager..."
    
    # Check if uv is available
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Info "uv not found in PATH. Adding user PATH entries..."
        Update-SessionPath | Out-Null

        if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
            Write-Info "uv is not available yet. It may need a terminal restart."
            return
        }
    }
    
    try {
        # Create uv config directory
        $uvConfigPath = Join-Path $env:APPDATA "uv"
        if (-not (Test-Path $uvConfigPath)) {
            New-Item -Path $uvConfigPath -ItemType Directory -Force | Out-Null
            Write-Success "Created uv config directory: $uvConfigPath"
        } else {
            Write-Success "uv config directory already exists"
        }
        
        # Create uv.toml configuration file
        $uvTomlPath = Join-Path $uvConfigPath "uv.toml"
        $tomlContent = @"
[[index]]
url = "https://pypi.org/simple"
default = true

[[index]]
url = "https://tools.svnx.dev/pypi"
explicit = true
"@

        Set-Content -Path $uvTomlPath -Value $tomlContent -Encoding UTF8
        Write-Success "Created uv configuration file: $uvTomlPath"
        Write-Success "Configured default PyPI index and custom index: https://tools.svnx.dev/pypi (explicit)"
        
    } catch {
        $errorMsg = "Failed to configure uv: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "uv Configuration" $errorMsg
    }
}

function Get-VsMSBuildDir {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $null }
    $vsPath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null
    if ([string]::IsNullOrEmpty($vsPath)) { return $null }
    foreach ($subpath in @("MSBuild\Current\Bin", "MSBuild\15.0\Bin")) {
        $candidate = Join-Path $vsPath $subpath
        if (Test-Path (Join-Path $candidate "MSBuild.exe")) { return $candidate }
    }
    return $null
}

function Get-AzureCliDir {
    $candidates = @(
        "${env:ProgramFiles}\Microsoft SDKs\Azure\CLI2\wbin",
        "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\CLI2\wbin",
        "${env:LOCALAPPDATA}\Programs\Microsoft\Azure CLI\wbin"
    )
    foreach ($p in $candidates) {
        if (Test-Path (Join-Path $p "az.cmd")) { return $p }
    }
    return $null
}

function Get-CopilotCliDir {
    # Winget portable packages land under WinGet\Links (symlinked) first; Links is preferred.
    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
    )
    $packagesDir = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
    if (Test-Path $packagesDir) {
        $copilotDirs = Get-ChildItem -Path $packagesDir -Directory -Filter "GitHub.Copilot*" -ErrorAction SilentlyContinue
        foreach ($d in $copilotDirs) { $candidates += $d.FullName }
    }
    foreach ($p in $candidates) {
        if (Test-Path (Join-Path $p "copilot.exe")) { return $p }
    }
    return $null
}

function Get-NvmRootDir {
    $p = Join-Path $env:USERPROFILE "scoop\apps\nvm\current"
    if (Test-Path (Join-Path $p "nvm.exe")) { return $p }
    return $null
}

function Get-NodeSymlinkDir {
    # nvm-windows places the active node/npm in a symlink directory it manages.
    # Prefer the env var it sets; fall back to the conventional sibling of NVM_HOME.
    $candidates = @()
    if ($env:NVM_SYMLINK) { $candidates += $env:NVM_SYMLINK }
    $nvmHome = if ($env:NVM_HOME) { $env:NVM_HOME } else { Join-Path $env:APPDATA "nvm" }
    $candidates += (Join-Path (Split-Path $nvmHome -Parent) "nodejs")
    foreach ($p in $candidates) {
        if (Test-Path (Join-Path $p "node.exe")) { return $p }
    }
    return $null
}

function Get-ClaudeCliDir {
    # The official Claude Code installer drops the binary into %USERPROFILE%\.local\bin.
    $p = Join-Path $env:USERPROFILE ".local\bin"
    foreach ($exe in @("claude.exe", "claude.cmd", "claude")) {
        if (Test-Path (Join-Path $p $exe)) { return $p }
    }
    return $null
}

function Reconcile-ToolPaths {
    <#
    .SYNOPSIS
        Single data-driven sweep that ensures key dev tools are resolvable on PATH.
    .DESCRIPTION
        Replaces the per-tool Add-MSBuildToPath / Add-AzureCliToPath /
        Add-CopilotCliToPath helpers and the inline PATH-fixup blocks inside
        Install-NodeJS and Install-ClaudeCode. Adding a new tool that drops
        outside Scoop shims or WinGet\Links is now a one-row addition to the
        $fixups table here, not a new function.

        For each tool: skip if Get-Command already resolves it; otherwise run
        the probe to locate the install directory and feed it to Add-PathEntry
        with verification, so unresolved tools surface as errors in the final
        summary.
    #>
    $fixups = @(
        @{ Name = "MSBuild";       Verify = "msbuild"; Probe = { Get-VsMSBuildDir } }
        @{ Name = "Azure CLI";     Verify = "az";      Probe = { Get-AzureCliDir } }
        @{ Name = "Copilot CLI";   Verify = "copilot"; Probe = { Get-CopilotCliDir } }
        @{ Name = "nvm";           Verify = "nvm";     Probe = { Get-NvmRootDir } }
        @{ Name = "Node.js";       Verify = "node";    Probe = { Get-NodeSymlinkDir } }
        @{ Name = "Claude Code";   Verify = "claude";  Probe = { Get-ClaudeCliDir } }
    )

    foreach ($fixup in $fixups) {
        if (Get-Command $fixup.Verify -ErrorAction SilentlyContinue) {
            Write-Success "$($fixup.Name) already resolvable on PATH"
            continue
        }
        try {
            $dir = & $fixup.Probe
        } catch {
            Write-Info "$($fixup.Name) probe failed: $($_.Exception.Message)"
            continue
        }
        if (-not $dir) {
            Write-Info "$($fixup.Name) not detected on disk (probably not installed); skipping"
            continue
        }
        Add-PathEntry -Directory $dir -Scope User -VerifyCommand $fixup.Verify -Component $fixup.Name | Out-Null
    }
}

function Send-EnvironmentChangeBroadcast {
    <#
    .SYNOPSIS
        Broadcasts WM_SETTINGCHANGE so already-running shells, Explorer, and
        Windows Terminal pick up the new User PATH (and other env-var changes)
        without requiring sign-out.
    .DESCRIPTION
        [Environment]::SetEnvironmentVariable updates the registry but does NOT
        broadcast; existing processes keep their stale environment block. Most
        installers send this broadcast for us; this script writes PATH directly,
        so we do it ourselves once at the end.
    #>
    try {
        if (-not ('SetupDevice.NativeMethods' -as [type])) {
            Add-Type -Namespace SetupDevice -Name NativeMethods -MemberDefinition @"
                [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
                public static extern System.IntPtr SendMessageTimeout(
                    System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam,
                    uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
"@
        }
        $HWND_BROADCAST   = [System.IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x1a
        $SMTO_ABORTIFHUNG = 0x2
        $result = [UIntPtr]::Zero
        [void][SetupDevice.NativeMethods]::SendMessageTimeout(
            $HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment",
            $SMTO_ABORTIFHUNG, 5000, [ref]$result)
        Write-Success "Broadcast environment change to running processes"
    } catch {
        Write-Info "Could not broadcast environment change: $($_.Exception.Message)"
    }
}

function Write-PathLengthSummary {
    <#
    .SYNOPSIS
        Reports the current length of User and Machine PATH and warns if either
        is approaching the 2047-char Windows limit.
    #>
    foreach ($scope in 'User','Machine') {
        $val = [Environment]::GetEnvironmentVariable("Path", $scope)
        $len = if ($val) { $val.Length } else { 0 }
        if ($len -gt 1900) {
            Write-Host "$scope PATH: $len chars (approaching 2047 limit)" -ForegroundColor Yellow
        } else {
            Write-Host "$scope PATH: $len chars" -ForegroundColor DarkGray
        }
    }
}

function Install-AzureCliExtensions {
    Write-Info "Checking Azure CLI extensions..."

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Info "Azure CLI not found in PATH, skipping extension install"
        return
    }

    $installedExtensions = az extension list --query "[].name" -o tsv 2>$null
    if ($installedExtensions -contains "azure-devops") {
        Write-Success "Azure CLI extension 'azure-devops' already installed"
    } else {
        try {
            Write-Info "Installing Azure CLI extension: azure-devops..."
            az extension add --name azure-devops --yes 2>&1 | Out-Null
            Write-Success "Azure CLI extension 'azure-devops' installed"
        } catch {
            $errorMsg = "Failed to install azure-devops extension: $($_.Exception.Message)"
            Write-ErrorMsg $errorMsg
            Add-ErrorRecord "az extension azure-devops" $errorMsg
        }
    }
}

function Get-DevConfig {
    $configPath = Join-Path $PSScriptRoot "config.json"
    if (Test-Path $configPath) {
        try {
            return Get-Content $configPath -Raw | ConvertFrom-Json
        } catch {
            Write-Warning "Could not parse config.json: $_"
        }
    }
    return $null
}

function Set-GitGlobalConfig {
    Write-Info "Configuring Git global settings..."

    # Check if git is available
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Info "Git not found in PATH, skipping Git configuration"
        return
    }

    $devConfig   = Get-DevConfig
    $desiredName  = if ($devConfig -and $devConfig.user.name  -and $devConfig.user.name  -ne "Your Name")        { $devConfig.user.name }  else { $null }
    $desiredEmail = if ($devConfig -and $devConfig.user.email -and $devConfig.user.email -ne "you@example.com") { $devConfig.user.email } else { $null }

    try {
        # Set user name
        if ($desiredName) {
            $currentName = git config --global user.name 2>$null
            if ($currentName -ne $desiredName) {
                git config --global user.name $desiredName
                Write-Success "Git user.name set to: $desiredName"
            } else {
                Write-Success "Git user.name already set correctly"
            }
        } else {
            Write-Info "Git user.name: not configured (set user.name in Scripts\Devenv\config.json)"
        }

        # Set user email
        if ($desiredEmail) {
            $currentEmail = git config --global user.email 2>$null
            if ($currentEmail -ne $desiredEmail) {
                git config --global user.email $desiredEmail
                Write-Success "Git user.email set to: $desiredEmail"
            } else {
                Write-Success "Git user.email already set correctly"
            }
        } else {
            Write-Info "Git user.email: not configured (set user.email in Scripts\Devenv\config.json)"
        }
        
        # Set credential useHttpPath
        $currentHttpPath = git config --global credential.useHttpPath 2>$null
        if ($currentHttpPath -ne "true") {
            git config --global credential.useHttpPath true
            Write-Success "Git credential.useHttpPath set to: true"
        } else {
            Write-Success "Git credential.useHttpPath already set correctly"
        }

        # Configure delta as the default pager (pretty diffs)
        if (Get-Command delta -ErrorAction SilentlyContinue) {
            $currentPager = git config --global core.pager 2>$null
            if ($currentPager -ne "delta") {
                git config --global core.pager delta
                Write-Success "Git core.pager set to: delta"
            } else {
                Write-Success "Git core.pager already set to delta"
            }

            $currentNavigate = git config --global delta.navigate 2>$null
            if ($currentNavigate -ne "true") {
                git config --global delta.navigate true
            }

            $currentSideBySide = git config --global delta.side-by-side 2>$null
            if ($currentSideBySide -ne "true") {
                git config --global delta.side-by-side true
            }
        } else {
            Write-Info "delta not found in PATH, skipping Git pager configuration (install dandavison.delta)"
        }
    } catch {
        $errorMsg = "Failed to configure Git: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "Git Configuration" $errorMsg
    }
}

function Set-GitBashPathInheritance {
    <#
    .SYNOPSIS
        Ensures Git Bash (MSYS2) inherits the full Windows PATH instead of
        constructing a minimal one that drops User and Machine PATH entries.
    .DESCRIPTION
        MSYS2's /etc/profile reads the MSYS2_PATH_TYPE variable to decide how
        to build the session PATH. The default ("inherit") preserves the full
        Windows PATH. If the variable is set to "minimal" or "strict" in the
        user's ~/.bash_profile, most registry PATH entries (Scoop shims,
        WinGet links, .dotnet/tools, etc.) are silently dropped — breaking
        tools that were correctly installed and added to PATH.

        This function ensures ~/.bash_profile either sets MSYS2_PATH_TYPE to
        "inherit" or leaves it unset (which defaults to "inherit").
    #>
    $bashProfile = Join-Path $env:USERPROFILE ".bash_profile"

    if (-not (Test-Path $bashProfile)) {
        Write-Success "Git Bash PATH inheritance: OK (no ~/.bash_profile override)"
        return
    }

    $content = Get-Content $bashProfile -Raw
    if ($content -match 'MSYS2_PATH_TYPE\s*=\s*(minimal|strict)') {
        $updated = $content -replace 'export\s+MSYS2_PATH_TYPE\s*=\s*(minimal|strict)', 'export MSYS2_PATH_TYPE=inherit'
        Set-Content -Path $bashProfile -Value $updated -NoNewline
        Write-Success "Git Bash PATH inheritance: fixed (MSYS2_PATH_TYPE changed from '$($Matches[1])' to 'inherit')"
    } else {
        Write-Success "Git Bash PATH inheritance: OK"
    }
}

function Set-EditorEnvironmentVariable {
    Write-Info "Setting up EDITOR environment variable..."
    
    try {
        $currentEditor = [Environment]::GetEnvironmentVariable("EDITOR", "User")
        if ($currentEditor -ne "micro") {
            [Environment]::SetEnvironmentVariable("EDITOR", "micro", "User")
            $env:EDITOR = "micro"
            Write-Success "EDITOR environment variable set to: micro"
        } else {
            Write-Success "EDITOR environment variable already set correctly to: micro"
        }
    } catch {
        $errorMsg = "Failed to set EDITOR environment variable: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "EDITOR Environment Variable" $errorMsg
    }
}

function Set-ReposEnvironmentVariable {
    Write-Info "Setting up REPOS environment variable..."
    
    # Determine and set REPOS environment variable
    # Script is in: <REPOS>\Developer\<youralias>\Scripts\Devenv\SetupDevice.ps1
    # We need to go up 4 levels to get to REPOS
    $scriptDir = $PSScriptRoot
    $reposPath = Split-Path (Split-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) -Parent) -Parent
    
    Write-Info "Detected REPOS path: $reposPath"
    try {
        $currentRepos = [Environment]::GetEnvironmentVariable("REPOS", "User")
        if ($currentRepos -ne $reposPath) {
            [Environment]::SetEnvironmentVariable("REPOS", $reposPath, "User")
            $env:REPOS = $reposPath
            Write-Success "REPOS environment variable set to: $reposPath"
        } else {
            Write-Success "REPOS environment variable already set correctly to: $reposPath"
        }
        
        # Create Projects folder (default terminal directory)
        $projectsPath = Join-Path $reposPath "Projects"
        if (-not (Test-Path $projectsPath)) {
            New-Item -Path $projectsPath -ItemType Directory -Force | Out-Null
            Write-Success "Created Projects folder: $projectsPath"
        } else {
            Write-Success "Projects folder already exists: $projectsPath"
        }
        
    } catch {
        $errorMsg = "Failed to set REPOS environment variable or create Projects folder: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "REPOS Environment Variable" $errorMsg
    }
}


function Set-DevRepoEnvironmentVariable {
    Write-Info "Setting up DEV_REPO environment variable..."
    # Script is in: <REPOS>\Developer\<youralias>\Scripts\Devenv\SetupDevice.ps1
    # Go up 2 levels from Scripts\Devenv\ to get the dev repo root
    $scriptDir = $PSScriptRoot
    $devRepoPath = Split-Path (Split-Path $scriptDir -Parent) -Parent

    Write-Info "Detected DEV_REPO path: $devRepoPath"
    try {
        $current = [Environment]::GetEnvironmentVariable("DEV_REPO", "User")
        if ($current -ne $devRepoPath) {
            [Environment]::SetEnvironmentVariable("DEV_REPO", $devRepoPath, "User")
            $env:DEV_REPO = $devRepoPath
            Write-Success "DEV_REPO environment variable set to: $devRepoPath"
        } else {
            Write-Success "DEV_REPO environment variable already set correctly to: $devRepoPath"
        }
    } catch {
        $errorMsg = "Failed to set DEV_REPO environment variable: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "DEV_REPO Environment Variable" $errorMsg
    }
}


function Register-MergeOursDriver {
    # Required by .gitattributes merge=ours rules so divergent paths from the
    # upstream template are kept on this side during template/main merges.
    $devRepoPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $current = git -C $devRepoPath config --local merge.ours.driver 2>$null
    if ($current -ne 'true') {
        git -C $devRepoPath config --local merge.ours.driver true
        Write-Success "Registered git merge driver: ours"
    }
}


function Register-TemplateRemote {
    # Adds the upstream `template` remote so `git fetch template` and
    # `git merge template/main` work without a manual setup step on fresh clones.
    $devRepoPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $templateUrl = 'https://edgarhg.visualstudio.com/ProbablyFine/_git/SegfaultPlayground'
    $existing = git -C $devRepoPath remote get-url template 2>$null
    if (-not $existing) {
        git -C $devRepoPath remote add template $templateUrl
        Write-Success "Registered git remote: template -> $templateUrl"
    } elseif ($existing -ne $templateUrl) {
        Write-Info "Git remote 'template' already set to a different URL; leaving as-is: $existing"
    }
}

function Set-DarkMode {
    Write-Info "Enabling Dark Mode for Windows..."
    
    try {
        # Set Windows theme to Dark
        $personalizePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (-not (Test-Path $personalizePath)) {
            New-Item -Path $personalizePath -Force | Out-Null
        }
        
        # AppsUseLightTheme: 0 = Dark, 1 = Light (for apps)
        Set-ItemProperty -Path $personalizePath -Name "AppsUseLightTheme" -Value 0 -Type DWord
        Write-Success "Apps set to Dark Mode"
        
        # SystemUsesLightTheme: 0 = Dark, 1 = Light (for system/taskbar)
        Set-ItemProperty -Path $personalizePath -Name "SystemUsesLightTheme" -Value 0 -Type DWord
        Write-Success "System set to Dark Mode"
        
        # Force refresh by restarting Explorer (if not already done by taskbar config)
        Write-Info "Restarting Explorer to apply Dark Mode..."
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        Write-Success "Dark Mode enabled successfully"
        Write-Info "Changes should be visible now. You may need to sign out and back in for full effect."
        
    } catch {
        $errorMsg = "Failed to enable Dark Mode: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "Dark Mode" $errorMsg
    }
}

function Remove-NpmCopilot {
    Write-Info "Checking for legacy npm-based GitHub Copilot CLI..."

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        return
    }

    try {
        $installed = npm list -g @github/copilot --depth=0 2>$null | Out-String
        if ($installed -match "@github/copilot") {
            Write-Info "Removing legacy @github/copilot npm package (replaced by winget GitHub.Copilot)..."
            npm uninstall -g @github/copilot 2>&1 | Out-Null
            Write-Success "Removed legacy @github/copilot npm package"
        } else {
            Write-Success "No legacy npm Copilot CLI found"
        }
    } catch {
        $errorMsg = "Failed to remove legacy @github/copilot: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "npm Copilot cleanup" $errorMsg
    }
}


function Set-TaskbarSearchBox {
    Write-Info "Hiding search box from taskbar..."
    
    try {
        # Registry path for Windows 11 taskbar search
        $searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        
        if (-not (Test-Path $searchPath)) {
            New-Item -Path $searchPath -Force | Out-Null
        }
        
        # SearchboxTaskbarMode: 0 = Hidden, 1 = Show search icon, 2 = Show search box
        Set-ItemProperty -Path $searchPath -Name "SearchboxTaskbarMode" -Value 0 -Type DWord
        Write-Success "Taskbar search box hidden"
        
        # Force refresh by restarting Explorer
        Write-Info "Restarting Explorer to apply changes..."
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        Write-Success "Taskbar search box configuration complete"
        
    } catch {
        $errorMsg = "Failed to hide taskbar search box: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "Taskbar Search Box" $errorMsg
    }
}

function Set-UacPolicy {
    Write-Info "Configuring UAC policy..."

    try {
        $policyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

        # ConsentPromptBehaviorAdmin = 5: notify only when non-Windows apps request elevation.
        # Prevents apps from auto-elevating silently (0) without prompting every action (2).
        Set-ItemProperty -Path $policyPath -Name "ConsentPromptBehaviorAdmin" -Value 5 -Type DWord
        Write-Success "UAC: prompt for consent on non-Windows app elevation (level 5)"

    } catch {
        $errorMsg = "Failed to configure UAC policy: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "UAC Policy" $errorMsg
    }
}

function Enable-WindowsSudo {
    Write-Info "Enabling built-in Windows Sudo..."

    # Built-in Sudo ships with Windows 11 24H2+. Use the System32 path directly so
    # we don't pick up gsudo or any other 'sudo' shim on PATH.
    $sudoExe = Join-Path $env:WINDIR "System32\sudo.exe"
    if (-not (Test-Path $sudoExe)) {
        Write-Info "Built-in sudo not present (requires Windows 11 24H2 or newer); skipping"
        return
    }

    try {
        & $sudoExe config --enable normal | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "sudo config --enable normal exited with code $LASTEXITCODE"
        }
        Write-Success "Windows Sudo enabled (mode: normal)"
    } catch {
        $errorMsg = "Failed to enable Windows Sudo: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "Windows Sudo" $errorMsg
    }
}

function Set-PowerToysKeepAwake {
    Write-Info "Configuring PowerToys Keep Awake..."

    try {
        $settingsDir = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\Keep Awake"
        $settingsFile = Join-Path $settingsDir "settings.json"

        if (-not (Test-Path $settingsDir)) {
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
        }

        # Read existing settings so we don't clobber unrelated keys
        $settings = $null
        if (Test-Path $settingsFile) {
            try { $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json } catch { $settings = $null }
        }

        if (-not $settings) {
            $settings = [PSCustomObject]@{
                version    = "1.0"
                name       = "KeepAwake"
                properties = [PSCustomObject]@{}
            }
        }

        if (-not $settings.properties) {
            $settings | Add-Member -NotePropertyName "properties" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }

        # keepawake_start_mode: 0 = off, 1 = indefinite, 2 = timed
        $settings.properties | Add-Member -NotePropertyName "keepawake_start_mode"   -NotePropertyValue ([PSCustomObject]@{ value = 1 })    -Force
        $settings.properties | Add-Member -NotePropertyName "keepawake_keep_screen_on" -NotePropertyValue ([PSCustomObject]@{ value = $true }) -Force

        $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsFile -Encoding UTF8
        Write-Success "PowerToys Keep Awake: indefinite mode, screen on"

    } catch {
        $errorMsg = "Failed to configure PowerToys Keep Awake: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "PowerToys Keep Awake" $errorMsg
    }
}

function Install-Agency {
    Write-Info "Installing Agency..."

    if (Get-Command agency -ErrorAction SilentlyContinue) {
        Write-Success "Agency is already installed"
        return
    }

    try {
        iex "& { $(irm aka.ms/InstallTool.ps1)} agency"
        Update-SessionPath | Out-Null
        Write-Success "Agency installed"
    } catch {
        $errorMsg = "Failed to install Agency: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "Agency" $errorMsg
    }
}

function Invoke-DevenvSubScript {
    # Convenience wrapper: resolve a path under Scripts\ and forward to Invoke-SubScript.
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [object[]]$ArgumentList = @(),
        [string]$Component
    )
    $scriptsRoot = Join-Path $PSScriptRoot ".."
    $full = Join-Path $scriptsRoot $RelativePath
    if (-not $Component) { $Component = (Split-Path $RelativePath -Leaf) }
    Invoke-SubScript -Path $full -ArgumentList $ArgumentList -Component $Component
}

function Main {
    Write-Host "Dev Environment Setup" -ForegroundColor Magenta
    Write-Host "=====================" -ForegroundColor Magenta
    Write-Host "Sub-script output -> $script:logFile" -ForegroundColor DarkGray

    try {
        # Admin-only foundation runs first: Defender exclusions before any installs
        # so they aren't scanned, then UAC/sudo so subsequent shells behave
        # correctly. Power + keep-alive only when -RemoteNode is set.
        Write-Section "Configuring System & Security Policies"
        Invoke-DevenvSubScript -RelativePath "Devenv/SetupDefenderExclusions.ps1" -Component "Defender Exclusions"
        Set-UacPolicy
        Enable-WindowsSudo
        if ($RemoteNode) {
            Invoke-DevenvSubScript -RelativePath "Devenv/SetupPowerManagement.ps1" -ArgumentList @("-Quiet") -Component "Power Management"
            Set-PowerToysKeepAwake
            Invoke-DevenvSubScript -RelativePath "Devenv/SetupKeepAlive.ps1" -Component "KeepAlive Task"
        } else {
            Write-Info "Skipping power/keep-alive configuration (use -RemoteNode to apply)"
        }

        Write-Section "Installing Package Managers"
        $scoopAvailable = Install-Scoop
        if ($scoopAvailable) {
            Add-ScoopShimsToPath
            Install-ScoopBuckets
        } else {
            Write-Info "Skipping Scoop buckets because Scoop is not available"
        }
        $wingetAvailable = Install-Winget

        Write-Section "Installing Development Tools"
        if ($scoopAvailable) {
            Install-ScoopPackages
        } else {
            Write-Info "Skipping Scoop packages because Scoop is not available"
        }
        if ($wingetAvailable) {
            Install-WingetPackages
            if ($FullSetup) {
                Install-DockerDesktop
            } else {
                Write-Info "Skipping Docker Desktop (pass -FullSetup to install)"
            }
        } else {
            Write-Info "Skipping winget packages because winget is not available"
        }
        Install-Python
        Install-NodeJS
        Install-ClaudeCode
        Install-Agency
        Install-NpmArtifactsCredProvider
        Remove-NpmCopilot
        Configure-Uv

        # PATH fix-ups for tools that don't surface through Scoop shims or
        # WinGet\Links. Single data-driven sweep -- new tools are one row in
        # Reconcile-ToolPaths' fixup table, not a new function.
        Write-Section "Reconciling Tool PATHs"
        Reconcile-ToolPaths

        Write-Section "Configuring Tools"
        Install-AzureCliExtensions
        Set-GitGlobalConfig
        Set-GitBashPathInheritance

        Write-Section "Setting Up Environment Variables"
        Set-EditorEnvironmentVariable
        Set-ReposEnvironmentVariable
        Set-DevRepoEnvironmentVariable
        Register-MergeOursDriver
        Register-TemplateRemote
        Invoke-DevenvSubScript -RelativePath "Devenv/SetupBuildThrottling.ps1" -Component "Build Throttling"

        Write-Section "Running Configuration Scripts"
        Invoke-DevenvSubScript -RelativePath "Devenv/SetupWindowsTerminal.ps1"
        Invoke-DevenvSubScript -RelativePath "Devenv/SetupBeyondCompare.ps1"
        Invoke-DevenvSubScript -RelativePath "Devenv/SetupClink.ps1"
        Invoke-DevenvSubScript -RelativePath "Agents/Run-Setup.ps1" -Component "Coding Agent CLI Preferences"
        Invoke-DevenvSubScript -RelativePath "Agents/Register-Marketplace.ps1" -Component "Plugin Marketplace"
        Invoke-DevenvSubScript -RelativePath "Maintenance/SetupRepoMaintenance.ps1"

        if ($ExplorerSettings) {
            Write-Section "Configuring Explorer"
            Set-DarkMode
            Set-TaskbarSearchBox
        } else {
            Write-Info "Skipping Explorer settings (use -ExplorerSettings to apply)"
        }

        Write-Section "Finalizing Environment"
        # Tell already-running shells, Windows Terminal, and Explorer to reload
        # their environment block so they see the new PATH without sign-out.
        Send-EnvironmentChangeBroadcast
        Write-PathLengthSummary

        Write-Section "Setup Complete"

        if ($script:errors.Count -eq 0) {
            Write-Success "Device setup completed successfully with no errors!"
        } else {
            Write-Host "`nSetup completed with $($script:errors.Count) error(s):" -ForegroundColor Yellow
            Write-Host ""
            foreach ($error in $script:errors) {
                Write-Host "  [$($error.Component)]" -ForegroundColor Red -NoNewline
                Write-Host " $($error.Message)" -ForegroundColor Gray
            }
            Write-Host ""
        }

        Write-Host "Sub-script log: $script:logFile" -ForegroundColor DarkGray

    } catch {
        Write-ErrorMsg "Setup failed: $($_.Exception.Message)"
        exit 1
    }
}

# Run the main function
Main
