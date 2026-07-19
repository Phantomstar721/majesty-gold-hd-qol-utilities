@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-NoIntro.ps1"
echo.
pause
