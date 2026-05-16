function Write-HVLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Verbose')]
        [string]$Level = 'Info'
    )
    process {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line = "[$timestamp] [HyperV] $Message"

        switch ($Level) {
            'Warning' { Write-Warning $Message }
            'Error'   { Write-Error $Message }
            'Verbose' { Write-Verbose $line }
            default   { Write-Host $line }
        }
    }
}
