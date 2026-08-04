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
    Operation,
    RepairProposal,
    RiskLevel,
    RollbackArtifact,
    StorageHealth,
    TargetFingerprint,
    utc_now,
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
        "category": "windows-crashes-loops",
        "target": target(),
        "smart_status": StorageHealth.HEALTHY,
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
        "operation": Operation.SIMULATE_BCD_REBUILD,
        "target": target(),
        "risk": RiskLevel.READ_ONLY,
        "summary": "Simulate rebuilding the BCD store",
        "reason": "BCD validation failed",
        "simulated_change": "BCD fixture state becomes valid",
        "host_impact": "No host impact",
        "inputs": ("fixture evidence",),
        "preconditions": ("healthy storage",),
        "permitted_commands": (),
        "expected_outputs": ("typed receipt",),
        "rollback_artifact": RollbackArtifact(
            artifact_id="rollback-test-001",
            scenario_id="boot-loop",
            kind="fixture-bcd-backup",
            target_digest=target().digest(),
            content_digest="9" * 64,
            restore_tested=True,
            verified_at="2026-08-04T00:00:00Z",
        ),
        "stop_conditions": ("target changes",),
        "verification_plan": ("load independent post-action fixture",),
    }
    values.update(overrides)
    return RepairProposal(**values)


def approval(item: RepairProposal | None = None) -> Approval:
    approved = item or proposal()
    return Approval(
        fingerprint=approved.approval_fingerprint(),
        approved_by="local-user",
        approved_at=utc_now(),
    )
