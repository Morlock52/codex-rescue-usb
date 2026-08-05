@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Sta -File "%~dp0Open-CodexRescueDashboard.ps1" %*
set "CODEX_RESCUE_EXIT=%ERRORLEVEL%"
if not "%CODEX_RESCUE_EXIT%"=="0" pause
exit /b %CODEX_RESCUE_EXIT%
