#Requires -Version 5.1
<#
.SYNOPSIS
    Smoke-tests the HyperVToolkit module against the local Hyper-V host.
.DESCRIPTION
    Creates a minimal VM from a blank template VHD, exercises lifecycle and
    checkpoint functions, then tears everything down. Does NOT require a
    Windows guest image -- this covers all operations that work on a powered-off VM.

    Functions that require a live Windows guest (Wait-HVReady, New-HVSession,
    file transfer, remote exec) are NOT exercised here; test those once you
    have a running guest OS.
.PARAMETER VmName
    Name for the test VM. Default: HVToolkit-Test.
.PARAMETER VhdDirectory
    Where to place test VHDs. Defaults to the host's default VHD path.
.PARAMETER KeepVm
    If set, do not delete the VM at the end (useful for inspecting results).
#>
param(
    [string]$VmName = 'HVToolkit-Test',
    [string]$VhdDirectory,
    [switch]$KeepVm
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pass = 0; $fail = 0
$failures = [System.Collections.Generic.List[string]]::new()

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    Write-Host "  $Name ... " -NoNewline
    try {
        & $Body
        Write-Host 'PASS' -ForegroundColor Green
        $script:pass++
    } catch {
        Write-Host "FAIL: $_" -ForegroundColor Red
        $script:fail++
        $script:failures.Add("$Name`: $_")
    }
}

# ── Bootstrap ────────────────────────────────────────────────────────────────
Write-Host "`n=== HyperVToolkit smoke test ===" -ForegroundColor Cyan

$modulePsd1 = Join-Path $PSScriptRoot 'HyperVToolkit\HyperVToolkit.psd1'
if (-not (Test-Path $modulePsd1)) { throw "Module not found: $modulePsd1" }
Import-Module $modulePsd1 -Force
Write-Host "Module loaded: $modulePsd1"

$vhdDir = if ($VhdDirectory) { $VhdDirectory } else { (Get-VMHost).VirtualHardDiskPath }
if (-not (Test-Path $vhdDir)) { New-Item -ItemType Directory -Path $vhdDir -Force | Out-Null }

$templateVhd = Join-Path $vhdDir "${VmName}-template.vhdx"
$vmVhd       = Join-Path $vhdDir "${VmName}.vhdx"

# Ensure clean slate
foreach ($path in $templateVhd, $vmVhd) {
    if (Test-Path $path) { Remove-Item $path -Force }
}
if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) {
    Remove-HVMachine -Name $VmName -DeleteVHD -Confirm:$false
}

Write-Host "VHD directory: $vhdDir"
Write-Host "Test VM name:  $VmName"

# ── Create a tiny blank template VHD ────────────────────────────────────────
Write-Host "`n--- Setup ---"
Write-Host "  Creating blank template VHD (1 GB) ..."
New-VHD -Path $templateVhd -SizeBytes 1GB -Dynamic | Out-Null
Write-Host "  Template VHD: $templateVhd"

# ── Test config ──────────────────────────────────────────────────────────────
$cfg = [PSCustomObject]@{
    name           = $VmName
    type           = 'templateClone'
    generation     = 2
    memorySizeMB   = 512
    processorCount = 1
    vhdSizeGB      = 1
    switchName     = 'Default Switch'
    templateVHDPath = $templateVhd
    differencing   = $false
    checkpointType = 'Standard'
    vhdDirectory   = $vhdDir
    secureBoot     = $false
}

# ── VM Lifecycle ─────────────────────────────────────────────────────────────
Write-Host "`n--- VM Lifecycle ---"

Test-Case 'Get-HVMachine (before create)' {
    $vms = @(Get-HVMachine -Name $VmName)
    if ($vms.Count -ne 0) { throw "VM should not exist yet (found $($vms.Count))" }
}

Test-Case 'New-HVMachine (templateClone)' {
    $vm = New-HVMachine -Config $cfg
    if (-not $vm) { throw 'No VM object returned' }
    if ($vm.Name -ne $VmName) { throw "Wrong VM name: $($vm.Name)" }
}

Test-Case 'Get-HVMachine (after create)' {
    $vm = Get-HVMachine -Name $VmName
    if (-not $vm) { throw 'VM not found after creation' }
    if ($vm.State -ne 'Off') { throw "Expected state Off, got $($vm.State)" }
}

Test-Case 'VHD clone was created' {
    if (-not (Test-Path $vmVhd)) { throw "VHD not found at $vmVhd" }
}

# ── Power ────────────────────────────────────────────────────────────────────
Write-Host "`n--- Power ---"

Test-Case 'Start-HVMachine' {
    Start-HVMachine -Name $VmName
    $state = (Get-VM -Name $VmName).State
    if ($state -notin @('Running','Starting')) { throw "Expected Running, got $state" }
}

Test-Case 'Start-HVMachine (already running -- should be no-op)' {
    Start-HVMachine -Name $VmName  # should not throw
}

