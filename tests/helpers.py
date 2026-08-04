from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from codex_rescue.models import (  # noqa: E402
    Approval,
    BitLockerState,
    EvidenceSnapshot,
    RepairProposal,
    RiskLevel,
    TargetFingerprint,
)


def target(**overrides: str | None) -> TargetFingerprint:
    values: dict[str, str | None] = {
        "disk_serial": "NVME-DEMO-001",
        "partition_guid": "11111111-2222-3333-4444-555555555555",
        "filesystem_uuid": "AAAA-BBBB",
        "windows_path": "\\Windows",
        "bitlocker_key_id": None,
    }
    values.update(overrides)
    return TargetFingerprint(**values)


def evidence(**overrides: object) -> EvidenceSnapshot:
    values: dict[str, object] = {
        "scenario_id": "boot-loop",
        "title": "Windows boot configuration is damaged",
        "category": "pc-wont-boot",
        "target": target(),
        "smart_status": "healthy",
        "read_errors": 0,
        "bitlocker_state": BitLockerState.NOT_ENCRYPTED,
        "bcd_valid": False,
        "boot_files_present": True,
        "network_available": False,
        "notes": ("Fixture evidence only",),
    }
    values.update(overrides)
    return EvidenceSnapshot(**values)


def proposal(**overrides: object) -> RepairProposal:
    values: dict[str, object] = {
        "proposal_id": "proposal-001",
        "operation": "simulate.bcd.rebuild",
        "target": target(),
        "risk": RiskLevel.REVERSIBLE,
        "summary": "Simulate rebuilding the BCD store",
        "rollback_required": True,
        "rollback_artifact_ready": True,
        "contains_secret": False,
    }
    values.update(overrides)
    return RepairProposal(**values)


def approval(item: RepairProposal | None = None) -> Approval:
    approved = item or proposal()
    return Approval(
        proposal_id=approved.proposal_id,
        target_digest=approved.target.digest(),
        approved_by="local-user",
    )
