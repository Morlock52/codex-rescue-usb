from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from enum import StrEnum


def canonical_digest(value: object) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


class RiskLevel(StrEnum):
    READ_ONLY = "read-only"
    REVERSIBLE = "reversible"
    CONDITIONALLY_REVERSIBLE = "conditionally-reversible"
    IRREVERSIBLE = "irreversible"


class BitLockerState(StrEnum):
    NOT_ENCRYPTED = "not-encrypted"
    LOCKED = "locked"
    UNLOCKED = "unlocked"


class StorageHealth(StrEnum):
    HEALTHY = "healthy"
    WARNING = "warning"
    FAILING = "failing"


class FindingSeverity(StrEnum):
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    BLOCKED = "blocked"
    CRITICAL = "critical"


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

    def canonical(self) -> dict[str, str | None]:
        return {
            "disk_serial": self.disk_serial.strip().upper(),
            "partition_guid": self.partition_guid.strip().lower(),
            "filesystem_uuid": self.filesystem_uuid.strip().upper(),
            "windows_path": self.windows_path.strip().replace("/", "\\").lower(),
            "bitlocker_key_id": (
                self.bitlocker_key_id.strip().upper()
                if self.bitlocker_key_id is not None
                else None
            ),
        }

    def digest(self) -> str:
        return canonical_digest(self.canonical())

    def is_unambiguous(self) -> bool:
        canonical = self.canonical()
        return all(
            canonical[key]
            for key in ("disk_serial", "partition_guid", "filesystem_uuid", "windows_path")
        )


@dataclass(frozen=True)
class EvidenceSnapshot:
    scenario_id: str
    title: str
    category: str
    target: TargetFingerprint
    smart_status: StorageHealth
    read_errors: int
    bitlocker_state: BitLockerState
    bcd_valid: bool
    boot_files_present: bool
    network_available: bool
    notes: tuple[str, ...] = ()


@dataclass(frozen=True)
class Finding:
    code: str
    severity: FindingSeverity
    title: str
    summary: str
    blocks_writes: bool
    confidence: float
    uncertainty: str
    suggested_operation: Operation | None = None

    def __post_init__(self) -> None:
        if not 0.0 <= self.confidence <= 1.0:
            raise ValueError("finding confidence must be between zero and one")


@dataclass(frozen=True)
class RollbackArtifact:
    artifact_id: str
    scenario_id: str
    kind: str
    target_digest: str
    content_digest: str
    restore_tested: bool
    verified_at: str


@dataclass(frozen=True)
class ApprovalFingerprint:
    proposal_id: str
    proposal_digest: str
    target_digest: str

    def digest(self) -> str:
        return canonical_digest(asdict(self))


@dataclass(frozen=True)
class RepairProposal:
    proposal_id: str
    operation: Operation
    target: TargetFingerprint
    risk: RiskLevel
    summary: str
    reason: str
    simulated_change: str
    host_impact: str
    inputs: tuple[str, ...]
    preconditions: tuple[str, ...]
    permitted_commands: tuple[str, ...]
    expected_outputs: tuple[str, ...]
    rollback_artifact: RollbackArtifact
    stop_conditions: tuple[str, ...]
    verification_plan: tuple[str, ...]

    def digest(self) -> str:
        return canonical_digest(asdict(self))

    def approval_fingerprint(self) -> ApprovalFingerprint:
        return ApprovalFingerprint(
            proposal_id=self.proposal_id,
            proposal_digest=self.digest(),
            target_digest=self.target.digest(),
        )


@dataclass(frozen=True)
class Approval:
    fingerprint: ApprovalFingerprint
    approved_by: str
    approved_at: str


@dataclass(frozen=True)
class PolicyDecision:
    allowed: bool
    reasons: tuple[str, ...] = ()


@dataclass(frozen=True)
class SimulationReceipt:
    operation: Operation
    proposal_digest: str
    approval_fingerprint_digest: str
    target_digest: str
    result_code: str
    simulated_change: str
    host_impact: str
    produced_at: str
    content_digest: str

    @classmethod
    def create(
        cls,
        proposal: RepairProposal,
        approval: Approval,
        result_code: str,
    ) -> SimulationReceipt:
        values = {
            "operation": proposal.operation,
            "proposal_digest": proposal.digest(),
            "approval_fingerprint_digest": approval.fingerprint.digest(),
            "target_digest": proposal.target.digest(),
            "result_code": result_code,
            "simulated_change": proposal.simulated_change,
            "host_impact": proposal.host_impact,
            "produced_at": utc_now(),
        }
        return cls(**values, content_digest=canonical_digest(values))

    def verify_digest(self) -> bool:
        values = asdict(self)
        content_digest = values.pop("content_digest")
        return content_digest == canonical_digest(values)


@dataclass(frozen=True)
class ExecutionResult:
    success: bool
    message: str
    receipt: SimulationReceipt | None


@dataclass(frozen=True)
class PostActionEvidence:
    source: str
    source_fixture_digest: str
    scenario_id: str
    operation: Operation
    target_digest: str
    bcd_valid: bool
    rollback_artifact_digest: str
    observed_at: str


@dataclass(frozen=True)
class VerificationResult:
    passed: bool
    message: str


@dataclass(frozen=True)
class CaseEvent:
    case_id: str
    sequence: int
    kind: str
    message: str
    payload_json: str
    occurred_at: str
    previous_hash: str
    event_hash: str

    @classmethod
    def create(
        cls,
        case_id: str,
        sequence: int,
        kind: str,
        message: str,
        payload: object,
        previous_hash: str,
    ) -> CaseEvent:
        values = {
            "case_id": case_id,
            "sequence": sequence,
            "kind": kind,
            "message": message,
            "payload_json": json.dumps(
                payload,
                sort_keys=True,
                separators=(",", ":"),
            ),
            "occurred_at": utc_now(),
            "previous_hash": previous_hash,
        }
        return cls(**values, event_hash=canonical_digest(values))

    def verify_hash(self) -> bool:
        values = asdict(self)
        event_hash = values.pop("event_hash")
        return event_hash == canonical_digest(values)

    def payload(self) -> object:
        return json.loads(self.payload_json)


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
    event_log: tuple[CaseEvent, ...] = field(default_factory=tuple)
