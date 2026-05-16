function New-HVCheckpoint {
    <#
    .SYNOPSIS
        Creates a named checkpoint on a Hyper-V VM.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [string]$Name
    )
    process {
        Assert-HyperVAdmin
        if (-not $PSCmdlet.ShouldProcess($VMName, "Create checkpoint '$Name'")) { return }

        Write-HVLog "Creating checkpoint '$Name' on '$VMName'"
        $cp = Checkpoint-VM -VMName $VMName -SnapshotName $Name -Passthru -ErrorAction Stop

        # Checkpoint-VM can return before the WMI layer reflects the new entry.
        # Poll until Get-VMCheckpoint can find it so callers can trust it's queryable.
        $deadline = (Get-Date).AddSeconds(15)
        while (-not (Get-VMCheckpoint -VMName $VMName -Name $Name -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
        }

        Write-HVLog "Checkpoint '$Name' created."
        $cp
    }
}

function Remove-HVCheckpoint {
    <#
    .SYNOPSIS
        Removes a named checkpoint from a Hyper-V VM.
    .PARAMETER IncludeSubtree
        Also removes all child checkpoints.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$IncludeSubtree
    )
    process {
        Assert-HyperVAdmin
        $cp = Get-VMCheckpoint -VMName $VMName -Name $Name -ErrorAction Stop

        if (-not $PSCmdlet.ShouldProcess($VMName, "Remove checkpoint '$Name'")) { return }

        Write-HVLog "Removing checkpoint '$Name' on '$VMName'"
        if ($IncludeSubtree) {
            Remove-VMCheckpoint -VMCheckpoint $cp -IncludeAllChildSnapshots
        } else {
            Remove-VMCheckpoint -VMCheckpoint $cp
        }
        Write-HVLog "Checkpoint '$Name' removed."
    }
}

function Restore-HVCheckpoint {
    <#
    .SYNOPSIS
        Restores a named checkpoint on a Hyper-V VM, stopping the VM first if needed.
    .PARAMETER Start
        Start the VM after restoring the checkpoint.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$Start
    )
    process {
        Assert-HyperVAdmin
        $cp = Get-VMCheckpoint -VMName $VMName -Name $Name -ErrorAction Stop

        if (-not $PSCmdlet.ShouldProcess($VMName, "Restore checkpoint '$Name'")) { return }

        $vm = Get-VM -Name $VMName -ErrorAction Stop
        if ($vm.State -ne 'Off') {
            Write-HVLog "Stopping VM '$VMName' before checkpoint restore"
            Stop-VM -VMName $VMName -TurnOff -Force
        }

        Write-HVLog "Restoring checkpoint '$Name' on '$VMName'"
        Restore-VMCheckpoint -VMCheckpoint $cp -Confirm:$false

        # Hyper-V reorganizes the AVHD differencing chain after a restore. The WMI
        # layer needs a moment before checkpoint queries return consistent results.
        Start-Sleep -Seconds 2

        Write-HVLog "Checkpoint '$Name' restored."

        if ($Start) {
            Write-HVLog "Starting VM '$VMName' after restore"
            Start-VM -VMName $VMName
        }
    }
}
