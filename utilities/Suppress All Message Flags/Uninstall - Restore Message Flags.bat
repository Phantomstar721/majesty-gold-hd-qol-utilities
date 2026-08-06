@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Restore-SuppressAllMessageFlags.ps1"
echo.
pause

