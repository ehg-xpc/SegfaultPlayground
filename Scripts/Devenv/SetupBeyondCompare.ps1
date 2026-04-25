# Resolve Beyond Compare path from Scoop
$bcRoot = Join-Path $env:Scoop 'apps\beyondcompare\current'
$bcomp  = Join-Path $bcRoot 'BComp.exe'

if (-not (Test-Path $bcomp)) {
    throw "BComp.exe not found at $bcomp. Is Beyond Compare installed via Scoop?"
}

# Set BCRoot environment variable
[Environment]::SetEnvironmentVariable("BCRoot", $bcRoot, "User")
$env:BCRoot = $bcRoot
Write-Host "Set BCRoot environment variable to: $bcRoot" -ForegroundColor Green

# Configure Git
git config --global diff.tool bc3
git config --global difftool.bc3.path "$bcomp"

git config --global merge.tool bc3
git config --global mergetool.bc3.path "$bcomp"