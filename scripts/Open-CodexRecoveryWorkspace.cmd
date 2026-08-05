@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Open-CodexRecoveryWorkspace.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo Codex recovery workspace did not start.
pause
exit /b %EXIT_CODE%
