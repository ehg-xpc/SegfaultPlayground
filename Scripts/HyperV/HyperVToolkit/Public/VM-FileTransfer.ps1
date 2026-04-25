function Copy-FileToVM {
    <#
    .SYNOPSIS
        Copies a file or directory from the Hyper-V host to a VM using PowerShell Direct.
    .PARAMETER VMName
        Name of the target VM.
    .PARAMETER Session
        An open PSSession to the VM (from New-HVSession).
    .PARAMETER HostPath
        Local path on the host to copy from.
    .PARAMETER VMPath
        Destination path inside the VM.
    .PARAMETER Recurse
        Copy directories recursively.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.PSSession]$Session,

        [Parameter(Mandatory)]
        [string]$HostPath,

        [Parameter(Mandatory)]
        [string]$VMPath,

        [switch]$Recurse
    )

    if (-not (Test-Path $HostPath)) { throw "Host path not found: $HostPath" }
    if (-not $PSCmdlet.ShouldProcess($VMName, "Copy '$HostPath' -> '$VMPath'")) { return }

    Write-HVLog "Copying '$HostPath' -> VM '$VMName':'$VMPath'"

    # Ensure destination directory exists on the VM
    $destDir = Split-Path $VMPath -Parent
    Invoke-Command -Session $Session -ArgumentList $destDir -ScriptBlock {
        param($dir)
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    $copyArgs = @{
        Path        = $HostPath
        Destination = $VMPath
        ToSession   = $Session
        Force       = $true
    }
    if ($Recurse) { $copyArgs['Recurse'] = $true }

    Copy-Item @copyArgs -ErrorAction Stop
    Write-HVLog "Copy to VM complete."
}

function Copy-FileFromVM {
    <#
    .SYNOPSIS
        Copies a file or directory from a VM to the Hyper-V host using PowerShell Direct.
    .PARAMETER VMName
        Name of the source VM.
    .PARAMETER Session
        An open PSSession to the VM (from New-HVSession).
    .PARAMETER VMPath
        Path inside the VM to copy from.
    .PARAMETER HostPath
        Destination path on the host.
    .PARAMETER Recurse
        Copy directories recursively.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.PSSession]$Session,

        [Parameter(Mandatory)]
        [string]$VMPath,

        [Parameter(Mandatory)]
        [string]$HostPath,

        [switch]$Recurse
    )

    if (-not $PSCmdlet.ShouldProcess($VMName, "Copy '$VMPath' -> '$HostPath'")) { return }

    Write-HVLog "Copying VM '$VMName':'$VMPath' -> '$HostPath'"

    # Ensure local destination directory exists
    $ext     = [System.IO.Path]::GetExtension($HostPath)
    $destDir = if ($ext) { Split-Path $HostPath -Parent } else { $HostPath }
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $copyArgs = @{
        Path        = $VMPath
        Destination = $HostPath
        FromSession = $Session
        Force       = $true
    }
    if ($Recurse) { $copyArgs['Recurse'] = $true }

    Copy-Item @copyArgs -ErrorAction Stop
    Write-HVLog "Copy from VM complete."
}
