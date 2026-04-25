function Get-HVDevVmImage {
    <#
    .SYNOPSIS
        Downloads a Windows developer VM image from the Microsoft developer portal
        and extracts the VHDX for use as a Hyper-V template.
    .DESCRIPTION
        Get the Hyper-V download URL from:
            https://developer.microsoft.com/en-us/windows/downloads/virtual-machines/
        The downloaded zip is extracted and the VHDX is placed in OutputDirectory.
        Uses BITS transfer when available for progress reporting and resume support.
    .PARAMETER Url
        Direct download URL for the Hyper-V zip from the developer portal.
    .PARAMETER OutputDirectory
        Where to store the extracted VHDX. Defaults to the Hyper-V host's default VHD path.
    .PARAMETER KeepZip
        Retain the source zip after extraction.
    .OUTPUTS
        Full path to the extracted VHDX file.
    .EXAMPLE
        $vhdx = Get-HVDevVmImage -Url 'https://aka.ms/windev_VM_hyperv' -OutputDirectory C:\VMs\Templates
        New-HVMachine -Config (Get-Content vm-template.json | ConvertFrom-Json | Add-Member -PassThru -NotePropertyName templateVHDPath -NotePropertyValue $vhdx)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [string]$OutputDirectory,

        [switch]$KeepZip
    )

    $outDir = Resolve-ImageOutputDirectory $OutputDirectory

    # Derive a local zip filename from the URL leaf, falling back to a timestamped name
    $urlLeaf = [System.IO.Path]::GetFileName(([uri]$Url).LocalPath)
    $zipName = if ($urlLeaf -like '*.zip') { $urlLeaf } else { "WinDevVM_$(Get-Date -Format 'yyyyMMdd').zip" }
    $zipPath = Join-Path $outDir $zipName

    Write-HVLog "Downloading developer VM image"
    Write-HVLog "  URL: $Url"
    Write-HVLog "  Destination: $zipPath"

    Invoke-HVBitsDownload -Url $Url -Destination $zipPath -DisplayName 'Windows Dev VM'

    Write-HVLog "Extracting archive..."
    $extractDir = Join-Path $outDir ([System.IO.Path]::GetFileNameWithoutExtension($zipName))
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $vhdFile = Get-ChildItem -Path $extractDir -Recurse -Include '*.vhdx', '*.vhd' |
        Sort-Object Length -Descending |
        Select-Object -First 1

    if (-not $vhdFile) { throw "No VHD/VHDX found in extracted archive at '$extractDir'" }

    $destVhd = Join-Path $outDir $vhdFile.Name
    Write-HVLog "Moving '$($vhdFile.Name)' to '$outDir'"
    Move-Item -Path $vhdFile.FullName -Destination $destVhd -Force

    Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $KeepZip) { Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue }

    Write-HVLog "Image ready: $destVhd"
    $destVhd
}

