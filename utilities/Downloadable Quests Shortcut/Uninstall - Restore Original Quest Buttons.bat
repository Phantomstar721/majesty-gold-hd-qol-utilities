@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Restore-CustomQuestButton.ps1"
echo.
pause
