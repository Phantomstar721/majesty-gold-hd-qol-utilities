@echo off
setlocal
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\Restore-SpeedrunTimer.ps1"
echo.
pause
popd
