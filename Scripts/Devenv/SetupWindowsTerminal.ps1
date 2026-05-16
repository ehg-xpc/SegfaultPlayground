# Usage:
#   SetupWindowsTerminal.ps1           - Deploy repo settings to Windows Terminal (default)
#   SetupWindowsTerminal.ps1 -Pull     - Pull current Windows Terminal settings back into the repo

param(
    [switch]$Pull
)

# Paths
$wtLocalState   = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
$cfg            = Join-Path $wtLocalState 'settings.json'
$repoSettings   = Join-Path $PSScriptRoot 'terminal.settings.json'
$repoConfigPath = Join-Path $PSScriptRoot 'RepositoryConfig.json'

# --- ID generation helper ---

function New-ProfileGuid {
    param([string]$Seed)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("devenv-profile:$Seed")
    $hash  = [System.Security.Cryptography.MD5]::Create().ComputeHash($bytes)
    $hex   = ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
    return "{$($hex.Substring(0,8))-$($hex.Substring(8,4))-$($hex.Substring(12,4))-$($hex.Substring(16,4))-$($hex.Substring(20,12))}".ToLower()
}

# --- Generated-ID collector (used for cleanup on both deploy and -Pull) ---

function Get-AllGeneratedGuids {
    param($RepositoryConfig)
    $guids = @()
    foreach ($prop in $RepositoryConfig.repositories.PSObject.Properties) {
        $guids += New-ProfileGuid $prop.Name
    }
    return $guids
}

# --- Profile generation ---

