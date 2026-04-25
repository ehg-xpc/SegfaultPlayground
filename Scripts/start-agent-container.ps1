# start-agent-container.ps1 - Launch a Claude Code agent container for a Stanley worktree
#
# Usage:
#   .\start-agent-container.ps1 <slug>
#   .\start-agent-container.ps1 <project>/<slug>
#   .\start-agent-container.ps1 C:\\.worktrees\\MyRepo\\my-branch
#
# Launches claude --dangerously-skip-permissions inside the ado-agent container
# with the resolved worktree mounted at /worktree, task queue at /tasks,
# and shared agent context at /context (read-only).
#
# PAT resolution order:
#   1. $env:AZDO_PAT
#   2. ~/.stanley/agent-container.env  (AZDO_PAT=<token>)
#   3. Fail loudly

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory)]
    [string]$Target,

    [string]$Project,
    [string]$Image = 'ado-agent'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) { Write-Host "[agent-container] $msg" -ForegroundColor Cyan }
function Fail([string]$msg)       { Write-Error "[agent-container] $msg"; exit 1 }

# --------------------------------------------------------------------------
# Worktree roots (Stanley uses both depending on path length)
# --------------------------------------------------------------------------
$ShortRoot   = 'C:\.worktrees'
$DefaultRoot = Join-Path $env:USERPROFILE '.stanley\worktrees'

function Find-Worktree([string]$project, [string]$slug) {
    foreach ($root in @($ShortRoot, $DefaultRoot)) {
        $candidate = Join-Path $root "$project\$slug"
        if (Test-Path $candidate -PathType Container) { return $candidate }
    }
    return $null
}

function Search-AllProjects([string]$slug) {
    $results = @()
    foreach ($root in @($ShortRoot, $DefaultRoot)) {
        if (-not (Test-Path $root -PathType Container)) { continue }
        foreach ($projectDir in Get-ChildItem $root -Directory -ErrorAction SilentlyContinue) {
            $candidate = Join-Path $projectDir.FullName $slug
            if (Test-Path $candidate -PathType Container) {
                $results += [PSCustomObject]@{ Path = $candidate; Project = $projectDir.Name }
            }
        }
    }
    return $results
}

# --------------------------------------------------------------------------
# Resolve worktree path and project name
# --------------------------------------------------------------------------
$worktreePath = $null
$projectName  = $Project

Write-Step "Resolving worktree: $Target"

if ([System.IO.Path]::IsPathRooted($Target)) {
    # Full path supplied directly
    if (-not (Test-Path $Target -PathType Container)) {
        Fail "Path does not exist: $Target"
    }
    $worktreePath = $Target
    if (-not $projectName) {
        $projectName = Split-Path (Split-Path $Target -Parent) -Leaf
    }
} elseif ($Target -match '^([^/\\]+)[/\\]([^/\\]+)$') {
    # project/slug form
    $inferredProject = $Matches[1]
    $slug            = $Matches[2]
    if (-not $projectName) { $projectName = $inferredProject }
    $worktreePath = Find-Worktree -project $projectName -slug $slug
    if (-not $worktreePath) {
        Fail "Worktree not found for ${projectName}/${slug}`n  Searched:`n    $ShortRoot\$projectName\$slug`n    $DefaultRoot\$projectName\$slug"
    }
} else {
    # Bare slug — search all projects under both roots
    $slug    = $Target
    $results = @(Search-AllProjects -slug $slug)
    if ($results.Count -eq 0) {
        Fail "No worktree found for slug '$slug'`n  Searched under: $ShortRoot, $DefaultRoot"
    }
    if ($results.Count -gt 1) {
        $list = ($results | ForEach-Object { "  $($_.Project)/$slug  ($($_.Path))" }) -join "`n"
        Fail "Ambiguous: slug '$slug' found in multiple projects:`n$list`n  Use <project>/<slug> to disambiguate."
    }
    $worktreePath = $results[0].Path
    if (-not $projectName) { $projectName = $results[0].Project }
}

Write-Step "Worktree:  $worktreePath"
Write-Step "Project:   $projectName"

# --------------------------------------------------------------------------
# Resolve PAT
# --------------------------------------------------------------------------
$pat = $env:AZDO_PAT

if (-not $pat) {
    $envFile = Join-Path $env:USERPROFILE '.stanley\agent-container.env'
    if (Test-Path $envFile) {
        foreach ($line in Get-Content $envFile) {
            if ($line -match '^\s*AZDO_PAT\s*=\s*(.+)$') {
                $pat = $Matches[1].Trim()
                break
            }
        }
    }
}

if (-not $pat) {
    Fail "AZDO_PAT not set.`n  Option 1: `$env:AZDO_PAT = '<token>'`n  Option 2: add AZDO_PAT=<token> to $env:USERPROFILE\.stanley\agent-container.env"
}

Write-Step "PAT:       [resolved]"

# --------------------------------------------------------------------------
# Resolve and validate mount paths
# --------------------------------------------------------------------------
$tasksPath      = Join-Path $env:USERPROFILE ".stanley\tasks\$projectName"
$contextPath    = Join-Path $env:USERPROFILE ".stanley\shared\$projectName"
$claudePath     = Join-Path $env:USERPROFILE ".claude"
$claudeJsonPath = Join-Path $env:USERPROFILE ".claude.json"

if (-not (Test-Path $tasksPath -PathType Container)) {
    Fail "Tasks directory not found: $tasksPath"
}
if (-not (Test-Path $contextPath -PathType Container)) {
    Fail "Shared context not found: $contextPath"
}
if (-not (Test-Path $claudePath -PathType Container)) {
    Fail "Claude config directory not found: $claudePath"
}
if (-not (Test-Path $claudeJsonPath -PathType Leaf)) {
    Fail "Claude config file not found: $claudeJsonPath"
}

# Docker Desktop on Windows requires forward slashes in volume paths
function ConvertTo-DockerPath([string]$p) { $p.Replace('\', '/') }

$dockerWorktree   = ConvertTo-DockerPath $worktreePath
$dockerTasks      = ConvertTo-DockerPath $tasksPath
$dockerContext    = ConvertTo-DockerPath $contextPath
$dockerClaude     = ConvertTo-DockerPath $claudePath
$dockerClaudeJson = ConvertTo-DockerPath $claudeJsonPath

# --------------------------------------------------------------------------
# Launch container
# --------------------------------------------------------------------------
Write-Step "Image:     $Image"
Write-Step "Mounts:"
Write-Host "             /worktree                        <- $worktreePath"   -ForegroundColor DarkGray
Write-Host "             /tasks                           <- $tasksPath"      -ForegroundColor DarkGray
Write-Host "             /context                         <- $contextPath"    -ForegroundColor DarkGray
Write-Host "             /home/agent/.claude              <- $claudePath"     -ForegroundColor DarkGray
Write-Host "             /home/agent/.claude/.claude.json <- $claudeJsonPath" -ForegroundColor DarkGray
Write-Host ""

docker run --rm -it `
    --cap-add=NET_ADMIN `
    --cap-add=NET_RAW `
    -e "AZDO_PAT=$pat" `
    -v "${dockerWorktree}:/worktree" `
    -v "${dockerTasks}:/tasks" `
    -v "${dockerContext}:/context:ro" `
    -v "${dockerClaude}:/home/agent/.claude" `
    -v "${dockerClaudeJson}:/home/agent/.claude/.claude.json" `
    -w /worktree `
    $Image `
    claude --dangerously-skip-permissions
