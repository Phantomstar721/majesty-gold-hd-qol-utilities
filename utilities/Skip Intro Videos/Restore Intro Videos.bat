@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall-NoIntro.ps1"
echo.
pause
