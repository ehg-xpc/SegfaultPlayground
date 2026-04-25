@echo off
powershell -NoProfile -Command "Start-Process pwsh -ArgumentList '-NoExit','-ExecutionPolicy','Bypass','-File','%~dp0Devenv\SetupDevice.ps1' -Verb RunAs"
