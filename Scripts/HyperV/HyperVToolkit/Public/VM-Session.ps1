function New-HVSession {
    <#
    .SYNOPSIS
        Opens a PowerShell Direct session to a Hyper-V VM.
    .DESCRIPTION
        Uses the Hyper-V hypervisor bus (no network required). The VM must be running
        and the guest must support PowerShell remoting (Windows 8.1 / 2012 R2 or later).
    .PARAMETER VMName
        Name of the target VM.
    .PARAMETER Credential
        Guest credentials. Use Resolve-VMCredential to build from config.
    .PARAMETER RetryCount
        Number of connection attempts before failing. Default: 3.
    .OUTPUTS
        System.Management.Automation.Runspaces.PSSession
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Runspaces.PSSession])]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [pscredential]$Credential,

        [int]$RetryCount = 3,
        [int]$RetryDelaySeconds = 5
    )

    Write-HVLog "Opening PowerShell Direct session to VM '$VMName'"

    $session = Invoke-WithRetry -MaxAttempts $RetryCount -DelaySeconds $RetryDelaySeconds -ScriptBlock {
        New-PSSession -VMName $VMName -Credential $Credential -ErrorAction Stop
    }

    Write-HVLog "Session established to '$VMName' (Id=$($session.Id))."
    $session
}

function Remove-HVSession {
    <#
    .SYNOPSIS
        Closes a PowerShell Direct session opened with New-HVSession.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [System.Management.Automation.Runspaces.PSSession]$Session
    )
    process {
        if ($null -ne $Session -and $Session.State -ne 'Closed') {
            Write-HVLog "Closing session (Id=$($Session.Id))"
            Remove-PSSession -Session $Session -ErrorAction SilentlyContinue
        }
    }
}

function Resolve-VMCredential {
    <#
    .SYNOPSIS
        Builds a PSCredential from a config object's guestCredential section.
    .DESCRIPTION
        Reads the password from the environment variable named by
        passwordSecretEnvVar, or falls back to an interactive Get-Credential prompt.
    .PARAMETER CredentialConfig
        PSCustomObject with 'username' and optionally 'passwordSecretEnvVar'.
    .OUTPUTS
        System.Management.Automation.PSCredential
    #>
    [CmdletBinding()]
    [OutputType([pscredential])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$CredentialConfig
    )

    $username = $CredentialConfig.username

    if ($CredentialConfig.passwordSecretEnvVar) {
        $envValue = [System.Environment]::GetEnvironmentVariable($CredentialConfig.passwordSecretEnvVar)
        if (-not $envValue) {
            throw "Environment variable '$($CredentialConfig.passwordSecretEnvVar)' is not set or is empty."
        }
        $securePass = ConvertTo-SecureString $envValue -AsPlainText -Force
        return [pscredential]::new($username, $securePass)
    }

    Get-Credential -UserName $username -Message "Enter password for VM user '$username'"
}
