@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Restore-UnlockAllQuests.ps1"
echo.
pause
