# Setup Clink with custom prompt
$clinkScriptsDir = Join-Path $env:LOCALAPPDATA "clink"
$promptScript = Join-Path $PSScriptRoot "clink-prompt.lua"
$targetScript = Join-Path $clinkScriptsDir "clink-prompt.lua"

# Ensure clink scripts directory exists
if (-not (Test-Path $clinkScriptsDir)) {
    New-Item -ItemType Directory -Path $clinkScriptsDir -Force | Out-Null
    Write-Host "Created clink scripts directory: $clinkScriptsDir"
}

# Copy or update the prompt script
if (Test-Path $promptScript) {
    Copy-Item -Path $promptScript -Destination $targetScript -Force
    Write-Host "Clink prompt script installed: $targetScript"
} else {
    Write-Warning "Prompt script not found at: $promptScript"
}

Write-Host "Clink setup complete. Restart any cmd sessions to see the new prompt."
