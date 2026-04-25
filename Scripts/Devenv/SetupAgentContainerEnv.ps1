#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Provisions and refreshes the ADO PAT stored in ~/.stanley/agent-container.env.

.DESCRIPTION
    Ensures ~/.stanley/agent-container.env exists with a valid AZDO_PAT that allows
    the container agent to clone repos, push commits, manage PRs, and create work items.

    On each run the script:
      1. Reads the existing AZDO_PAT from the env file (if any).
      2. Validates it by calling the ADO PAT list API and checking the expiry date.
      3. If the token is missing, invalid, expiring within 30 days, or -Force is passed,
         creates a new PAT (valid for 7 days) via the ADO REST API and saves it.

    Other variables already present in the env file are preserved unchanged.

.PARAMETER Force
    Skip the existing-token check and always create a fresh PAT.

.EXAMPLE
    .\SetupAgentContainerEnv.ps1
    .\SetupAgentContainerEnv.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ── Constants ────────────────────────────────────────────────────────────────

$EnvFile      = Join-Path $env:USERPROFILE '.stanley\agent-container.env'
$DisplayName  = 'AgentContainer'
$Scopes       = 'vso.code_write vso.work_write vso.build'
$ValidityDays = 7
$RefreshDays  = 2    # recreate if expiry is within this many days
$AzdoOrg      = 'onedrive'
$PatApiUri    = "https://vssps.dev.azure.com/$AzdoOrg/_apis/tokens/pats?api-version=7.1-preview.1"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Get-StoredPat {
    if (-not (Test-Path $EnvFile)) { return $null }
    $content = Get-Content $EnvFile -Raw
    if ($content -match '(?m)^AZDO_PAT=(.+)$') { return $Matches[1].Trim() }
    return $null
}

function Test-ExistingPat {
    param([string]$Pat)
    # Use the PAT itself as Basic auth (empty username) to call the PAT list API.
    # Returns the validTo string if functional, $null if the PAT is rejected.
    $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
    try {
        $response = Invoke-RestMethod `
            -Uri $PatApiUri `
            -Headers @{ Authorization = "Basic $encoded" } `
            -ErrorAction Stop

        # Find our named entry to retrieve the expiry date
        $entry = $response.value | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
        if ($entry -and $entry.validTo) { return $entry.validTo }

        # PAT is functional but no entry with our display name found — still valid
        return 'unknown'
    } catch {
        return $null
    }
}

function New-AdoPat {
    param([string]$BearerToken)
    $validTo = (Get-Date).AddDays($ValidityDays).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $body = @{
        displayName = $DisplayName
        scope       = $Scopes
        validTo     = $validTo
        allOrgs     = $false
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
        -Uri    $PatApiUri `
        -Method POST `
        -Headers @{
            Authorization  = "Bearer $BearerToken"
            'Content-Type' = 'application/json'
        } `
        -Body $body `
        -ErrorAction Stop

    if ($response.patTokenError -and $response.patTokenError -ne 'none') {
        throw "PAT creation failed: $($response.patTokenError). $($response.patTokenErrorMessage)"
    }
    return $response.patToken
}

function Set-PatInEnvFile {
    param([string]$Pat)

    $dir = Split-Path $EnvFile
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (Test-Path $EnvFile) {
        $content = Get-Content $EnvFile -Raw
        if ($content -match '(?m)^AZDO_PAT=') {
            $content = $content -replace '(?m)^AZDO_PAT=.*$', "AZDO_PAT=$Pat"
        } else {
            $content = $content.TrimEnd("`r", "`n") + "`nAZDO_PAT=$Pat`n"
        }
    } else {
        $content = "AZDO_PAT=$Pat`n"
    }

    Set-Content -Path $EnvFile -Value $content -Encoding UTF8 -NoNewline
}

# ── Main ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Agent Container Env Setup" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan
Write-Host ""

$needNewPat = $Force.IsPresent

if (-not $needNewPat) {
    $existingPat = Get-StoredPat

    if ($null -eq $existingPat) {
        Write-Host "No AZDO_PAT found in $EnvFile — will create one." -ForegroundColor Yellow
        $needNewPat = $true
    } else {
        Write-Host "Validating existing PAT..." -ForegroundColor Cyan
        $validTo = Test-ExistingPat $existingPat

        if ($null -eq $validTo) {
            Write-Host "Existing PAT is invalid or has been revoked — will create a new one." -ForegroundColor Yellow
            $needNewPat = $true
        } elseif ($validTo -eq 'unknown') {
            Write-Host "PAT is functional (expiry unknown — display name mismatch)." -ForegroundColor Green
            Write-Host "Run with -Force to replace it with a fresh named token." -ForegroundColor Yellow
        } else {
            $expiryDate = [datetime]::Parse($validTo)
            $daysLeft   = [math]::Floor(($expiryDate.ToUniversalTime() - (Get-Date).ToUniversalTime()).TotalDays)

            if ($daysLeft -le $RefreshDays) {
                Write-Host "PAT expires in $daysLeft day(s) ($($expiryDate.ToString('yyyy-MM-dd'))) — refreshing." -ForegroundColor Yellow
                $needNewPat = $true
            } else {
                Write-Host "PAT is valid — expires $($expiryDate.ToString('yyyy-MM-dd')) ($daysLeft days remaining)." -ForegroundColor Green
            }
        }
    }
}

if ($needNewPat) {
    Write-Host ""
    Write-Host "Fetching Azure access token..." -ForegroundColor Cyan
    $bearerToken = az account get-access-token `
        --resource 499b84ac-1321-427f-aa17-267ca6975798 `
        --query accessToken -o tsv 2>&1

    if ($LASTEXITCODE -ne 0 -or -not $bearerToken) {
        throw "Failed to get Azure access token. Are you signed in? Run: az login"
    }
    $bearerToken = $bearerToken.Trim()

    Write-Host "Creating PAT '$DisplayName' (valid $ValidityDays days)..." -ForegroundColor Cyan
    $patToken = New-AdoPat $bearerToken
    Set-PatInEnvFile $patToken.token

    Write-Host ""
    Write-Host "Done." -ForegroundColor Green
    Write-Host "  Env file     : $EnvFile" -ForegroundColor Green
    Write-Host "  Display name : $($patToken.displayName)" -ForegroundColor Green
    if ($patToken.validTo) {
        $expiryDate = [datetime]::Parse($patToken.validTo)
        Write-Host "  Expires      : $($expiryDate.ToString('yyyy-MM-dd'))" -ForegroundColor Green
    }
}

Write-Host ""
