@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0start-agent-container.ps1" %*
