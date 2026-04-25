$private = Join-Path $PSScriptRoot 'Private'
$public  = Join-Path $PSScriptRoot 'Public'

Get-ChildItem -Path $private -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

Get-ChildItem -Path $public -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }
