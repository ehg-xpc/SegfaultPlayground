function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 5,

        # Return $true to retry, $false to rethrow immediately.
        [scriptblock]$ShouldRetry = { $true }
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxAttempts) {
        $attempt++
        try {
            return (& $ScriptBlock)
        } catch {
            $lastError = $_
            if ($attempt -lt $MaxAttempts -and (& $ShouldRetry $_)) {
                Write-Verbose "Attempt $attempt/$MaxAttempts failed: $($_.Exception.Message). Retrying in ${DelaySeconds}s..."
                Start-Sleep -Seconds $DelaySeconds
            } else {
                break
            }
        }
    }

    throw $lastError
}