function Get-HVEnterpriseBuild {
    <#
    .SYNOPSIS
        Lists Windows builds available on an internal Microsoft build share.
    .DESCRIPTION
        Enumerates build directories under a branch path on \\winbuilds\release or
        \\ntdev\release. The share is organized as <root>\<branch>\<build>\, so
        BuildShare must point to the branch level, e.g. \\winbuilds\release\br_release.
        Builds are sorted newest first by build number.
    .PARAMETER BuildShare
        UNC path to the branch directory, e.g. \\winbuilds\release\br_release or
        \\ntdev\release\main_release.
    .PARAMETER Architecture
        Processor architecture subfolder. Default: amd64fre.
    .PARAMETER Count
        Maximum number of builds to return. Default: 10.
    .PARAMETER Filter
        Optional wildcard filter on the build directory name, e.g. '28000*'.
    .OUTPUTS
        PSCustomObjects with: Build, Architecture, DiskDirectory, Format, Files
    .EXAMPLE
        Get-HVEnterpriseBuild -BuildShare \\winbuilds\release\br_release -Count 5
        Get-HVEnterpriseBuild -BuildShare \\ntdev\release\main_release -Filter '28000*'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BuildShare,

        [ValidateSet('amd64fre', 'x86fre', 'arm64fre')]
        [string]$Architecture = 'amd64fre',

        [int]$Count = 10,

        [string]$Filter = '*'
    )

    if (-not (Test-Path $BuildShare)) {
        throw "Build share not accessible: $BuildShare. Ensure you are on the corporate network or VPN."
    }

    Write-HVLog "Enumerating builds at '$BuildShare' (arch=$Architecture, filter=$Filter)"

    Get-ChildItem -Path $BuildShare -Directory -Filter $Filter -ErrorAction Stop |
        Where-Object { $_.Name -match '^\d+\.\d+' } |
        Sort-Object { Resolve-BuildSortKey $_.Name } -Descending |
        Select-Object -First ($Count * 3) |  # over-fetch because many may lack VHDs
        ForEach-Object {
            $buildName = $_.Name
            $archBase  = Join-Path $_.FullName $Architecture

            # VHDXs are preferred; fall back to VHDs
            $diskDir = $null
            $fmt     = $null
            foreach ($candidate in @('vhdx', 'vhd')) {
                $path = Join-Path $archBase $candidate
                if (Test-Path $path) { $diskDir = $path; $fmt = $candidate; break }
            }

            # Also check for disk images directly under the arch folder (some builds skip the subdir)
            if (-not $diskDir) {
                $direct = Get-ChildItem -Path $archBase -Filter '*.vhdx' -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if (-not $direct) {
                    $direct = Get-ChildItem -Path $archBase -Filter '*.vhd' -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                }
                if ($direct) { $diskDir = $archBase; $fmt = $direct.Extension.TrimStart('.') }
            }

            if (-not $diskDir) { return }

            # Files may be nested one level deeper in per-edition subdirs (e.g. vhdx\vhdx_client_enterprise_en-us\*.vhdx)
            $files = Get-ChildItem -Path $diskDir -Filter "*.$fmt" -Recurse -ErrorAction SilentlyContinue

            if ($files) {
                [PSCustomObject]@{
                    Build         = $buildName
                    Architecture  = $Architecture
                    DiskDirectory = $diskDir
                    Format        = $fmt
                    Files         = $files
                }
            }
        } |
        Select-Object -First $Count
}

