@echo off
setlocal
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\Install-SpeedrunTimer.ps1"
echo.
pause
popd
