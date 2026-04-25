# Loads posh-git, enables completion, sets prompt and PSReadLine options
# Works even if oh-my-posh is not installed

param(
    [string]$Theme = "json"
)

$ErrorActionPreference = 'SilentlyContinue'

# posh-git
Import-Module posh-git -Scope Global -Force

# Optional oh-my-posh if available
if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    # Try to add oh-my-posh to PATH if installed via winget
    $ohMyPoshPath = Join-Path $env:LOCALAPPDATA "Programs\oh-my-posh\bin"
    if (Test-Path $ohMyPoshPath) {
        $env:Path += ";$ohMyPoshPath"
    }
}

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    try {
        # Using oh-my-posh with configurable theme (requires Nerd Font in terminal)
        # Make sure terminal is configured to use CascadiaCode NF or FiraCode NF
        # Other good themes with Nerd Fonts: "powerlevel10k_rainbow", "agnoster", "night-owl", "paradox", "bubbles"
        $initScript = oh-my-posh init pwsh --config $Theme
        # Execute in global scope
        Invoke-Expression -Command $initScript
    } catch {
        Write-Host "[WARN] oh-my-posh failed to initialize: $_" -ForegroundColor Yellow
    }
} else {
    # Minimal prompt if oh-my-posh not available
    function Global:prompt {
        $loc = $(Get-Location)
        $git = ''
        if (Get-Command 'Get-GitBranch' -ErrorAction SilentlyContinue) {
            $b = Get-GitBranch
            if ($b) { $git = " [$($b)]" }
        } elseif (Get-Command 'git' -ErrorAction SilentlyContinue) {
            $b = git rev-parse --abbrev-ref HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $b) { $git = " [$b]" }
        }
        "PS $loc$git> "
    }
}

$ErrorActionPreference = 'Continue'
