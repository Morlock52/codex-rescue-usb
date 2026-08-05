@echo off
setlocal
set "DESTINATION=%USERPROFILE%\Documents\CodexRescue"

echo Codex Rescue USB source staging
echo Source: %~dp0..
echo Destination: %DESTINATION%
echo.

if exist "%DESTINATION%" (
  echo The destination already exists. No files were changed.
  echo Remove or rename that folder before staging a fresh source copy.
  exit /b 2
)

mkdir "%DESTINATION%" || exit /b 1
xcopy "%~dp0.." "%DESTINATION%" /E /I /H /K /Y
if errorlevel 1 (
  echo Source staging failed. Review the output above; the ISO build was not started.
  exit /b 1
)

echo.
echo Source staged successfully.
echo Open a PowerShell window in %DESTINATION% and run scripts\Build-RescueIso.ps1 -Force.
endlocal
