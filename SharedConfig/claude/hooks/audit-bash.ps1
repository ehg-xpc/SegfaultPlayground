# PostToolUse hook for Bash -- appends a one-line JSONL entry to a daily audit log.
# Provides a queryable record of every command the agent ran and its exit code.
param()

$payload = $input | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $payload) { exit 0 }

$command  = $payload.tool_input.command  -replace "`n", " "
$exitCode = $payload.tool_response.exitCode
$logDir   = Join-Path $env:USERPROFILE ".claude\audit"
$logFile  = Join-Path $logDir ("bash-" + (Get-Date -Format "yyyy-MM-dd") + ".jsonl")

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$entry = [ordered]@{
    ts       = (Get-Date -Format "o")
    exit     = $exitCode
    cmd      = $command
}

$entry | ConvertTo-Json -Compress | Add-Content -Path $logFile -Encoding UTF8
