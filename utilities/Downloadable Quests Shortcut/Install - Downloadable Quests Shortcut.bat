@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-DownloadableQuestShortcut.ps1"
echo.
pause
