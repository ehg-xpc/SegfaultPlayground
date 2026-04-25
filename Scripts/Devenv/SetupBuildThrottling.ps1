<#
.SYNOPSIS
    Configures build throttling environment variables to limit CPU usage during builds.

.DESCRIPTION
    Sets CL_MPCount and NUMBER_OF_PROCESSORS as permanent (User-level) environment variables
    to prevent builds from saturating all cores.
#>

$ErrorActionPreference = "Stop"

# Import shared helpers if running standalone
if (-not (Get-Command Write-Info -ErrorAction SilentlyContinue)) {
    function Write-Info  { param([string]$msg) Write-Host "  [INFO] $msg" -ForegroundColor Cyan }
    function Write-Success { param([string]$msg) Write-Host "  [OK]   $msg" -ForegroundColor Green }
    function Write-ErrorMsg { param([string]$msg) Write-Host "  [ERR]  $msg" -ForegroundColor Red }
}

$vars = @{
    CL_MPCount           = "8"
    NUMBER_OF_PROCESSORS = "4"
}

foreach ($name in $vars.Keys) {
    $desired = $vars[$name]
    try {
        $current = [Environment]::GetEnvironmentVariable($name, "User")
        if ($current -ne $desired) {
            [Environment]::SetEnvironmentVariable($name, $desired, "User")
            Set-Item "env:$name" $desired
            Write-Success "$name set to: $desired"
        } else {
            Write-Success "$name already set correctly to: $desired"
        }
    } catch {
        $errorMsg = "Failed to set ${name}: $($_.Exception.Message)"
        Write-ErrorMsg $errorMsg
        if (Get-Command Add-ErrorRecord -ErrorAction SilentlyContinue) {
            Add-ErrorRecord "Build Throttling" $errorMsg
        }
    }
}
