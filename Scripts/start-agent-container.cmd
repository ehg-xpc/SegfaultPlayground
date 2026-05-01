@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0Internal\start-agent-container.ps1" %*
