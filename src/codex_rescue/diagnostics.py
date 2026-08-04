from __future__ import annotations

from codex_rescue.models import (
    BitLockerState,
    EvidenceSnapshot,
    Finding,
    FindingSeverity,
    Operation,
    StorageHealth,
)


def analyze(evidence: EvidenceSnapshot) -> tuple[Finding, ...]:
    """Return deterministic findings, ordered by the strongest safety gate."""
    if evidence.smart_status != StorageHealth.HEALTHY or evidence.read_errors > 0:
        return (
            Finding(
                code="storage.failing",
                severity=FindingSeverity.CRITICAL,
                title="Storage may be failing",
                summary=(
                    "Ordinary repair is blocked. Image the source to separate "
                    "storage before attempting filesystem or boot changes."
                ),
                blocks_writes=True,
                confidence=0.98,
                uncertainty="Physical media condition requires a separate imaging assessment.",
            ),
        )

    if evidence.bitlocker_state == BitLockerState.LOCKED:
        return (
            Finding(
                code="bitlocker.locked",
                severity=FindingSeverity.BLOCKED,
                title="BitLocker volume is locked",
                summary=(
                    "Continue only through the authorized local WinPE unlock "
                    "workflow. Recovery material is never accepted by this API."
                ),
                blocks_writes=True,
                confidence=1.0,
                uncertainty="The recovery credential and authorization are intentionally unknown.",
            ),
        )

    if not evidence.boot_files_present:
        return (
            Finding(
                code="boot.files-missing",
                severity=FindingSeverity.ERROR,
                title="Required boot files are missing",
                summary="Collect installation media evidence before proposing repair.",
                blocks_writes=True,
                confidence=0.9,
                uncertainty="The fixture does not establish why the boot files are absent.",
            ),
        )

    if not evidence.bcd_valid:
        return (
            Finding(
                code="boot.bcd-invalid",
                severity=FindingSeverity.ERROR,
                title="Windows boot configuration is invalid",
                summary=(
                    "The fixture can demonstrate BCD backup, approval, simulated "
                    "rebuild, and independent verification."
                ),
                blocks_writes=False,
                confidence=0.93,
                uncertainty="Fixture evidence cannot prove the state of a physical PC.",
                suggested_operation=Operation.SIMULATE_BCD_REBUILD,
            ),
        )

    return (
        Finding(
            code="system.no-known-fault",
            severity=FindingSeverity.INFO,
            title="No supported fault detected",
            summary="The fixture evidence does not match a version-one repair rule.",
            blocks_writes=False,
            confidence=0.75,
            uncertainty="Unsupported faults may still exist outside the fixture evidence.",
        ),
    )
