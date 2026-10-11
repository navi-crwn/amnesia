@echo off
rem Amnesia: collect a log for troubleshooting (saved to amnesia-log.txt in your Keep folder, nothing is sent)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect-log.ps1"
pause