function Get-HVEnterpriseVhd {
    <#
    .SYNOPSIS
        Copies (or references) a Windows VHD/VHDX from an internal Microsoft build share.
    .DESCRIPTION
        Finds the specified (or latest) build under a branch path on the share, selects a
        VHD file (optionally filtered by edition name), and copies it locally using BITS.
        Use -NoCopy to get the UNC path directly for use with a differencing disk.
        BuildShare must be the branch-level path (see Get-HVEnterpriseBuild).
    .PARAMETER BuildShare
        UNC path to the branch directory, e.g. \\winbuilds\release\br_release or
        \\ntdev\release\main_release.
    .PARAMETER BuildNumber
        Specific build directory name, e.g. '28000.1.251103-1709'. Omit to use the latest
        build that has a VHD available.
    .PARAMETER Architecture
        Processor architecture subfolder. Default: amd64fre.
    .PARAMETER Edition
        Substring to match against VHD filenames to select a specific edition,
        e.g. 'enterprise', 'professional', 'serverdatacenter'. Case-insensitive.
        If multiple files still match, the first is used and a warning is emitted.
    .PARAMETER OutputDirectory
        Local path to copy the VHD to. Defaults to the Hyper-V host's default VHD path.
    .PARAMETER NoCopy
        Return the UNC share path directly without copying. Useful when you want
        to create a differencing disk against the share image (faster, no local copy).
        The share must remain accessible while the VM is running.
    .OUTPUTS
        Full path to the VHD/VHDX (local copy, or UNC if -NoCopy).
    .EXAMPLE
        # Latest build, copy locally
        $vhd = Get-HVEnterpriseVhd -BuildShare \\winbuilds\release\br_release -Edition enterprise

        # Specific build, no copy (use as differencing parent)
        $vhd = Get-HVEnterpriseVhd -BuildShare \\ntdev\release\main_release -BuildNumber 28000.1.251103-1709 -NoCopy
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BuildShare,

        [string]$BuildNumber,

        [ValidateSet('amd64fre', 'x86fre', 'arm64fre')]
        [string]$Architecture = 'amd64fre',

        [string]$Edition,

        [string]$OutputDirectory,

        [switch]$NoCopy
    )

    if (-not (Test-Path $BuildShare)) {
        throw "Build share not accessible: $BuildShare. Ensure you are on the corporate network or VPN."
    }

    # Resolve build directory
    if ($BuildNumber) {
        $buildDir = Join-Path $BuildShare $BuildNumber
        if (-not (Test-Path $buildDir)) { throw "Build '$BuildNumber' not found at '$BuildShare'" }
        Write-HVLog "Using build: $BuildNumber"
    } else {
        Write-HVLog "Resolving latest build from '$BuildShare'..."
        $latestBuild = Get-HVEnterpriseBuild -BuildShare $BuildShare -Architecture $Architecture -Count 1
        if (-not $latestBuild) { throw "No builds with VHD/VHDX found at '$BuildShare' for architecture '$Architecture'" }
        $buildDir = Join-Path $BuildShare $latestBuild.Build
        Write-HVLog "Latest build: $($latestBuild.Build)"
    }

    # Locate disk directory
    $archBase = Join-Path $buildDir $Architecture
    $diskDir  = $null
    $fmt      = $null
    foreach ($candidate in @('vhdx', 'vhd')) {
        $path = Join-Path $archBase $candidate
        if (Test-Path $path) { $diskDir = $path; $fmt = $candidate; break }
    }
    if (-not $diskDir) {
        # Fall back: files anywhere under arch folder
        foreach ($candidate in @('vhdx', 'vhd')) {
            if (Get-ChildItem -Path $archBase -Filter "*.$candidate" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) {
                $diskDir = $archBase; $fmt = $candidate; break
            }
        }
    }
    if (-not $diskDir) {
        throw "No vhd/vhdx directory found under '$archBase'"
    }

    # Select file -- recurse into edition subdirs (e.g. vhdx\vhdx_client_enterprise_en-us\*.vhdx)
    $candidates = @(Get-ChildItem -Path $diskDir -Filter "*.$fmt" -Recurse -ErrorAction Stop)
    if ($Edition) {
        $candidates = @($candidates | Where-Object { $_.Name -like "*$Edition*" })
    }
    if ($candidates.Count -eq 0) {
        throw "No .$fmt files found in '$diskDir'$(if ($Edition) { " matching edition '$Edition'" })"
    }
    if ($candidates.Count -gt 1) {
        Write-HVLog "Multiple images found; using first. Use -Edition to narrow down:" -Level Warning
        $candidates | ForEach-Object { Write-HVLog "  $($_.Name)" -Level Warning }
    }
    $srcFile = $candidates[0]

    if ($NoCopy) {
        Write-HVLog "Returning UNC path (no local copy): $($srcFile.FullName)"
        return $srcFile.FullName
    }

    $outDir  = Resolve-ImageOutputDirectory $OutputDirectory
    $destPath = Join-Path $outDir $srcFile.Name

    $sizeGB = [math]::Round($srcFile.Length / 1GB, 1)
    Write-HVLog "Copying '$($srcFile.Name)' (${sizeGB} GB) from build share..."
    Invoke-HVBitsDownload -Url $srcFile.FullName -Destination $destPath -DisplayName "Copy $($srcFile.Name)"

    Write-HVLog "VHD ready: $destPath"
    $destPath
}

# ── Private helpers (file-local) ─────────────────────────────────────────────

function Resolve-ImageOutputDirectory {
    param([string]$OutputDirectory)
    $dir = if ($OutputDirectory) {
        $OutputDirectory
    } else {
        # Prefer the Hyper-V host default when available; fall back to a user-writable
        # path so image downloads work without elevation.
        $hvDefault = try { (Get-VMHost -ErrorAction Stop).VirtualHardDiskPath } catch { $null }
        if ($hvDefault) { $hvDefault } else { Join-Path $env:USERPROFILE 'HyperV\Images' }
    }
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dir
}

function Resolve-BuildSortKey {
    param([string]$BuildName)
    # Extract leading <major>.<minor> for numeric sort, e.g. '26100.1234' from '26100.1234.230901-0001'
    if ($BuildName -match '^(\d+)\.(\d+)') {
        return [long]$Matches[1] * 1000000 + [long]$Matches[2]
    }
    return [long]0
}

function Invoke-HVBitsDownload {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$DisplayName
    )
    # Prefer BITS (built-in, supports resume and shows progress).
    # Fall back to Invoke-WebRequest for UNC paths (BITS doesn't handle \\server\share).
    $isUNC = $Url.StartsWith('\\')
    if (-not $isUNC -and (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue)) {
        Start-BitsTransfer -Source $Url -Destination $Destination -DisplayName $DisplayName -ErrorAction Stop
    } else {
        Copy-Item -Path $Url -Destination $Destination -Force -ErrorAction Stop
    }
}
