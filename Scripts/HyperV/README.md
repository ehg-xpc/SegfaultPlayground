# HyperV Toolkit

PowerShell module and scripts for managing Hyper-V VMs in an MSI build-and-test pipeline.

## Requirements

- Windows 10/11 or Windows Server with Hyper-V enabled
- PowerShell 5.1+
- Membership in the local **Administrators** or **Hyper-V Administrators** group

### Running without a fully elevated shell

All VM management operations work from a non-elevated session as long as you are a member of the **Hyper-V Administrators** local group. Full elevation (`Run as Administrator`) is only needed for host-level changes such as enabling the Hyper-V Windows feature.

Add yourself to the group once, then re-login:

```powershell
Add-LocalGroupMember -Group 'Hyper-V Administrators' -Member $env:USERNAME
```

After re-login, all toolkit functions work from a normal (non-elevated) shell.

## Module: HyperVToolkit

### Loading

```powershell
Import-Module .\HyperVToolkit\HyperVToolkit.psd1
```

### VM Lifecycle

| Function | Description |
|---|---|
| `Get-HVMachine [-Name <pattern>]` | List VMs, optionally filtered by name/wildcard |
| `New-HVMachine -Config <obj>` | Create a VM from a config object or `-ConfigPath <json>` |
| `Remove-HVMachine -Name <vm> [-DeleteVHD]` | Remove a VM, optionally deleting all VHD files (walks the full differencing chain) |

`New-HVMachine` supports two creation modes via the `type` field in the config:

- `templateClone` -- copies or differences from an existing VHDX
- `freshISO` -- creates a new blank VHD and attaches an ISO for OS install

Config fields:

| Field | Required | Description |
|---|---|---|
| `name` | yes | VM name |
| `type` | yes | `templateClone` or `freshISO` |
| `generation` | yes | `1` or `2` |
| `memorySizeMB` | yes | Startup RAM in MB |
| `processorCount` | yes | vCPU count |
| `vhdSizeGB` | yes | VHD size in GB (freshISO only) |
| `switchName` | yes | Virtual switch name |
| `templateVHDPath` | templateClone | Path to the source VHDX |
| `differencing` | templateClone | `true` for differencing disk, `false` (default) to copy |
| `isoPath` | freshISO | Path to the OS install ISO |
| `checkpointType` | no | `Standard` or `Production` (default) |
| `secureBoot` | no | Gen2 only. Default `true` |
| `secureBootTemplate` | no | e.g. `MicrosoftWindows`, `MicrosoftUEFICertificateAuthority` |
| `vhdDirectory` | no | Override for VHD output directory |
| `dynamicMemory` | no | `{ enabled, minimumMB, maximumMB }` |

See `Configs/vm-template.json` and `Configs/vm-fresh.json` for examples.

### Power Management

| Function | Description |
|---|---|
| `Start-HVMachine -Name <vm>` | Start a VM (no-op if already running) |
| `Stop-HVMachine -Name <vm> [-Force]` | Stop a VM (no-op if already off); `-Force` does a hard power-off |
| `Wait-HVReady -Name <vm> -Credential <cred>` | Poll via PowerShell Direct until the VM responds or timeout |

### Checkpoints

| Function | Description |
|---|---|
| `New-HVCheckpoint -VMName <vm> -Name <name>` | Create a named checkpoint; polls until the WMI layer reflects it |
| `Restore-HVCheckpoint -VMName <vm> -Name <name> [-Start]` | Restore a checkpoint (stops VM first if needed); `-Start` boots after restore |
| `Remove-HVCheckpoint -VMName <vm> -Name <name> [-IncludeSubtree]` | Remove a checkpoint |

`Restore-HVCheckpoint` has `ConfirmImpact = High`. Pass `-Confirm:$false` in unattended/batch use.

### Sessions and Remote Execution

```powershell
$cred = Resolve-VMCredential -Username 'VM\User'   # reads $env:TESTVM_PASSWORD or prompts
$s    = New-HVSession -VMName 'TestVM' -Credential $cred

Invoke-VMScript   -Session $s -ScriptBlock { Get-Process }
Invoke-VMCommand  -Session $s -Executable 'msiexec.exe' -Arguments '/i C:\foo.msi /quiet'

Remove-HVSession  -Session $s
```

`Invoke-VMScriptFile -Session $s -ScriptPath .\Test.ps1 -Arguments @{Param1='value'}` copies the script to the VM, runs it, and returns `{ExitCode, Output, Errors, Success}`.

### File Transfer

```powershell
Copy-FileToVM   -Session $s -HostPath   C:\build\MyProduct.msi -GuestPath C:\Install\
Copy-FileFromVM -Session $s -GuestPath  C:\Logs\results.zip    -HostPath  C:\Results\
```

### Acquiring VM Images

#### Public developer VM (no elevation required)

Downloads a pre-built Windows dev environment image from the Microsoft developer portal:

```powershell
$vhdx = Get-HVDevVmImage -Url 'https://aka.ms/windev_VM_hyperv' -OutputDirectory C:\VMs\Templates
```

Get the current download URL from: https://developer.microsoft.com/en-us/windows/downloads/virtual-machines/

Uses BITS transfer for progress reporting and resume support. Falls back to `Copy-Item` if BITS is unavailable.

#### Internal Microsoft build shares

List available builds:

```powershell
Get-HVEnterpriseBuild -BuildShare \\winbuilds\release -Count 5
Get-HVEnterpriseBuild -BuildShare \\ntdev\release -Filter '26100*'
```

Copy the latest VHD locally (uses BITS):

```powershell
$vhd = Get-HVEnterpriseVhd -BuildShare \\winbuilds\release -Edition Enterprise
```

Use the share image directly as a differencing parent (no local copy):

```powershell
$vhd = Get-HVEnterpriseVhd -BuildShare \\ntdev\release -BuildNumber 26100.1234 -NoCopy
```

Requires corporate network or VPN access.

## Scripts

### Test-HyperVToolkit.ps1

Smoke test for the module. Creates a minimal VM from a blank VHD, exercises lifecycle, power, and checkpoint operations, then tears everything down. Does not require a Windows guest image.

```powershell
.\Test-HyperVToolkit.ps1
.\Test-HyperVToolkit.ps1 -VmName MyTestVM -VhdDirectory D:\VHDs -KeepVm
```

### Collect-VMLogs.ps1

Run **on the VM** to gather event logs and files, then package them into a zip. The orchestrator copies this script to the VM and calls it via PowerShell Direct.

```powershell
# Run on the VM
.\Collect-VMLogs.ps1 -OutputDirectory C:\Logs -LastHours 4 `
    -EventLogs @('Application','System','Setup') `
    -ExtraPaths @('C:\ProgramData\MyProduct\Logs')
```

Outputs the zip file path to stdout for the caller to retrieve.

### Invoke-MSITestRun.ps1

Config-driven orchestrator that ties the full pipeline together:

1. Restore clean checkpoint
2. Start VM and wait for it to be ready
3. Open a PowerShell Direct session
4. Copy and install the MSI
5. Optionally take a post-install checkpoint
6. Run test scripts
7. Collect logs and copy the zip to the host
8. Return a structured result object and write a JSON summary

```powershell
$result = .\Invoke-MSITestRun.ps1 -ConfigPath .\Configs\test-run.json
```

Returns `{Success, InstallExitCode, TestResults, LogArchivePath, Duration, Errors}`.

See `Configs/test-run.json` for a full example config.
