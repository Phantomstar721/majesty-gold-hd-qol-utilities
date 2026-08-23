@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Restore-LowerTrackingWindow.ps1"
echo.
pause
