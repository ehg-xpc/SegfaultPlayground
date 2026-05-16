function Start-HVMachine {
    <#
    .SYNOPSIS
        Starts a Hyper-V VM.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name
    )
    process {
        Assert-HyperVAdmin
        $vm = Get-VM -Name $Name -ErrorAction Stop

        if ($vm.State -eq 'Running') {
            Write-HVLog "VM '$Name' is already running."
            return
        }

        if (-not $PSCmdlet.ShouldProcess($Name, 'Start VM')) { return }

        Write-HVLog "Starting VM '$Name'"
        Start-VM -VM $vm -ErrorAction Stop
        Write-HVLog "VM '$Name' started."
    }
}

function Stop-HVMachine {
    <#
    .SYNOPSIS
        Stops a Hyper-V VM gracefully or by force.
    .PARAMETER Force
        Skip graceful shutdown and cut power (equivalent to pulling the plug).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [switch]$Force
    )
    process {
        Assert-HyperVAdmin
        $vm = Get-VM -Name $Name -ErrorAction Stop

        if ($vm.State -eq 'Off') {
            Write-HVLog "VM '$Name' is already off."
            return
        }

        $action = if ($Force) { 'Force-stop VM' } else { 'Gracefully stop VM' }
        if (-not $PSCmdlet.ShouldProcess($Name, $action)) { return }

        Write-HVLog "Stopping VM '$Name' (Force=$Force)"
        Stop-VM -VM $vm -TurnOff:$Force -Force
        Write-HVLog "VM '$Name' stopped."
    }
}

function Wait-HVReady {
    <#
    .SYNOPSIS
        Polls a VM via PowerShell Direct until it accepts connections or times out.
    .OUTPUTS
        $true when the VM is ready.
        Throws on timeout.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [pscredential]$Credential,

        [int]$TimeoutSeconds = 180,

        [int]$PollIntervalSeconds = 5
    )

    Write-HVLog "Waiting for VM '$VMName' to be ready (timeout: ${TimeoutSeconds}s)"

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt  = 0

    while ((Get-Date) -lt $deadline) {
        $attempt++
        try {
            $ok = Invoke-Command -VMName $VMName -Credential $Credential `
                -ScriptBlock { $true } -ErrorAction Stop
            if ($ok) {
                Write-HVLog "VM '$VMName' is ready (attempt $attempt)."
                return $true
            }
        } catch {
            Write-Verbose "[Wait-HVReady] attempt ${attempt}: $($_.Exception.Message)"
            Start-Sleep -Seconds $PollIntervalSeconds
        }
    }

    throw "Timed out waiting for VM '$VMName' to become ready after ${TimeoutSeconds} seconds."
}
