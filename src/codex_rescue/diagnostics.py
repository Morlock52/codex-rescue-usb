from __future__ import annotations

from codex_rescue.models import BitLockerState, EvidenceSnapshot, Finding


def analyze(evidence: EvidenceSnapshot) -> tuple[Finding, ...]:
    """Return deterministic findings, ordered by the strongest safety gate."""
    if evidence.smart_status != "healthy" or evidence.read_errors > 0:
        return (
            Finding(
                code="storage.failing",
                severity="critical",
                title="Storage may be failing",
                summary=(
                    "Ordinary repair is blocked. Image the source to separate "
                    "storage before attempting filesystem or boot changes."
                ),
                blocks_writes=True,
            ),
        )

    if evidence.bitlocker_state == BitLockerState.LOCKED:
        return (
            Finding(
                code="bitlocker.locked",
                severity="blocked",
                title="BitLocker volume is locked",
                summary=(
                    "Continue only through the authorized local WinPE unlock "
                    "workflow. Recovery material is never accepted by this API."
                ),
                blocks_writes=True,
            ),
        )

    if not evidence.boot_files_present:
        return (
            Finding(
                code="boot.files-missing",
                severity="error",
                title="Required boot files are missing",
                summary="Collect installation media evidence before proposing repair.",
                blocks_writes=True,
            ),
        )

    if not evidence.bcd_valid:
        return (
            Finding(
                code="boot.bcd-invalid",
                severity="error",
                title="Windows boot configuration is invalid",
                summary=(
                    "The fixture can demonstrate BCD backup, approval, simulated "
                    "rebuild, and independent verification."
                ),
                blocks_writes=False,
                suggested_operation="simulate.bcd.rebuild",
            ),
        )

    return (
        Finding(
            code="system.no-known-fault",
            severity="info",
            title="No supported fault detected",
            summary="The fixture evidence does not match a version-one repair rule.",
            blocks_writes=False,
        ),
    )
