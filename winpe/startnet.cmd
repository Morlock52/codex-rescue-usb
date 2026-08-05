@echo off
wpeinit
title Codex Rescue Disk - Offline Recovery
echo.
echo Codex Rescue Disk boots read-only by default.
echo Evidence is written only to an operator-selected drive containing CODEX_EVIDENCE.DEST.
echo Recovery keys must never be saved in this environment or given to Codex.
echo.
echo Run X:\Rescue\Collect-RescueEvidence.cmd to collect offline evidence.
echo Run X:\Rescue\Unlock-BitLockerWithRecoveryKey.cmd D only for an authorized volume and prepared external key drive.
cmd
