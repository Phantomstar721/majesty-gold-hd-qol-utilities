@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Create-ReleaseZip.ps1"
echo.
pause
