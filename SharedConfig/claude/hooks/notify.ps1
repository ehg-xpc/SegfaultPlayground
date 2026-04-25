# Notification hook -- fires when Claude Code needs user attention while running in background.
# Reads the notification payload from stdin and shows a Windows toast notification.
param()

$payload = $input | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $payload) { exit 0 }

$title   = if ($payload.title)   { $payload.title }   else { "Claude Code" }
$message = if ($payload.message) { $payload.message } else { "Agent needs your attention." }

# Use BurntToast if available, otherwise fall back to balloon tip via Shell.
if (Get-Command -Name New-BurntToastNotification -ErrorAction SilentlyContinue) {
    New-BurntToastNotification -Text $title, $message -Silent
} else {
    Add-Type -AssemblyName System.Windows.Forms
    $balloon = New-Object System.Windows.Forms.NotifyIcon
    $balloon.Icon = [System.Drawing.SystemIcons]::Information
    $balloon.BalloonTipTitle = $title
    $balloon.BalloonTipText  = $message
    $balloon.Visible = $true
    $balloon.ShowBalloonTip(4000)
    Start-Sleep -Milliseconds 4500
    $balloon.Dispose()
}
