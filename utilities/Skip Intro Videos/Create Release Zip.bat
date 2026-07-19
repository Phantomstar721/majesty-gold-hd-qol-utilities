@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Create-ReleaseZip.ps1"
echo.
pause
