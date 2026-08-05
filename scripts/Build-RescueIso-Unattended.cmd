@echo off
setlocal
set "OUTPUT=%~dp0..\dist"
if not exist "%OUTPUT%" mkdir "%OUTPUT%"
set "LOG=%OUTPUT%\Build-RescueIso.log"
set "RESULT_FILE=%OUTPUT%\Build-RescueIso.exitcode"

if exist "%RESULT_FILE%" del /q "%RESULT_FILE%"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-RescueIso.ps1" -Force > "%LOG%" 2>&1
set "RESULT=%ERRORLEVEL%"
> "%RESULT_FILE%" echo %RESULT%
exit /b %RESULT%
