# Display colorful ASCII art banner with animated reveal
# Animations are skipped if the banner was already shown in the past 12 hours.

$line1 = "░█▀▀░█▀▀░█▀▀░█▀▀░█▀█░█░█░█░░░▀█▀░░░█▀█░█░░░█▀█░█░█░█▀▀░█▀▄░█▀█░█░█░█▀█░█▀▄"
$line2 = "░▀▀█░█▀▀░█░█░█▀▀░█▀█░█░█░█░░░░█░░░░█▀▀░█░░░█▀█░░█░░█░█░█▀▄░█░█░█░█░█░█░█░█"
$line3 = "░▀▀▀░▀▀▀░▀▀▀░▀░░░▀░▀░▀▀▀░▀▀▀░░▀░░░░▀░░░▀▀▀░▀░▀░░▀░░▀▀▀░▀░▀░▀▀▀░▀▀▀░▀░▀░▀▀░"

# Determine whether to animate based on a timestamp file
$stampFile = Join-Path $env:TEMP "devenv-banner-stamp"
$animate = $true

if (Test-Path $stampFile) {
    $lastShown = (Get-Item $stampFile).LastWriteTime
    if (([DateTime]::Now - $lastShown).TotalHours -lt 12) {
        $animate = $false
    }
}

if ($animate) {
    # Update the timestamp
    [IO.File]::WriteAllText($stampFile, "")

    $ESC = [char]27
    $up3 = "$ESC[3A"
    $len = $line1.Length
    $step = 4

    function Write-Banner($c1, $c2, $c3) {
        Write-Host $up3 -NoNewline
        Write-Host $line1 -ForegroundColor $c1
        Write-Host $line2 -ForegroundColor $c2
        Write-Host $line3 -ForegroundColor $c3
    }

    # Phase 1: left-to-right reveal across all 3 lines simultaneously
    Write-Host ""
    for ($i = $step; $i -le ($len + $step - 1); $i += $step) {
        if ($i -gt $step) { Write-Host $up3 -NoNewline }
        $end = [Math]::Min($i, $len)
        $pad = ' ' * ($len - $end)
        Write-Host ($line1.Substring(0, $end) + $pad) -ForegroundColor DarkGray
        Write-Host ($line2.Substring(0, $end) + $pad) -ForegroundColor DarkGray
        Write-Host ($line3.Substring(0, $end) + $pad) -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 12
    }

    # Phase 2: two white flashes over the dim banner
    Start-Sleep -Milliseconds 60
    Write-Banner White     White     White
    Start-Sleep -Milliseconds 50
    Write-Banner DarkGray  DarkGray  DarkGray
    Start-Sleep -Milliseconds 80
    Write-Banner White     White     White
    Start-Sleep -Milliseconds 50
    Write-Banner DarkGray  DarkGray  DarkGray

    # Phase 3: color bleed top to bottom
    Start-Sleep -Milliseconds 100
    Write-Banner DarkRed   DarkGray  DarkGray
    Start-Sleep -Milliseconds 110
    Write-Banner Red       DarkRed   DarkGray
    Start-Sleep -Milliseconds 110
    Write-Banner Red       DarkRed   DarkMagenta

    # Phase 4: settle
    Write-Host ""
} else {
    # Static banner (no animation)
    Write-Host ""
    Write-Host $line1 -ForegroundColor Red
    Write-Host $line2 -ForegroundColor DarkRed
    Write-Host $line3 -ForegroundColor DarkMagenta
    Write-Host ""
}
