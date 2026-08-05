@echo off
setlocal
echo.
echo Evidence collection is read-only. It will not repair or unlock a drive.
set /p OUTDRIVE=Enter a removable destination drive letter, for example E:
if "%OUTDRIVE%"=="" goto :cancelled
set OUTDRIVE=%OUTDRIVE:~0,1%
if /I "%OUTDRIVE%"=="X" goto :invalid
if not exist "%OUTDRIVE%:\" goto :invalid
set OUT=%OUTDRIVE%:\CodexRescueEvidence
mkdir "%OUT%" 2>nul
diskpart /s X:\Rescue\diskpart-list.txt > "%OUT%\diskpart.txt"
manage-bde -status > "%OUT%\bitlocker-status.txt" 2>&1
bcdedit /enum all > "%OUT%\bcd.txt" 2>&1
wevtutil el > "%OUT%\event-log-index.txt" 2>&1
driverquery /v > "%OUT%\drivers.txt" 2>&1
ipconfig /all > "%OUT%\network.txt" 2>&1
echo Evidence captured in %OUT%
goto :end

:invalid
echo A valid removable destination drive was not selected. No evidence was written.
goto :end

:cancelled
echo No destination was selected. No evidence was written.

:end
endlocal
