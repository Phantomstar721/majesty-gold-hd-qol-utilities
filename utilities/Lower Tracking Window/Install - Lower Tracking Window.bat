@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-LowerTrackingWindow.ps1"
echo.
pause
