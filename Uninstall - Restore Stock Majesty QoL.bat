@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall-All.ps1"
echo.
pause

