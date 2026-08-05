@echo off
setlocal EnableExtensions EnableDelayedExpansion
echo.
echo Evidence collection is read-only. It will not repair or unlock a drive.
echo Searching for one prepared destination containing CODEX_EVIDENCE.DEST.
set "DEST_COUNT=0"
set "INVALID_MARKER_COUNT=0"
set "OUTDRIVE="
for %%D in (D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%D:\CODEX_EVIDENCE.DEST" (
        if exist "%%D:\CODEX_EVIDENCE.DEST\" (
            set /a INVALID_MARKER_COUNT+=1
        ) else (
            set /a DEST_COUNT+=1
            set "OUTDRIVE=%%D"
        )
    )
)
if not "!INVALID_MARKER_COUNT!"=="0" goto :invalidmarker
if "!DEST_COUNT!"=="0" goto :unprepared
if not "!DEST_COUNT!"=="1" goto :ambiguous
set "OUT=!OUTDRIVE!:\CodexRescueEvidence"
if exist "!OUT!" goto :existing
echo.
echo Prepared evidence destination:
vol !OUTDRIVE!:
echo This operation writes a new evidence package to !OUT!.
set "CONFIRM="
set /p "CONFIRM=Type COLLECT TO !OUTDRIVE!: and press Enter: "
if /I not "!CONFIRM!"=="COLLECT TO !OUTDRIVE!:" goto :notconfirmed
set "RECHECK_COUNT=0"
set "RECHECK_INVALID=0"
set "RECHECK_DRIVE="
for %%D in (D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%D:\CODEX_EVIDENCE.DEST" (
        if exist "%%D:\CODEX_EVIDENCE.DEST\" (
            set /a RECHECK_INVALID+=1
        ) else (
            set /a RECHECK_COUNT+=1
            set "RECHECK_DRIVE=%%D"
        )
    )
)
if not "!RECHECK_INVALID!"=="0" goto :destinationchanged
if not "!RECHECK_COUNT!"=="1" goto :destinationchanged
if /I not "!RECHECK_DRIVE!"=="!OUTDRIVE!" goto :destinationchanged
mkdir "!OUT!" 2>nul
if errorlevel 1 goto :writefailed
diskpart /s X:\Rescue\diskpart-list.txt > "!OUT!\diskpart.txt"
manage-bde -status > "!OUT!\bitlocker-status.txt" 2>&1
bcdedit /enum all > "!OUT!\bcd.txt" 2>&1
wevtutil el > "!OUT!\event-log-index.txt" 2>&1
dism /Online /Get-Drivers /Format:Table > "!OUT!\drivers.txt" 2>&1
ipconfig /all > "!OUT!\network.txt" 2>&1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File X:\Rescue\Collect-OfflineWindowsInventory.ps1 -OutputPath "!OUT!\windows-installations.json" -DestinationDriveLetter "!OUTDRIVE!"
if errorlevel 1 goto :inventoryfailed
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

:invalidmarker
echo CODEX_EVIDENCE.DEST must be an empty file, not a directory. No evidence was written.
goto :end

:ambiguous
echo More than one prepared destination was found. Remove all but one and try again.
echo No evidence was written.
goto :end

:existing
echo !OUT! already exists. Move or rename it before collecting again. No evidence was overwritten.
goto :end

:notconfirmed
echo The confirmation did not match. No evidence was written.
goto :end

:destinationchanged
echo The prepared destination changed after confirmation. No evidence was written.
goto :end

:writefailed
echo The evidence directory could not be created. No diagnostic commands were run.
goto :end

:manifestfailed
echo Evidence files were captured, but the package is incomplete because its manifest or checksums failed.
echo Review !OUT! before sharing it. No existing package was overwritten.
goto :end

:inventoryfailed
echo The basic evidence files were captured, but the offline Windows inventory failed.
echo The package is incomplete and was not manifested. Review !OUT! before sharing it.
goto :end

:end
endlocal
