<#
.SYNOPSIS
    Configures a new device with your preferred development environment setup.

.DESCRIPTION
    This script automates the setup of a new development device by:
    1. Installing Scoop and winget package managers if not present
    2. Installing essential development tools via Scoop and winget
    3. Installing Node.js and Python
    4. Running existing configuration scripts (SetupWindowsTerminal, etc.)
    5. Configuring environment variables and system policies

    The script gracefully handles already-installed components and can be run multiple times safely.

.PARAMETER ExplorerSettings
    Apply Windows Explorer settings (Dark Mode and Taskbar configuration). Skipped by default.

.PARAMETER FullSetup
    Install additional components like Docker Desktop that are skipped by default.

.EXAMPLE
    .\SetupDevice.ps1

.EXAMPLE
    .\SetupDevice.ps1 -ExplorerSettings

.EXAMPLE
    .\SetupDevice.ps1 -FullSetup

.NOTES
    Must be run from an elevated PowerShell session.

#>

param(
    [switch]$ExplorerSettings,
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

function Add-ErrorRecord {
    param([string]$Component, [string]$Message)
    $script:errors += @{
        Component = $Component
        Message = $Message
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

    $localBin = Join-Path $env:USERPROFILE ".local\bin"
    if ((Test-Path $localBin -ErrorAction SilentlyContinue) -and -not $current.ContainsKey($localBin.ToLowerInvariant())) {
        $pathsToAdd += $localBin
    }

    if ($pathsToAdd) {
        $env:Path = $env:Path + ";" + ($pathsToAdd -join ";")
        Write-Verbose "Added $($pathsToAdd.Count) path(s) to current session"
        return $pathsToAdd.Count
    }
    return 0
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
        
        # Call the ResetScoopBuckets script
        $resetScript = Join-Path $PSScriptRoot "ResetScoopBuckets.ps1"
        if (Test-Path $resetScript) {
            & pwsh.exe -ExecutionPolicy Bypass -File $resetScript
        } else {
            Write-ErrorMsg "ResetScoopBuckets.ps1 not found at: $resetScript"
        }
        
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
    winget install --id Docker.DockerDesktop --source winget --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null

    winget list --id Docker.DockerDesktop --exact --accept-source-agreements 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Installed Docker Desktop"
    } else {
        $errorMsg = "Docker Desktop installation could not be verified"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "Docker Desktop" $errorMsg
    }
}

function Disable-PythonAppExecutionAliases {
    Write-Info "Removing Python app execution aliases from WindowsApps..."

    # The python.exe/python3.exe stubs in WindowsApps are App Execution Aliases
    # shipped by DesktopAppInstaller (winget). They are 0-byte NTFS reparse points
    # that redirect to a "Python not found, install from Store" prompt.
    # Since we use uv-managed Python, these just cause confusion.
    # We can't uninstall DesktopAppInstaller (it provides winget), but we can
    # safely delete the alias files themselves.
    $storeAppsPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
    $aliases = @("python.exe", "python3.exe")

    foreach ($alias in $aliases) {
        $aliasPath = Join-Path $storeAppsPath $alias
        if (Test-Path $aliasPath) {
            try {
                Remove-Item $aliasPath -Force -ErrorAction Stop
                Write-Success "Removed app execution alias: $alias"
            } catch {
                Write-ErrorMsg "Could not remove ${alias}: $($_.Exception.Message)"
                Add-ErrorRecord "Python Aliases" "Failed to remove ${alias}: $($_.Exception.Message)"
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

    # Disable Windows Store Python aliases that interfere with uv-managed Python
    Disable-PythonAppExecutionAliases

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
        
        # Update PATH for current session
        Update-SessionPath | Out-Null

        # Ensure python.exe and python3.exe trampolines exist in ~/.local/bin
        # so bare "python" works for tools that don't use "uv run"
        $localBin = Join-Path $env:USERPROFILE ".local\bin"
        if (-not (Test-Path $localBin)) {
            New-Item -ItemType Directory -Path $localBin -Force | Out-Null
        }

        $trampoline = Get-ChildItem -Path $localBin -Filter "python3.*.exe" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if (-not $trampoline) {
            $uvPythonPath = uv python find 3.12.1 2>$null | Out-String
            $uvPythonPath = $uvPythonPath -replace '\s+', ''
            if ($uvPythonPath -and (Test-Path $uvPythonPath)) {
                $trampoline = Get-Item -Path $uvPythonPath
            } else {
                $uvPythonList = uv python list 2>&1 | Out-String
                if ($uvPythonList -match '([A-Za-z]:\\[^\r\n]*python\.exe)') {
                    $uvPythonPath = $Matches[1].Trim()
                    if (Test-Path $uvPythonPath) {
                        $trampoline = Get-Item -Path $uvPythonPath
                    }
                }
            }
        }

        if ($trampoline) {
            $pythonPath = $trampoline.FullName

            # Remove any stale Python executables from ~/.local/bin so the wrappers win.
            Get-ChildItem -Path $localBin -Filter "python*.exe" -File -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

            foreach ($name in @("python.cmd", "python3.cmd")) {
                $dest = Join-Path $localBin $name
                $wrapper = "@echo off`r`n"
                $wrapper += '"' + $pythonPath + '" %*'
                Set-Content -Path $dest -Value $wrapper -Encoding ASCII
                Write-Success "Created $name wrapper in ~/.local/bin"
            }

            foreach ($name in @("pip.cmd", "pip3.cmd")) {
                $dest = Join-Path $localBin $name
                $wrapper = "@echo off`r`n"
                $wrapper += '"' + $pythonPath + '" -m pip %*'
                Set-Content -Path $dest -Value $wrapper -Encoding ASCII
                Write-Success "Created $name wrapper in ~/.local/bin"
            }

            if ($env:Path -notlike "*$localBin*") {
                $env:Path = "$env:Path;$localBin"
            }
            Update-SessionPath | Out-Null
        } else {
            Write-Info "No local Python executable found to create trampolines in ~/.local/bin -- bare 'python' may not be on PATH"
        }

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
    
    if (-not (Get-Command nvm -ErrorAction SilentlyContinue)) {
        # nvm-windows installed via Scoop does not add itself to PATH automatically.
        # Explicitly register the nvm directory in User PATH and the current session.
        $nvmDir = Join-Path $env:USERPROFILE "scoop\apps\nvm\current"
        $nvmExe = Join-Path $nvmDir "nvm.exe"

        if (Test-Path $nvmExe) {
            Write-Info "nvm found at $nvmDir — adding to PATH"
            $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            if ($userPath -notlike "*$nvmDir*") {
                [Environment]::SetEnvironmentVariable("PATH", "$userPath;$nvmDir", "User")
            }
            $env:Path = "$env:Path;$nvmDir"
        } else {
            Write-ErrorMsg "nvm is not available. Please ensure it was installed correctly."
            Add-ErrorRecord "Node.js" "nvm not available"
            return
        }
    }
    
    try {
        $nvmList = nvm list 2>$null
        if ($nvmList -match "24\.0\.0") {
            Write-Success "Node.js 24.0.0 is already installed"
            nvm use 24.0.0
        } else {
            Write-Info "Installing Node.js 24.0.0..."
            nvm install 24.0.0
            nvm use 24.0.0
            Write-Success "Node.js 24.0.0 installed and activated"
        }
        
        # nvm-windows places node/npm in a symlink directory; ensure it is in PATH.
        # "nvm root" outputs "Current Root: <path>" so we strip the prefix.
        $nvmRootOutput = nvm root 2>$null | Out-String
        if ($nvmRootOutput -match 'Current Root:\s*(.+)') {
            $nvmRoot = $Matches[1].Trim()
            $nodeSymlink = Join-Path $nvmRoot "nodejs"
            if ((Test-Path $nodeSymlink) -and ($env:Path -notlike "*$nodeSymlink*")) {
                $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
                if ($userPath -notlike "*$nodeSymlink*") {
                    [Environment]::SetEnvironmentVariable("Path", "$userPath;$nodeSymlink", "User")
                }
                $env:Path = "$env:Path;$nodeSymlink"
            }
        }
        Update-SessionPath | Out-Null

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
"@

        Set-Content -Path $uvTomlPath -Value $tomlContent -Encoding UTF8
        Write-Success "Created uv configuration file: $uvTomlPath"
        Write-Success "Configured default PyPI index"
        
    } catch {
        $errorMsg = "Failed to configure uv: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "uv Configuration" $errorMsg
    }
}

function Install-ClaudeCode {
    Write-Info "Installing Claude Code CLI..."

    # The official installer drops the binary into %USERPROFILE%\.local\bin
    $claudeLocalBin = Join-Path $env:USERPROFILE ".local\bin"

    # Ensure the bin dir is in User PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$claudeLocalBin*") {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$claudeLocalBin", "User")
        Write-Success "Added $claudeLocalBin to User PATH"
    }
    if ($env:Path -notlike "*$claudeLocalBin*") {
        $env:Path = "$env:Path;$claudeLocalBin"
    }

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Success "Claude Code CLI is already installed"
        return
    }

    try {
        Write-Info "Running Claude Code official installer..."
        Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
        Write-Success "Claude Code CLI installed"
    } catch {
        $errorMsg = "Failed to install Claude Code CLI: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        Add-ErrorRecord "Claude Code" $errorMsg
    }
}

function Add-GitToPath {
    Write-Info "Checking for Git in PATH..."

    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Success "Git is already in PATH"
        return
    }

    # Git may have been installed via Scoop but shims not yet reflected in this session
    Update-SessionPath | Out-Null

    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Success "Git is now available in PATH"
        return
    }

    # Check common Git installation locations (Scoop shims, system installer)
    $possiblePaths = @(
        (Join-Path $env:USERPROFILE "scoop\shims"),
        "${env:ProgramFiles}\Git\cmd",
        "${env:ProgramFiles(x86)}\Git\cmd",
        "${env:LOCALAPPDATA}\Programs\Git\cmd"
    )

    foreach ($path in $possiblePaths) {
        $gitExe = Join-Path $path "git.exe"
        if (Test-Path $gitExe) {
            $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($currentPath -notlike "*$path*") {
                [Environment]::SetEnvironmentVariable("Path", "$currentPath;$path", "User")
            }
            $env:Path = "$env:Path;$path"

            if (Get-Command git -ErrorAction SilentlyContinue) {
                Write-Success "Added Git to PATH: $path"
                return
            }
        }
    }

    $errorMsg = "Git not found in PATH or common locations - it may require a terminal restart"
    Write-Info $errorMsg
    Add-ErrorRecord "Git PATH" $errorMsg
}

