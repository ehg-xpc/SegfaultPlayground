param(
    [Parameter(Mandatory = $false)]
    [string]$RepositoryName,
    
    [Parameter(Mandatory = $false)]
    [string]$Theme
)

Clear-Host

$ScriptsFolder = Resolve-Path (Join-Path $PSScriptRoot "..")
$DevFolder = Split-Path $ScriptsFolder -Parent

$RepoScriptsPath = $null

# Handle repository setup if repository name is provided
if ($RepositoryName) {
    $manageRepoScript = Join-Path $PSScriptRoot "ManageRepository.ps1"
    
    if (Test-Path $manageRepoScript) {
        # Call the shared repository management script - it returns just the path
        $repoPath = & $manageRepoScript -RepositoryName $RepositoryName
        
        if ($LASTEXITCODE -eq 0 -and $repoPath -and (Test-Path $repoPath)) {
            Set-Location $repoPath

            # Check for repo-specific scripts folder (convention: Scripts\Repos\{RepositoryName})
            $RepoScriptsPath = Join-Path $ScriptsFolder "Repos\$RepositoryName"
            if (-not (Test-Path $RepoScriptsPath)) {
                $RepoScriptsPath = $null
            }
        } else {
            Write-Host "Failed to setup repository '$RepositoryName'. Continuing with basic environment setup..." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Error: Repository management script not found. Continuing with basic environment setup..." -ForegroundColor Yellow
    }
}

$RootFolder = Get-Location

# Display banner
$showBannerScript = Join-Path $PSScriptRoot "ShowBanner.ps1"
if (Test-Path $showBannerScript) {
    . $showBannerScript
}

# Log repository info and inject agent context (after banner)
if ($RepositoryName -and $repoPath -and (Test-Path $repoPath)) {
    Write-Host "Repository: $RepositoryName" -ForegroundColor Green
    if ($RepoScriptsPath) {
        Write-Host "Scripts: Repos\$RepositoryName" -ForegroundColor Cyan
    }

    $agentContextScript = Join-Path $PSScriptRoot "SetupSharedAgentContext.ps1"
    if (Test-Path $agentContextScript) {
        & $agentContextScript -RepoName $RepositoryName -RepoPath $repoPath
    }

    Write-Host ""
}

# Set aliases
function Global:self { Set-Location $DevFolder }
function Global:scripts { Set-Location $ScriptsFolder }
function Global:root { Set-Location $RootFolder }
function Global:devsetup { & "$ScriptsFolder\devsetup.cmd" }

# Build PATH
$pathsToAdd = @(
    $ScriptsFolder,
    (Join-Path $DevFolder "Tools")
)

# Add repo-specific scripts path if defined
if ($RepoScriptsPath) {
    $pathsToAdd = @($RepoScriptsPath) + $pathsToAdd
}

# Add paths to environment
foreach ($path in $pathsToAdd) {
    if ($path -and (Test-Path $path)) {
        if ($env:PATH -notlike "*$path*") {
            $env:PATH = "$path;$env:PATH"
        }
    }
}

# Setup PowerShell prompt
$setupPromptScript = Join-Path $ScriptsFolder "Devenv\SetupPrompt.ps1"
if (Test-Path $setupPromptScript) {
    if ($Theme) {
        . $setupPromptScript -Theme $Theme
    } else {
        . $setupPromptScript
    }
}

# Reset console colors to prevent color bleeding from prompt setup
[Console]::ResetColor()
