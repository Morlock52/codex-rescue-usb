from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from dataclasses import asdict, dataclass, field
from enum import StrEnum
from types import MappingProxyType


class RiskLevel(StrEnum):
    READ_ONLY = "read-only"
    REVERSIBLE = "reversible"
    CONDITIONALLY_REVERSIBLE = "conditionally-reversible"
    IRREVERSIBLE = "irreversible"


class BitLockerState(StrEnum):
    NOT_ENCRYPTED = "not-encrypted"
    LOCKED = "locked"
    UNLOCKED = "unlocked"


class Operation(StrEnum):
    SIMULATE_BCD_REBUILD = "simulate.bcd.rebuild"


class CaseStage(StrEnum):
    BLOCKED = "blocked"
    DIAGNOSED = "diagnosed"
    PROPOSED = "proposed"
    APPROVED = "approved"
    VERIFIED = "verified"
    FAILED = "failed"


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

    def is_unambiguous(self) -> bool:
        required = (
            self.disk_serial,
            self.partition_guid,
            self.filesystem_uuid,
            self.windows_path,
        )
        return all(value.strip() for value in required)


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
    confidence: float
    uncertainty: str
    suggested_operation: Operation | None = None


@dataclass(frozen=True)
class RepairProposal:
    proposal_id: str
    operation: Operation
    target: TargetFingerprint
    risk: RiskLevel
    summary: str
    rollback_required: bool
    rollback_artifact_ready: bool
    contains_secret: bool = False

    def receipt_digest(self) -> str:
        payload = json.dumps(
            {
                "operation": self.operation,
                "proposal_id": self.proposal_id,
                "target_digest": self.target.digest(),
            },
            sort_keys=True,
            separators=(",", ":"),
        )
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()


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
    output: Mapping[str, str | bool]

    def __post_init__(self) -> None:
        object.__setattr__(self, "output", MappingProxyType(dict(self.output)))


@dataclass(frozen=True)
class PostActionEvidence:
    source: str
    target_digest: str
    bcd_valid: bool
    rollback_artifact_present: bool


@dataclass(frozen=True)
class VerificationResult:
    passed: bool
    message: str


@dataclass(frozen=True)
class CaseRecord:
    case_id: str
    evidence: EvidenceSnapshot
    findings: tuple[Finding, ...]
    stage: CaseStage
    proposal: RepairProposal | None = None
    approval: Approval | None = None
    execution: ExecutionResult | None = None
    post_action_evidence: PostActionEvidence | None = None
    verification: VerificationResult | None = None
    event_log: tuple[str, ...] = field(default_factory=tuple)
