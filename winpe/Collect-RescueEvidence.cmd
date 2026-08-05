@echo off
setlocal
set OUT=%~dp0evidence
mkdir "%OUT%" 2>nul
diskpart /s X:\Rescue\diskpart-list.txt > "%OUT%\diskpart.txt"
manage-bde -status > "%OUT%\bitlocker-status.txt" 2>&1
bcdedit /enum all > "%OUT%\bcd.txt" 2>&1
wevtutil el > "%OUT%\event-log-index.txt" 2>&1
driverquery /v > "%OUT%\drivers.txt" 2>&1
ipconfig /all > "%OUT%\network.txt" 2>&1
echo Evidence captured in %OUT%
endlocal
