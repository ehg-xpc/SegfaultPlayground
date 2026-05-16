' VBScript shim that launches KeepAlive.ps1 with SW_HIDE (window style 0)
' at the CreateProcess level, preventing even the brief pwsh.exe flash that
' occurs when Task Scheduler spawns pwsh.exe with -WindowStyle Hidden.

Dim sh, script
Set sh = CreateObject("WScript.Shell")

' __FILE__ is not available in VBScript; resolve relative to this script's folder.
script = Replace(WScript.ScriptFullName, WScript.ScriptName, "KeepAlive.ps1")

' Window style 0 = SW_HIDE. bWaitOnReturn = False (fire-and-forget).
sh.Run "pwsh.exe -NonInteractive -ExecutionPolicy Bypass -File """ & script & """", 0, False
