@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Restore-QuestMapPan.ps1"
echo.
pause
