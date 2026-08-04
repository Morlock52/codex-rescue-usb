from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass, field
from enum import StrEnum
from typing import Any


class RiskLevel(StrEnum):
    READ_ONLY = "read-only"
    REVERSIBLE = "reversible"
    CONDITIONALLY_REVERSIBLE = "conditionally-reversible"
    IRREVERSIBLE = "irreversible"


class BitLockerState(StrEnum):
    NOT_ENCRYPTED = "not-encrypted"
    LOCKED = "locked"
    UNLOCKED = "unlocked"


@dataclass(frozen=True)
class TargetFingerprint:
    disk_serial: str
    partition_guid: str
    filesystem_uuid: str
    windows_path: str
    bitlocker_key_id: str | None = None

    def digest(self) -> str:
        payload = json.dumps(asdict(self), sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class EvidenceSnapshot:
    scenario_id: str
    title: str
    category: str
    target: TargetFingerprint
    smart_status: str
    read_errors: int
    bitlocker_state: BitLockerState
    bcd_valid: bool
    boot_files_present: bool
    network_available: bool
    notes: tuple[str, ...] = ()


@dataclass(frozen=True)
class Finding:
    code: str
    severity: str
    title: str
    summary: str
    blocks_writes: bool
    suggested_operation: str | None = None


@dataclass(frozen=True)
class RepairProposal:
    proposal_id: str
    operation: str
    target: TargetFingerprint
    risk: RiskLevel
    summary: str
    rollback_required: bool
    rollback_artifact_ready: bool
    contains_secret: bool = False


@dataclass(frozen=True)
class Approval:
    proposal_id: str
    target_digest: str
    approved_by: str


@dataclass(frozen=True)
class PolicyDecision:
    allowed: bool
    reasons: tuple[str, ...] = ()


@dataclass(frozen=True)
class ExecutionResult:
    success: bool
    message: str
    output: dict[str, Any]


@dataclass(frozen=True)
class VerificationResult:
    passed: bool
    message: str


@dataclass
class CaseRecord:
    case_id: str
    evidence: EvidenceSnapshot
    findings: tuple[Finding, ...]
    stage: str
    proposal: RepairProposal | None = None
    approval: Approval | None = None
    execution: ExecutionResult | None = None
    verification: VerificationResult | None = None
    event_log: list[str] = field(default_factory=list)
