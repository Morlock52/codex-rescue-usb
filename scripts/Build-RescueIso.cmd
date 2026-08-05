@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-RescueIso.ps1" -Force
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo ISO build failed with exit code %RESULT%.
pause
exit /b %RESULT%
