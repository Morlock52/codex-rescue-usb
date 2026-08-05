@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Open-PhysicalUsbReadinessGui.ps1" %*
set "CODEX_EXIT=%ERRORLEVEL%"
endlocal & exit /b %CODEX_EXIT%