function Ensure-LocalBinOnUserPath {
    $localBin = Join-Path $env:USERPROFILE ".local\bin"

    if (-not (Test-Path $localBin)) {
        try {
            New-Item -ItemType Directory -Path $localBin -Force | Out-Null
            Write-Success "Created directory: $localBin"
        } catch {
            Write-ErrorMsg "Failed to create ${localBin}: $($_.Exception.Message)"
            Add-ErrorRecord "PATH" "Failed to create ${localBin}: $($_.Exception.Message)"
            return
        }
    }

    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $normalized = $currentUserPath -split ';' | ForEach-Object { $_.TrimEnd('\').Trim() } | Where-Object { $_ }
    if ($normalized -contains $localBin) {
        Write-Success "$localBin is already in User PATH"
    } else {
        if ($currentUserPath) {
            [Environment]::SetEnvironmentVariable("Path", "$currentUserPath;$localBin", "User")
        } else {
            [Environment]::SetEnvironmentVariable("Path", $localBin, "User")
        }
        Write-Success "Added $localBin to User PATH"
    }

    if ($env:Path -notlike "*$localBin*") {
        $env:Path = "$env:Path;$localBin"
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

function Run-SetupScripts {
    Write-Info "Running configuration scripts..."

    $scriptsPath = Join-Path $PSScriptRoot ".."

    $setupScripts = @(
        "Devenv/SetupCLink.ps1",
        "Devenv/SetupWindowsTerminal.ps1",
        "Maintenance/SetupRepoMaintenance.ps1"
    )

    foreach ($script in $setupScripts) {
        $scriptPath = Join-Path $scriptsPath $script
        if (-not (Test-Path $scriptPath)) {
            Write-Info "$script not found, skipping"
            continue
        }
        try {
            Write-Info "Running $script..."
            & $scriptPath
            Write-Success "$script completed"
        } catch {
            $errorMsg = "$script failed: $($_.Exception.Message)"
            Write-ErrorMsg $errorMsg
            Add-ErrorRecord "Setup Scripts" $errorMsg
        }
    }
}

function Confirm-ToolsOnPath {
    Write-Info "Verifying essential tools are on PATH..."

    # Final refresh to pick up anything registered by earlier steps
    Update-SessionPath | Out-Null

    $tools = @(
        @{ Name = "python";   Label = "Python" },
        @{ Name = "uv";       Label = "uv" },
        @{ Name = "nvm";      Label = "nvm" },
        @{ Name = "node";     Label = "Node.js" },
        @{ Name = "npm";      Label = "npm" },
        @{ Name = "git";      Label = "Git" },
        @{ Name = "gh";       Label = "GitHub CLI" },
        @{ Name = "opencode"; Label = "OpenCode CLI" },
        @{ Name = "claude";   Label = "Claude Code CLI" }
    )

    foreach ($tool in $tools) {
        if (Get-Command $tool.Name -ErrorAction SilentlyContinue) {
            Write-Success "$($tool.Label) ($($tool.Name)) is on PATH"
        } else {
            $errorMsg = "$($tool.Label) ($($tool.Name)) is NOT on PATH -- may need a terminal restart"
            Write-ErrorMsg $errorMsg
            Add-ErrorRecord "PATH Check" $errorMsg
        }
    }
}

function Main {
    Write-Host "Dev Environment Setup" -ForegroundColor Magenta
    Write-Host "=====================" -ForegroundColor Magenta

    # Ensure ~/.local/bin is permanently in the User PATH and available in this session.
    Ensure-LocalBinOnUserPath
    Update-SessionPath | Out-Null

    try {
        # Install package managers
        Write-Section "Installing Package Managers"
        $scoopAvailable = Install-Scoop
        if ($scoopAvailable) {
            Install-ScoopBuckets
        } else {
            Write-Info "Skipping Scoop buckets because Scoop is not available"
        }
        $wingetAvailable = Install-Winget

        # Install development tools
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

        Configure-Uv

        # Configure development environment
        Write-Section "Configuring Development Environment"
        Add-GitToPath
        Set-GitGlobalConfig

        # Set up environment variables
        Write-Section "Setting Up Environment Variables"
        Set-EditorEnvironmentVariable
        Set-ReposEnvironmentVariable
        Set-DevRepoEnvironmentVariable

        # System policy settings
        Write-Section "Configuring System Policies"
        Set-UacPolicy
        Enable-WindowsSudo

        # Enable Dark Mode and Configure Taskbar (opt-in)
        if ($ExplorerSettings) {
            Write-Section "Enabling Dark Mode"
            Set-DarkMode

            Write-Section "Configuring Taskbar"
            Set-TaskbarSearchBox
        } else {
            Write-Info "Skipping Explorer settings (use -ExplorerSettings to apply)"
        }

        # Run existing configuration scripts (all)
        Write-Section "Running Configuration Scripts"
        Run-SetupScripts

        # Verify all essential tools are reachable
        Write-Section "Verifying Tools on PATH"
        Confirm-ToolsOnPath

        Write-Section "Setup Complete"

        # Display summary
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

    } catch {
        Write-ErrorMsg "Setup failed: $($_.Exception.Message)"
        exit 1
    }
}

# Run the main function
Main
