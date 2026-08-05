@echo off
setlocal EnableExtensions EnableDelayedExpansion
echo.
echo Evidence collection is read-only. It will not repair or unlock a drive.
echo Searching for one prepared destination containing CODEX_EVIDENCE.DEST.
set "DEST_COUNT=0"
set "OUTDRIVE="
for %%D in (D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%D:\CODEX_EVIDENCE.DEST" (
        set /a DEST_COUNT+=1
        set "OUTDRIVE=%%D"
    )
)
if "!DEST_COUNT!"=="0" goto :unprepared
if not "!DEST_COUNT!"=="1" goto :ambiguous
set "OUT=!OUTDRIVE!:\CodexRescueEvidence"
if exist "!OUT!" goto :existing
mkdir "!OUT!" 2>nul
if errorlevel 1 goto :writefailed
diskpart /s X:\Rescue\diskpart-list.txt > "!OUT!\diskpart.txt"
manage-bde -status > "!OUT!\bitlocker-status.txt" 2>&1
bcdedit /enum all > "!OUT!\bcd.txt" 2>&1
wevtutil el > "!OUT!\event-log-index.txt" 2>&1
dism /Online /Get-Drivers /Format:Table > "!OUT!\drivers.txt" 2>&1
ipconfig /all > "!OUT!\network.txt" 2>&1
(
    echo Codex Rescue evidence package
    echo Collection mode: read-only diagnostics
    echo Destination drive: !OUTDRIVE!:
) > "!OUT!\README.txt"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File X:\Rescue\New-EvidenceManifest.ps1 -OutputDirectory "!OUT!"
if errorlevel 1 goto :manifestfailed
echo Evidence captured in !OUT!
goto :end

:unprepared
echo No prepared destination was found. No evidence was written.
goto :end

:ambiguous
echo More than one prepared destination was found. Remove all but one and try again.
echo No evidence was written.
goto :end

:existing
echo !OUT! already exists. Move or rename it before collecting again. No evidence was overwritten.
goto :end

:writefailed
echo The evidence directory could not be created. No diagnostic commands were run.
goto :end

:manifestfailed
echo Evidence files were captured, but the package is incomplete because its manifest or checksums failed.
echo Review !OUT! before sharing it. No existing package was overwritten.
goto :end

:end
endlocal
