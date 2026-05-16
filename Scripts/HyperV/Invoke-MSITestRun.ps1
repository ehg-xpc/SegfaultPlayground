#Requires -Version 7.0
<#
.SYNOPSIS
    MSI install-and-test orchestrator for Hyper-V VMs.
.DESCRIPTION
    Restores a VM to a known-good checkpoint, installs an MSI silently, runs a
    configurable list of test scripts, collects logs, and returns a structured
    result. All VM communication is via PowerShell Direct (no network required).

    Pass -WhatIf to simulate the run without making any changes.
.PARAMETER ConfigPath
    Path to a test-run.json configuration file.
.PARAMETER Credential
    Optional: PSCredential for the VM guest. If omitted, loaded from the config's
    guestCredential section (passwordSecretEnvVar or interactive prompt).
.OUTPUTS
    PSCustomObject: Success, InstallExitCode, TestResults, LogArchivePath,
                    Duration, Errors
.EXAMPLE
    $result = .\Invoke-MSITestRun.ps1 -ConfigPath .\Configs\test-run.json
    $result | ConvertTo-Json -Depth 5
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [pscredential]$Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:runStart = Get-Date
$script:errors   = [System.Collections.Generic.List[string]]::new()

function Write-Step {
    param([string]$msg)
    Write-Host "`n=== $msg ===" -ForegroundColor Cyan
}

function Add-RunError {
    param([string]$msg)
    Write-Warning $msg
    $script:errors.Add($msg)
}

# ── Load config ──────────────────────────────────────────────────────────────
$configFile = Resolve-Path $ConfigPath -ErrorAction Stop
$cfg        = Get-Content $configFile -Raw | ConvertFrom-Json
$vmName     = $cfg.vmName

Write-Step "MSI Test Run for VM '$vmName'"
Write-Host "Config: $configFile"

# ── Import module ────────────────────────────────────────────────────────────
$modulePsd1 = Join-Path $PSScriptRoot 'HyperVToolkit\HyperVToolkit.psd1'
if (-not (Test-Path $modulePsd1)) {
    throw "HyperVToolkit module not found at '$modulePsd1'. Ensure the module is in the same directory as this script."
}
Import-Module $modulePsd1 -Force -ErrorAction Stop

# ── Resolve credentials ──────────────────────────────────────────────────────
if (-not $Credential) {
    if ($cfg.guestCredential) {
        $Credential = Resolve-VMCredential -CredentialConfig $cfg.guestCredential
    } else {
        $Credential = Get-Credential -Message "Enter credentials for VM '$vmName'"
    }
}

# ── State tracking ───────────────────────────────────────────────────────────
$session         = $null
$testResults     = [System.Collections.Generic.List[PSCustomObject]]::new()
$logArchivePath  = $null
$installExitCode = -1

