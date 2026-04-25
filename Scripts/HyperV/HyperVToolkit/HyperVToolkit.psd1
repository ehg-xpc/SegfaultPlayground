@{
    ModuleVersion     = '1.0.0'
    GUID              = 'b5c8e3a1-7f2d-4e6b-9c0a-1d2e3f4a5b6c'
    Author            = ''
    Description       = 'Hyper-V VM management toolkit for MSI build and test pipelines'
    PowerShellVersion = '5.1'
    RootModule        = 'HyperVToolkit.psm1'
    FunctionsToExport = @(
        'Get-HVMachine'
        'New-HVMachine'
        'Remove-HVMachine'
        'Start-HVMachine'
        'Stop-HVMachine'
        'Wait-HVReady'
        'New-HVCheckpoint'
        'Remove-HVCheckpoint'
        'Restore-HVCheckpoint'
        'Copy-FileToVM'
        'Copy-FileFromVM'
        'Invoke-VMScript'
        'Invoke-VMScriptFile'
        'Invoke-VMCommand'
        'New-HVSession'
        'Remove-HVSession'
        'Resolve-VMCredential'
        'Get-HVDevVmImage'
        'Get-HVEnterpriseBuild'
        'Get-HVEnterpriseVhd'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
