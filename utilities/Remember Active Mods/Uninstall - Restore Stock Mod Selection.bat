@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Restore-ModPersistence.ps1"
echo.
pause