try {
    # ── Restore checkpoint ───────────────────────────────────────────────────
    Write-Step "Restoring checkpoint '$($cfg.cleanCheckpointName)'"
    Restore-HVCheckpoint -VMName $vmName -Name $cfg.cleanCheckpointName -Start

    # ── Wait for VM ──────────────────────────────────────────────────────────
    $readyTimeout = if ($cfg.readyTimeoutSeconds) { [int]$cfg.readyTimeoutSeconds } else { 180 }
    Write-Step "Waiting for VM to accept connections (${readyTimeout}s timeout)"
    Wait-HVReady -VMName $vmName -Credential $Credential -TimeoutSeconds $readyTimeout

    # ── Open session ─────────────────────────────────────────────────────────
    Write-Step "Opening PowerShell Direct session"
    $session  = New-HVSession -VMName $vmName -Credential $Credential
    $vmWorkDir = if ($cfg.vmInstallDirectory) { $cfg.vmInstallDirectory } else { 'C:\TestRun' }

    # ── Copy and install MSI ─────────────────────────────────────────────────
    $msiName   = Split-Path $cfg.msiPath -Leaf
    $vmMsiPath = Join-Path $vmWorkDir $msiName

    Write-Step "Copying MSI: $msiName"
    Copy-FileToVM -VMName $vmName -Session $session -HostPath $cfg.msiPath -VMPath $vmMsiPath

    $installArgs    = if ($cfg.msiInstallArgs) { $cfg.msiInstallArgs } else { '/quiet /norestart' }
    $installTimeout = if ($cfg.installTimeoutSeconds) { [int]$cfg.installTimeoutSeconds } else { 300 }

    Write-Step "Installing MSI (args: $installArgs)"
    $installExitCode = Invoke-VMScript -VMName $vmName -Session $session `
        -ArgumentList $vmMsiPath, $installArgs -ScriptBlock {
            param([string]$msi, [string]$extraArgs)
            $proc = Start-Process -FilePath 'msiexec.exe' `
                -ArgumentList "/i `"$msi`" $extraArgs" `
                -Wait -PassThru -NoNewWindow
            $proc.ExitCode
        }

    # 0 = success, 3010 = success + reboot required
    if ($installExitCode -notin @(0, 3010)) {
        Add-RunError "MSI install failed with exit code $installExitCode"
    } else {
        Write-Host "MSI installed. ExitCode=$installExitCode$(if ($installExitCode -eq 3010) { ' (reboot required)' })"
    }

    # ── Post-install checkpoint ──────────────────────────────────────────────
    if ($cfg.postInstallCheckpoint -and $cfg.postInstallCheckpoint.enabled) {
        $cpName = if ($cfg.postInstallCheckpoint.name) {
            $cfg.postInstallCheckpoint.name
        } else {
            "$vmName-post-install-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        }
        Write-Step "Creating post-install checkpoint: $cpName"
        New-HVCheckpoint -VMName $vmName -Name $cpName
    }

    # ── Run test scripts ─────────────────────────────────────────────────────
    if ($cfg.testScripts -and $cfg.testScripts.Count -gt 0) {
        Write-Step "Running $($cfg.testScripts.Count) test script(s)"

        foreach ($testDef in $cfg.testScripts) {
            $scriptName = Split-Path $testDef.hostPath -Leaf
            Write-Host "  -> $scriptName"

            $params = @{}
            if ($testDef.arguments) {
                foreach ($prop in $testDef.arguments.PSObject.Properties) {
                    $params[$prop.Name] = $prop.Value
                }
            }

            $timeout = if ($testDef.timeoutSeconds) { [int]$testDef.timeoutSeconds } else { 600 }

            try {
                $testResult = Invoke-VMScriptFile -VMName $vmName -Session $session `
                    -ScriptPath $testDef.hostPath -Parameters $params

                $testResults.Add([PSCustomObject]@{
                    Script   = $scriptName
                    Success  = $testResult.Success
                    ExitCode = $testResult.ExitCode
                    Output   = $testResult.Output
                    Errors   = $testResult.Errors
                })

                if (-not $testResult.Success -and -not $testDef.continueOnFailure) {
                    Add-RunError "Test '$scriptName' failed (ExitCode=$($testResult.ExitCode)). Stopping test run."
                    break
                }
            } catch {
                $errMsg = $_.ToString()
                $testResults.Add([PSCustomObject]@{
                    Script   = $scriptName
                    Success  = $false
                    ExitCode = -1
                    Output   = @()
                    Errors   = @($errMsg)
                })
                if (-not $testDef.continueOnFailure) {
                    Add-RunError "Test '$scriptName' threw: $errMsg"
                    break
                }
            }
        }
    }

    # ── Collect logs ──────────────────────────────────────────────────────────
    $lcfg = $cfg.logCollection
    $collectLogs = -not $lcfg -or $lcfg.enabled -ne $false

    if ($collectLogs) {
        Write-Step "Collecting VM logs"

        $collectorScript = Join-Path $PSScriptRoot 'Collect-VMLogs.ps1'
        if (-not (Test-Path $collectorScript)) {
            Add-RunError "Collect-VMLogs.ps1 not found at '$collectorScript'"
        } else {
            $collectorVMDir  = if ($lcfg -and $lcfg.vmCollectorScriptDirectory) { $lcfg.vmCollectorScriptDirectory } else { $vmWorkDir }
            $collectorVMPath = Join-Path $collectorVMDir 'Collect-VMLogs.ps1'
            $vmLogOutputDir  = Join-Path $collectorVMDir 'Logs'

            $eventLogs  = if ($lcfg -and $lcfg.eventLogs)  { [string[]]$lcfg.eventLogs }  else { @('Application','System','Microsoft-Windows-Installer/Operational') }
            $extraPaths = if ($lcfg -and $lcfg.extraPaths) { [string[]]$lcfg.extraPaths } else { @() }
            $lastHours  = if ($lcfg -and $lcfg.lastHours)  { [int]$lcfg.lastHours }        else { 2 }

            Copy-FileToVM -VMName $vmName -Session $session `
                -HostPath $collectorScript -VMPath $collectorVMPath

            $zipOnVM = Invoke-VMScript -VMName $vmName -Session $session `
                -ArgumentList $collectorVMPath, $vmLogOutputDir, $lastHours, $eventLogs, $extraPaths `
                -ScriptBlock {
                    param([string]$script, [string]$outDir, [int]$hours, [string[]]$logs, [string[]]$paths)
                    & $script -OutputDirectory $outDir -LastHours $hours `
                              -EventLogs $logs -ExtraPaths $paths 2>&1 |
                        Select-Object -Last 1  # last line is the zip path
                }

            if ($zipOnVM -and "$zipOnVM".EndsWith('.zip')) {
                $hostOutDir = $cfg.outputDirectory
                if (-not (Test-Path $hostOutDir)) {
                    New-Item -ItemType Directory -Path $hostOutDir -Force | Out-Null
                }
                $localZip       = Join-Path $hostOutDir (Split-Path "$zipOnVM" -Leaf)
                Copy-FileFromVM -VMName $vmName -Session $session -VMPath "$zipOnVM" -HostPath $localZip
                $logArchivePath = $localZip
                Write-Host "Logs: $logArchivePath"
            } else {
                Add-RunError "Log collector did not return a zip path. Got: $zipOnVM"
            }
        }
    }

} catch {
    Add-RunError "Unhandled error: $_"
} finally {
    if ($session) { Remove-HVSession -Session $session }
}

# ── Build result ──────────────────────────────────────────────────────────────
$duration        = (Get-Date) - $script:runStart
$failedTests     = $testResults | Where-Object { -not $_.Success }
$installOk       = $installExitCode -in @(0, 3010)
$success         = ($script:errors.Count -eq 0) -and $installOk -and (-not $failedTests)

$result = [PSCustomObject]@{
    Success         = $success
    InstallExitCode = $installExitCode
    TestResults     = $testResults.ToArray()
    LogArchivePath  = $logArchivePath
    Duration        = $duration
    Errors          = $script:errors.ToArray()
}

Write-Step "Run complete: Success=$success, Duration=$([math]::Round($duration.TotalSeconds))s"

if ($script:errors.Count -gt 0) {
    Write-Warning "Errors:`n$($script:errors -join "`n")"
}

# Persist result JSON to output directory
$outDir = $cfg.outputDirectory
if ($outDir) {
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $resultPath = Join-Path $outDir "TestResult_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $result | ConvertTo-Json -Depth 5 | Set-Content $resultPath -Encoding UTF8
    Write-Host "Result: $resultPath"
}

$result