Test-Case 'Stop-HVMachine -Force' {
    Stop-HVMachine -Name $VmName -Force
    $state = (Get-VM -Name $VmName).State
    if ($state -ne 'Off') { throw "Expected Off, got $state" }
}

Test-Case 'Stop-HVMachine (already off -- should be no-op)' {
    Stop-HVMachine -Name $VmName -Force  # should not throw
}

# ── Checkpoints ──────────────────────────────────────────────────────────────
Write-Host "`n--- Checkpoints ---"

Test-Case 'New-HVCheckpoint' {
    New-HVCheckpoint -VMName $VmName -Name 'test-checkpoint-1'
    $cp = Get-VMCheckpoint -VMName $VmName -Name 'test-checkpoint-1' -ErrorAction SilentlyContinue
    if (-not $cp) { throw 'Checkpoint not found after creation' }
}

Test-Case 'New-HVCheckpoint (second -- different state)' {
    # Start+stop the VM to change its state before taking the second checkpoint,
    # otherwise Hyper-V deduplicates Standard checkpoints with identical disk state.
    Start-HVMachine -Name $VmName
    Stop-HVMachine  -Name $VmName -Force
    New-HVCheckpoint -VMName $VmName -Name 'test-checkpoint-2'
    $cp2 = Get-VMCheckpoint -VMName $VmName -Name 'test-checkpoint-2' -ErrorAction SilentlyContinue
    if (-not $cp2) { throw 'test-checkpoint-2 not found after creation' }
}

Test-Case 'Restore-HVCheckpoint' {
    Restore-HVCheckpoint -VMName $VmName -Name 'test-checkpoint-1' -Confirm:$false
    $state = (Get-VM -Name $VmName).State
    if ($state -ne 'Off') { throw "Expected Off after restore, got $state" }
}

Test-Case 'Restore-HVCheckpoint -Start' {
    New-HVCheckpoint -VMName $VmName -Name 'test-checkpoint-restart'
    Restore-HVCheckpoint -VMName $VmName -Name 'test-checkpoint-restart' -Start -Confirm:$false
    $state = (Get-VM -Name $VmName).State
    if ($state -notin @('Running', 'Starting')) { throw "Expected Running after restore+start, got $state" }
    Stop-HVMachine -Name $VmName -Force
}

Test-Case 'Remove-HVCheckpoint' {
    New-HVCheckpoint -VMName $VmName -Name 'to-delete'
    Remove-HVCheckpoint -VMName $VmName -Name 'to-delete' -Confirm:$false
    $cp = Get-VMCheckpoint -VMName $VmName -Name 'to-delete' -ErrorAction SilentlyContinue
    if ($cp) { throw 'Checkpoint still exists after removal' }
}

# ── Image source (offline tests -- no network/download needed) ───────────────
Write-Host "`n--- Image Source ---"

Test-Case 'Get-HVEnterpriseBuild: inaccessible share returns friendly error' {
    try {
        Get-HVEnterpriseBuild -BuildShare '\\nonexistent\share' -ErrorAction Stop
        throw 'Expected an error for inaccessible share'
    } catch {
        if ($_.Exception.Message -notlike '*not accessible*') { throw "Unexpected error message: $_" }
    }
}

Test-Case 'Get-HVEnterpriseVhd: inaccessible share returns friendly error' {
    try {
        Get-HVEnterpriseVhd -BuildShare '\\nonexistent\share' -NoCopy -ErrorAction Stop
        throw 'Expected an error for inaccessible share'
    } catch {
        if ($_.Exception.Message -notlike '*not accessible*') { throw "Unexpected error message: $_" }
    }
}

Test-Case 'Get-HVEnterpriseBuild: live share (informational)' {
    # BuildShare must be the branch-level path, not the root.
    # br_release is the main Windows client release branch.
    $share = '\\winbuilds\release\br_release'
    if (-not (Test-Path $share)) {
        Write-Host '(skipped -- share unreachable)' -NoNewline
        return
    }
    $builds = @(Get-HVEnterpriseBuild -BuildShare $share -Count 3)
    if ($builds.Count -gt 0) {
        Write-Host "(found $($builds.Count) build(s): $($builds[0].Build), $($builds[0].Files.Count) image(s))" -NoNewline
    } else {
        Write-Host '(share reachable but no builds matched expected directory structure)' -NoNewline
    }
}

# ── Teardown ─────────────────────────────────────────────────────────────────
Write-Host "`n--- Teardown ---"

if (-not $KeepVm) {
    Test-Case 'Remove-HVMachine -DeleteVHD' {
        Remove-HVMachine -Name $VmName -DeleteVHD -Confirm:$false
        $vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
        if ($vm) { throw 'VM still exists after removal' }
        if (Test-Path $vmVhd) { throw "VHD still exists at $vmVhd" }
    }
} else {
    Write-Host '  Skipping teardown (-KeepVm).'
}

# Remove template VHD
if (Test-Path $templateVhd) { Remove-Item $templateVhd -Force }

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n=== Results: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($failures.Count -gt 0) {
    Write-Host 'Failed tests:'
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

if ($fail -gt 0) { exit 1 }
