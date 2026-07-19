@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-QuestMapPan.ps1"
echo.
pause
