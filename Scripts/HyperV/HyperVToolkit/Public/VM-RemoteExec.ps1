function Invoke-VMScript {
    <#
    .SYNOPSIS
        Runs a scriptblock on a VM via an existing PowerShell Direct session.
    .PARAMETER VMName
        Name of the target VM (used for logging only).
    .PARAMETER Session
        An open PSSession to the VM (from New-HVSession).
    .PARAMETER ScriptBlock
        The scriptblock to execute on the VM.
    .PARAMETER ArgumentList
        Arguments passed to the scriptblock.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.PSSession]$Session,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList
    )

    Write-HVLog "Executing scriptblock on VM '$VMName'"

    $args = @{
        Session     = $Session
        ScriptBlock = $ScriptBlock
    }
    if ($ArgumentList) { $args['ArgumentList'] = $ArgumentList }

    Invoke-Command @args
}

function Invoke-VMScriptFile {
    <#
    .SYNOPSIS
        Copies a host-side .ps1 script to a VM and executes it.
    .DESCRIPTION
        Stages the script to a temp path on the VM, runs it with the provided
        parameters, cleans up the temp file, and returns a result object.
    .PARAMETER VMName
        Name of the target VM.
    .PARAMETER Session
        An open PSSession to the VM (from New-HVSession).
    .PARAMETER ScriptPath
        Host-side path to the .ps1 file.
    .PARAMETER Parameters
        Hashtable of named parameters to splat into the script.
    .OUTPUTS
        PSCustomObject with: ExitCode, Output, Errors, Success
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.PSSession]$Session,

        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [hashtable]$Parameters = @{}
    )

    if (-not (Test-Path $ScriptPath)) { throw "Script not found: $ScriptPath" }

    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
    $token      = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $vmTempPath = "C:\Windows\Temp\hvtk_${scriptName}_${token}.ps1"

    Write-HVLog "Staging '$($ScriptPath | Split-Path -Leaf)' to VM '$VMName'"
    Copy-FileToVM -VMName $VMName -Session $Session -HostPath $ScriptPath -VMPath $vmTempPath

    Write-HVLog "Executing '$(Split-Path $ScriptPath -Leaf)' on VM '$VMName'"
    $result = Invoke-Command -Session $Session -ArgumentList $vmTempPath, $Parameters -ScriptBlock {
        param([string]$path, [hashtable]$params)
        try {
            $out = & $path @params 2>&1
            [PSCustomObject]@{
                ExitCode = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }
                Output   = $out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
                Errors   = $out | Where-Object { $_ -is  [System.Management.Automation.ErrorRecord] }
                Success  = $?
            }
        } finally {
            Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
        }
    }

    Write-HVLog "'$(Split-Path $ScriptPath -Leaf)' completed. Success=$($result.Success), ExitCode=$($result.ExitCode)"
    $result
}

function Invoke-VMCommand {
    <#
    .SYNOPSIS
        Runs an executable on a VM and returns its exit code.
    .PARAMETER VMName
        Name of the target VM.
    .PARAMETER Session
        An open PSSession to the VM (from New-HVSession).
    .PARAMETER Command
        Executable path or name (e.g. 'msiexec.exe').
    .PARAMETER Arguments
        Command-line arguments as a single string or array of strings.
    .OUTPUTS
        PSCustomObject with: ExitCode, Success
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.PSSession]$Session,

        [Parameter(Mandatory)]
        [string]$Command,

        [string]$Arguments = ''
    )

    Write-HVLog "Running on VM '$VMName': $Command $Arguments"

    $result = Invoke-Command -Session $Session -ArgumentList $Command, $Arguments -ScriptBlock {
        param([string]$cmd, [string]$args)
        $proc = Start-Process -FilePath $cmd -ArgumentList $args -Wait -PassThru -NoNewWindow
        [PSCustomObject]@{
            ExitCode = $proc.ExitCode
            Success  = ($proc.ExitCode -eq 0)
        }
    }

    Write-HVLog "Command completed. ExitCode=$($result.ExitCode)"
    $result
}