function Get-GeneratedRepoProfiles {
    param($RepositoryConfig)

    $profiles  = @()
    $baseRepos = $RepositoryConfig.baseReposPath   # e.g. %Repos% -- WT expands at runtime
    $iconsDir  = '%DEV_REPO%\Resources\Icons'

    foreach ($prop in $RepositoryConfig.repositories.PSObject.Properties) {
        $repoName = $prop.Name
        $repo     = $prop.Value

        # Repos can opt out of profile generation
        if ($repo.PSObject.Properties['generateProfile'] -and $repo.generateProfile -eq $false) {
            continue
        }

        # Icon fallback: per-repo > group > default
        $icon = "$iconsDir\Developer.ico"
        if ($repo.PSObject.Properties['group'] -and $RepositoryConfig.PSObject.Properties['groups']) {
            $grp = $RepositoryConfig.groups.PSObject.Properties |
                   Where-Object { $_.Name -eq $repo.group } |
                   Select-Object -First 1
            if ($grp -and $grp.Value.PSObject.Properties['icon']) { $icon = $grp.Value.icon }
        }
        if ($repo.PSObject.Properties['icon']) { $icon = $repo.icon }

        $tabTitle    = if ($repo.PSObject.Properties['tabTitle'])    { $repo.tabTitle }    else { $repoName }
        $commandline = if ($repo.PSObject.Properties['commandline']) { $repo.commandline } else {
            "pwsh.exe -NoLogo -NoExit -ExecutionPolicy Bypass -File `"%DEV_REPO%\Scripts\Devenv\UserEnv.ps1`" -RepositoryName `"$repoName`""
        }

        $profile = [PSCustomObject]@{
            commandline = $commandline
            guid        = New-ProfileGuid $repoName
            name        = $repoName
            tabTitle    = $tabTitle
            icon        = $icon
        }
        if ($repo.PSObject.Properties['startingDirectory'] -and $repo.startingDirectory) {
            $profile | Add-Member -MemberType NoteProperty -Name 'startingDirectory' -Value ($repo.startingDirectory -replace '/', '\')
        }
        $profiles += $profile
    }

    return $profiles
}

# --- newTabMenu generation ---

function Get-GeneratedNewTabMenu {
    param($RepositoryConfig, $GeneratedProfiles)

    if (-not $RepositoryConfig.PSObject.Properties['groups']) { return $null }

    $iconsDir = '%DEV_REPO%\Resources\Icons'

    $menu = @()
    foreach ($groupProp in $RepositoryConfig.groups.PSObject.Properties) {
        $groupKey  = $groupProp.Name
        $groupCfg  = $groupProp.Value
        $groupName = if ($groupCfg.PSObject.Properties['name']) { $groupCfg.name } else { $groupKey }
        $groupIcon = if ($groupCfg.PSObject.Properties['icon']) { $groupCfg.icon } else { "$iconsDir\Developer.ico" }

        $entries = @()
        foreach ($p in $GeneratedProfiles) {
            $repo = $RepositoryConfig.repositories.PSObject.Properties |
                    Where-Object { $_.Name -eq $p.name } |
                    Select-Object -ExpandProperty Value -First 1
            if ($repo -and $repo.PSObject.Properties['group'] -and $repo.group -eq $groupKey) {
                $entries += [PSCustomObject]@{ type = "profile"; profile = $p.guid }
            }
        }

        if ($entries.Count -gt 0) {
            $menu += [PSCustomObject]@{
                type       = "folder"
                name       = $groupName
                icon       = $groupIcon
                allowEmpty = $false
                inline     = "never"
                entries    = $entries
            }
        }
    }

    # Explicit entries for ungrouped generated profiles
    foreach ($p in $GeneratedProfiles) {
        $repo = $RepositoryConfig.repositories.PSObject.Properties |
                Where-Object { $_.Name -eq $p.name } |
                Select-Object -ExpandProperty Value -First 1
        if ($repo -and -not ($repo.PSObject.Properties['group'] -and $repo.group)) {
            $menu += [PSCustomObject]@{ type = "profile"; profile = $p.guid }
        }
    }

    return $menu
}

# --- Cleanup helpers ---

function Remove-GeneratedMenuEntries {
    param($MenuList, $GeneratedGuids)
    if (-not $MenuList) { return @() }

    # Mark remainingProfiles entries and their adjacent separators for removal
    $removeIdx = [System.Collections.Generic.HashSet[int]]::new()
    for ($i = 0; $i -lt $MenuList.Count; $i++) {
        if ($MenuList[$i].type -ne 'remainingProfiles') { continue }
        $removeIdx.Add($i) | Out-Null
        if ($i -gt 0 -and $MenuList[$i-1].type -eq 'separator') { $removeIdx.Add($i-1) | Out-Null }
        if ($i -lt ($MenuList.Count-1) -and $MenuList[$i+1].type -eq 'separator') { $removeIdx.Add($i+1) | Out-Null }
    }

    $result = @()
    for ($i = 0; $i -lt $MenuList.Count; $i++) {
        if ($removeIdx.Contains($i)) { continue }
        $entry = $MenuList[$i]
        if ($entry.type -eq 'profile' -and $GeneratedGuids -contains $entry.profile) { continue }
        if ($entry.type -eq 'folder') {
            $hasGenerated = $false
            foreach ($e in $entry.entries) {
                if ($GeneratedGuids -contains $e.profile) { $hasGenerated = $true; break }
            }
            if ($hasGenerated) { continue }
        }
        $result += $entry
    }
    return $result
}

function Remove-SupersededMenuEntries {
    param($MenuList, $SupersededGuids)
    if (-not $MenuList -or -not $SupersededGuids) { return $MenuList }
    return @($MenuList | Where-Object {
        if ($_.type -eq 'profile' -and $SupersededGuids -contains $_.profile) { return $false }
        if ($_.type -eq 'folder') {
            $kept = @($_.entries | Where-Object { $SupersededGuids -notcontains $_.profile })
            if ($kept.Count -eq 0) { return $false }
            $_.entries = $kept
        }
        return $true
    })
}

# --- Pull path ---

if ($Pull) {
    if (-not (Test-Path $cfg)) {
        throw "Windows Terminal settings not found at: $cfg"
    }

    if (Test-Path $repoConfigPath) {
        try {
            $repoCfg    = Get-Content $repoConfigPath -Raw | ConvertFrom-Json
            $genGuids   = Get-AllGeneratedGuids $repoCfg
            $deviceJson = Get-Content $cfg -Raw | ConvertFrom-Json

            # Strip generated profiles only -- custom profiles are preserved
            $before = $deviceJson.profiles.list.Count
            $deviceJson.profiles.list = @($deviceJson.profiles.list | Where-Object { $genGuids -notcontains $_.guid })
            $stripped = $before - $deviceJson.profiles.list.Count
            if ($stripped -gt 0) { Write-Host "Stripped $stripped generated profile(s)" }

            # Strip generated menu entries (regenerated on deploy); preserve custom entries
            if ($deviceJson.PSObject.Properties['newTabMenu']) {
                $deviceJson.newTabMenu = Remove-GeneratedMenuEntries $deviceJson.newTabMenu $genGuids
            }

            $deviceJson | ConvertTo-Json -Depth 20 | Set-Content $repoSettings -Encoding UTF8
        }
        catch {
            Write-Warning "Could not strip generated entries: $_. Copying settings as-is."
            Copy-Item -Path $cfg -Destination $repoSettings -Force
        }
    } else {
        Copy-Item -Path $cfg -Destination $repoSettings -Force
    }

    Write-Host "Pulled Windows Terminal settings into repo: $repoSettings"
    return
}

# --- Push (default): deploy repo settings to Windows Terminal ---

if (-not (Test-Path $wtLocalState)) {
    $wtExe = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (-not $wtExe) {
        throw "Windows Terminal is not installed. Install it from the Microsoft Store or via winget: winget install Microsoft.WindowsTerminal"
    }
    New-Item -ItemType Directory -Path $wtLocalState -Force | Out-Null
    Write-Host "Created Windows Terminal LocalState directory: $wtLocalState"
}

# Remove stale symlink -- symlinks in LocalState break single-instance detection
if (Test-Path $cfg) {
    $item = Get-Item $cfg -Force
    if ($item.LinkType) {
        Remove-Item $cfg -Force
        Write-Host "Removed stale symlink at: $cfg"
    }
}

# Back up original settings once
$bak = Join-Path $wtLocalState 'settings_original.json'
if ((Test-Path $cfg) -and -not (Test-Path $bak)) {
    Copy-Item -Path $cfg -Destination $bak -Force
    Write-Host "Backed up original settings to: $bak"
}

# Harvest WSL / Azure Cloud Shell profiles from the original backup
$sourceProfiles = @()
$profileSource  = if (Test-Path $bak) { $bak } elseif (Test-Path $cfg) { $cfg } else { $null }
if ($profileSource) {
    try {
        $deviceJson     = Get-Content $profileSource -Raw | ConvertFrom-Json
        $sourceProfiles = @($deviceJson.profiles.list | Where-Object {
            $_.source -match '^Windows\.Terminal\.(Wsl|Azure)$'
        })
        if ($sourceProfiles.Count -gt 0) {
            Write-Host "Found $($sourceProfiles.Count) profile(s) to preserve:"
            $sourceProfiles | ForEach-Object { Write-Host "  - $($_.name) ($($_.source))" }
        }
    }
    catch { Write-Warning "Could not parse settings for source profiles: $_" }
}

# Load repo settings; if absent, seed from the existing WT settings so the user's
# manual profiles and preferences are preserved (generated content added on top)
if (Test-Path $repoSettings) {
    $repoJson = Get-Content $repoSettings -Raw | ConvertFrom-Json
} elseif (Test-Path $cfg) {
    Write-Host "terminal.settings.json not in repo -- seeding from existing Windows Terminal settings"
    $repoJson = Get-Content $cfg -Raw | ConvertFrom-Json
} else {
    $repoJson = [PSCustomObject]@{}
}
if (-not $repoJson.PSObject.Properties['profiles']) {
    $repoJson | Add-Member -MemberType NoteProperty -Name 'profiles' -Value ([PSCustomObject]@{ list = @() })
}
if (-not $repoJson.profiles.PSObject.Properties['list']) {
    $repoJson.profiles | Add-Member -MemberType NoteProperty -Name 'list' -Value @()
}

if (Test-Path $repoConfigPath) {
    try {
        $repoCfg           = Get-Content $repoConfigPath -Raw | ConvertFrom-Json
        $generatedProfiles = Get-GeneratedRepoProfiles $repoCfg
        $allGenGuids       = Get-AllGeneratedGuids $repoCfg

        $supersededGuids = if ($repoCfg.PSObject.Properties['supersededProfiles']) { @($repoCfg.supersededProfiles) } else { @() }
        $allRetireGuids  = $allGenGuids + $supersededGuids

        # --- Profiles ---
        $repoJson.profiles.list = @($repoJson.profiles.list | Where-Object { $allRetireGuids -notcontains $_.guid })
        $repoJson.profiles.list = $generatedProfiles + @($repoJson.profiles.list)
        Write-Host "Injected $($generatedProfiles.Count) profile(s) from RepositoryConfig.json"

        # --- Default profile ---
        if ($repoCfg.PSObject.Properties['defaultProfile'] -and $repoCfg.defaultProfile) {
            $repoJson.defaultProfile = New-ProfileGuid $repoCfg.defaultProfile
        }

        # --- newTabMenu ---
        $generatedMenu = Get-GeneratedNewTabMenu $repoCfg $generatedProfiles
        if ($generatedMenu -and $generatedMenu.Count -gt 0) {
            $existing = if ($repoJson.PSObject.Properties['newTabMenu']) {
                $cleaned = Remove-GeneratedMenuEntries $repoJson.newTabMenu $allGenGuids
                Remove-SupersededMenuEntries $cleaned $supersededGuids
            } else { $null }
            $tail = @(
                [PSCustomObject]@{ type = "separator" },
                [PSCustomObject]@{ type = "remainingProfiles" },
                [PSCustomObject]@{ type = "separator" }
            )
            $repoJson.newTabMenu = @($generatedMenu + $existing + $tail | Where-Object { $null -ne $_ })
            Write-Host "Injected $($generatedMenu.Count) group folder(s) into newTabMenu"
        }
    }
    catch {
        Write-Warning "Could not generate profiles from RepositoryConfig.json: $_"
    }
}

# Inject preserved WSL / Azure Cloud Shell profiles
if ($sourceProfiles.Count -gt 0) {
    $repoGuids = @($repoJson.profiles.list | ForEach-Object { $_.guid }) | Where-Object { $_ }
    foreach ($sp in $sourceProfiles) {
        if ($sp.guid -and $repoGuids -contains $sp.guid) {
            Write-Host "  Skipping (already present): $($sp.name)"
            continue
        }
        $repoJson.profiles.list += $sp
    }
}

$repoJson | ConvertTo-Json -Depth 20 | Set-Content $cfg -Encoding UTF8
Write-Host "Deployed settings to: $cfg"
Write-Host "To pull changes back into the repo, run: SetupWindowsTerminal.ps1 -Pull"
