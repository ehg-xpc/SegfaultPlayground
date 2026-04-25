function Get-HVMachine {
    <#
    .SYNOPSIS
        Lists Hyper-V VMs, optionally filtered by name pattern.
    .PARAMETER Name
        VM name or wildcard. Defaults to all VMs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [SupportsWildcards()]
        [string]$Name = '*'
    )
    process {
        Get-VM -Name $Name -ErrorAction SilentlyContinue
    }
}

function New-HVMachine {
    <#
    .SYNOPSIS
        Creates a Hyper-V VM from a config object or JSON file.
    .PARAMETER Config
        PSCustomObject (or hashtable) matching the VM config schema.
        Required: name, type (templateClone|freshISO), generation, memorySizeMB,
                  processorCount, vhdSizeGB, switchName.
        templateClone also requires: templateVHDPath
        freshISO also requires: isoPath
    .PARAMETER ConfigPath
        Path to a JSON file. Mutually exclusive with -Config.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Object')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Object', ValueFromPipeline)]
        [object]$Config,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$ConfigPath
    )
    process {
        Assert-HyperVAdmin

        if ($PSCmdlet.ParameterSetName -eq 'File') {
            $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        }

        $name = $Config.name
        if (-not $PSCmdlet.ShouldProcess($name, 'Create Hyper-V VM')) { return }

        Write-HVLog "Creating VM '$name' (type=$($Config.type), gen=$($Config.generation))"

        # Resolve destination VHD path
        $vhdDir = if ($Config.vhdDirectory) {
            $Config.vhdDirectory
        } else {
            (Get-VMHost).VirtualHardDiskPath
        }
        $vhdPath = Join-Path $vhdDir "$name.vhdx"

        switch ($Config.type) {
            'templateClone' {
                if (-not $Config.templateVHDPath) {
                    throw "templateVHDPath is required when type='templateClone'"
                }
                if ($Config.differencing) {
                    Write-HVLog "Creating differencing disk from '$($Config.templateVHDPath)'"
                    New-VHD -Path $vhdPath -ParentPath $Config.templateVHDPath -Differencing -ErrorAction Stop | Out-Null
                } else {
                    Write-HVLog "Cloning template VHD from '$($Config.templateVHDPath)'"
                    Copy-Item -Path $Config.templateVHDPath -Destination $vhdPath -ErrorAction Stop
                }
            }
            'freshISO' {
                if (-not $Config.isoPath) {
                    throw "isoPath is required when type='freshISO'"
                }
                $sizeBytes = [long]($Config.vhdSizeGB) * 1GB
                Write-HVLog "Creating new dynamic VHD ($($Config.vhdSizeGB) GB)"
                New-VHD -Path $vhdPath -SizeBytes $sizeBytes -Dynamic -ErrorAction Stop | Out-Null
            }
            default { throw "Unknown VM type '$($Config.type)'. Use 'templateClone' or 'freshISO'." }
        }

        $memBytes   = [long]($Config.memorySizeMB) * 1MB
        $switchName = if ($Config.switchName) { $Config.switchName } else { 'Default Switch' }

        $vm = New-VM -Name $name -Generation ([int]$Config.generation) `
            -MemoryStartupBytes $memBytes -VHDPath $vhdPath `
            -SwitchName $switchName -ErrorAction Stop

        Set-VMProcessor -VM $vm -Count ([int]$Config.processorCount)

        if ($Config.dynamicMemory -and $Config.dynamicMemory.enabled) {
            Set-VMMemory -VM $vm -DynamicMemoryEnabled $true `
                -MinimumBytes ([long]$Config.dynamicMemory.minimumMB * 1MB) `
                -MaximumBytes ([long]$Config.dynamicMemory.maximumMB * 1MB)
        }

        $cpType = if ($Config.checkpointType) { $Config.checkpointType } else { 'Production' }
        Set-VM -VM $vm -CheckpointType $cpType

        if ([int]$Config.generation -eq 2) {
            $secureBoot = if ($null -ne $Config.secureBoot) { [bool]$Config.secureBoot } else { $true }
            $sbSetting  = if ($secureBoot) { 'On' } else { 'Off' }
            Set-VMFirmware -VM $vm -EnableSecureBoot $sbSetting

            if ($secureBoot -and $Config.secureBootTemplate) {
                Set-VMFirmware -VM $vm -SecureBootTemplate $Config.secureBootTemplate
            }
        }

        if ($Config.type -eq 'freshISO') {
            if ([int]$Config.generation -eq 2) {
                Add-VMDvdDrive -VM $vm -Path $Config.isoPath | Out-Null
                $firmware  = Get-VMFirmware -VM $vm
                $dvdDevice = $firmware.BootOrder | Where-Object {
                    $_.BootType -eq 'Drive' -and $_.Device.GetType().Name -like '*DvdDrive*'
                }
                if ($dvdDevice) {
                    $newOrder = @($dvdDevice) + ($firmware.BootOrder | Where-Object { $_ -ne $dvdDevice })
                    Set-VMFirmware -VM $vm -BootOrder $newOrder
                }
            } else {
                Set-VMDvdDrive -VM $vm -Path $Config.isoPath
            }
        }

        Write-HVLog "VM '$name' created."
        Get-VM -Name $name
    }
}

function Remove-HVMachine {
    <#
    .SYNOPSIS
        Removes a Hyper-V VM, optionally deleting its VHD files.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [switch]$DeleteVHD
    )
    process {
        Assert-HyperVAdmin
        $vm = Get-VM -Name $Name -ErrorAction Stop

        if (-not $PSCmdlet.ShouldProcess($Name, 'Remove Hyper-V VM')) { return }

        $vhdPaths = @()
        if ($DeleteVHD) {
            # Walk the full parent chain for each disk so we catch the base VHDX even
            # when checkpoints have stacked AVHD differencing files on top of it.
            $vhdPaths = foreach ($disk in @($vm | Get-VMHardDiskDrive)) {
                $path = $disk.Path
                while ($path) {
                    $path
                    $vhd  = Get-VHD -Path $path -ErrorAction SilentlyContinue
                    $path = if ($vhd -and $vhd.ParentPath) { $vhd.ParentPath } else { $null }
                }
            }
            $vhdPaths = @($vhdPaths | Where-Object { $_ })
        }

        if ($vm.State -ne 'Off') {
            Write-HVLog "Stopping VM '$Name' before removal"
            Stop-VM -VM $vm -TurnOff -Force
        }

        Write-HVLog "Removing VM '$Name'"
        Remove-VM -VM $vm -Force

        foreach ($path in $vhdPaths) {
            if (Test-Path $path) {
                Write-HVLog "Deleting VHD: $path"
                Remove-Item -Path $path -Force
            }
        }

        Write-HVLog "VM '$Name' removed."
    }
}
