# Manage-Repository.ps1 - Ensures repository exists and outputs the path
param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryName
)

# Set default config path
$ConfigPath = Join-Path $PSScriptRoot "RepositoryConfig.json"

# Load repository configuration
$RepositoryMap = @{}
$BaseReposPath = $env:Repos

if (Test-Path $ConfigPath) {
    try {
        $config = Get-Content $ConfigPath | ConvertFrom-Json
        foreach ($repo in $config.repositories.PSObject.Properties) {
            $RepositoryMap[$repo.Name] = @{
                url = $repo.Value.url
                folderName = $repo.Value.folderName ?? $repo.Name
            }
        }
        if ($config.baseReposPath) {
            $BaseReposPath = [Environment]::ExpandEnvironmentVariables($config.baseReposPath)
        }
    }
    catch {
        # Silent failure - just exit with error
        exit 1
    }
} else {
    # Config file not found
    exit 1
}

# Check if repository is configured
if (-not $RepositoryMap.ContainsKey($RepositoryName)) {
    exit 1
}

$repoConfig = $RepositoryMap[$RepositoryName]
$repoUrl = $repoConfig.url
$folderName = $repoConfig.folderName
$repoPath = Join-Path $BaseReposPath $folderName

# Handle local-only directories (null URL)
if (-not $repoUrl -or $repoUrl -eq "null") {
    if (-not (Test-Path $repoPath)) {
        New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
    }
    Write-Output $repoPath
    exit 0
}

# Handle git repositories
if (Test-Path $repoPath) {
    if (Test-Path (Join-Path $repoPath ".git")) {
        Write-Output $repoPath
        exit 0
    } else {
        # Directory exists but is not a git repository
        exit 1
    }
}

# Repository doesn't exist - clone it
$parentPath = Split-Path $repoPath -Parent
if (-not (Test-Path $parentPath)) {
    New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
}

Push-Location $parentPath
try {
    $finalFolderName = Split-Path $folderName -Leaf
    git clone $repoUrl $finalFolderName | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Output $repoPath
        exit 0
    } else {
        exit 1
    }
}
finally {
    Pop-Location
}