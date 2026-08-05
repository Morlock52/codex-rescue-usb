@echo off
setlocal EnableExtensions EnableDelayedExpansion

echo.
echo Authorized BitLocker recovery-key unlock
echo This command never asks Codex for a key and never writes a key to logs or evidence.

set "TARGET=%~1"
if "!TARGET!"=="" goto :usage
if not "!TARGET:~1!"=="" goto :usage

set "VALID_TARGET="
for %%D in (D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if /I "!TARGET!"=="%%D" set "VALID_TARGET=1"
)
if not defined VALID_TARGET goto :usage

set "KEYDRIVE="
set "KEYDRIVE_COUNT=0"
for %%D in (D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if /I not "!TARGET!"=="%%D" if exist "%%D:\CODEX_BITLOCKER.KEY" (
        set /a KEYDRIVE_COUNT+=1
        set "KEYDRIVE=%%D"
    )
)
if "!KEYDRIVE_COUNT!"=="0" goto :unprepared
if not "!KEYDRIVE_COUNT!"=="1" goto :ambiguousdrive

set "KEYFILE="
set "KEYFILE_COUNT=0"
for /F "usebackq delims=" %%K in (`dir /b /s /a:-d "!KEYDRIVE!:\*.bek" 2^>nul`) do (
    set /a KEYFILE_COUNT+=1
    set "KEYFILE=%%K"
)
if "!KEYFILE_COUNT!"=="0" goto :nokey
if not "!KEYFILE_COUNT!"=="1" goto :ambiguouskey

echo Target volume: !TARGET!:
echo Prepared external key drive: !KEYDRIVE!:
echo Exactly one recovery-key file was found. Its name and contents will not be displayed.
manage-bde -status "!TARGET!:"
echo The status display above is informational. Minimal WinPE may return a system-device warning even for a visible locked data volume.

set "CONFIRM="
set /P "CONFIRM=Type UNLOCK !TARGET!: to authorize this exact volume, or press Enter to cancel: "
if /I not "!CONFIRM!"=="UNLOCK !TARGET!:" goto :cancelled
set "CONFIRM="

manage-bde -unlock "!TARGET!:" -RecoveryKey "!KEYFILE!" >nul 2>&1
set "RESULT=!ERRORLEVEL!"
set "KEYFILE="
if not "!RESULT!"=="0" goto :unlockfailed

echo Unlock command succeeded. Verifying the selected volume state:
manage-bde -status "!TARGET!:"
pushd "!TARGET!:\" 2>nul
if errorlevel 1 goto :verifyfailed
popd
echo The selected volume root is accessible after the unlock.
echo BitLocker unlock completed for !TARGET!: using the prepared local recovery-key file.
exit /b 0

:usage
echo Usage: X:\Rescue\Unlock-BitLockerWithRecoveryKey.cmd D
echo Choose one authorized data-volume letter from D through W, Y, or Z. C and X are blocked.
exit /b 2

:unprepared
echo No separate drive containing CODEX_BITLOCKER.KEY was found. Nothing was unlocked.
exit /b 3

:ambiguousdrive
echo More than one prepared key drive was found. Remove all but one. Nothing was unlocked.
exit /b 4

:nokey
echo The prepared key drive contains no .bek recovery-key file. Nothing was unlocked.
exit /b 5

:ambiguouskey
echo The prepared key drive contains more than one .bek file. Keep only the key for the selected volume.
echo Nothing was unlocked.
exit /b 6

:cancelled
set "CONFIRM="
set "KEYFILE="
echo Authorization was not entered exactly. Nothing was unlocked.
exit /b 7

:unlockfailed
echo BitLocker rejected the prepared recovery key or the selected volume. The volume remains protected.
exit /b 8

:verifyfailed
echo The unlock command returned success, but the selected volume root is not accessible.
exit /b 9
