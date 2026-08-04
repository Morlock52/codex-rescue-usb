from __future__ import annotations

import re
from dataclasses import asdict

from codex_rescue.models import (
    Approval,
    BitLockerState,
    EvidenceSnapshot,
    PolicyDecision,
    RepairProposal,
    StorageHealth,
)
from codex_rescue.operations import OperationRegistry
from codex_rescue.secret_policy import SECRET_FIELD_TOKENS


_BITLOCKER_PASSWORD = re.compile(r"\b(?:\d{6}-){7}\d{6}\b")
_TOKEN_PATTERN = re.compile(
    r"\b(?:sk-|ghp_|github_pat_|bearer\s+)[A-Za-z0-9._-]{8,}",
    re.IGNORECASE,
)
def _contains_secret(value: object, key: str = "") -> bool:
    normalized = key.strip().lower().replace("-", "_")
    if normalized and any(token in normalized for token in SECRET_FIELD_TOKENS):
        return True
    if isinstance(value, dict):
        return any(_contains_secret(child, str(child_key)) for child_key, child in value.items())
    if isinstance(value, (list, tuple)):
        return any(_contains_secret(child) for child in value)
    if isinstance(value, str):
        return bool(_BITLOCKER_PASSWORD.search(value) or _TOKEN_PATTERN.search(value))
    return False


class SafetyBroker:
    """Validate complete structured proposals without executing commands."""

    def __init__(self, registry: OperationRegistry) -> None:
        self.registry = registry

    def evaluate(
        self,
        proposal: RepairProposal,
        evidence: EvidenceSnapshot,
        approval: Approval | None,
    ) -> PolicyDecision:
        reasons: list[str] = []
        handler = self.registry.get(proposal.operation)

        if handler is None:
            reasons.append("operation is not allowlisted")
        if not proposal.target.is_unambiguous():
            reasons.append("proposal target is ambiguous")
        if proposal.target.digest() != evidence.target.digest():
            reasons.append("proposal target does not match evidence target")
        if _contains_secret(asdict(proposal)):
            reasons.append("proposal contains secret material")
        if evidence.smart_status != StorageHealth.HEALTHY or evidence.read_errors > 0:
            reasons.append("storage health blocks ordinary repair")
        if evidence.bitlocker_state == BitLockerState.LOCKED:
            reasons.append("BitLocker volume is locked")

        if handler is not None:
            if proposal.risk != handler.policy.risk:
                reasons.append("proposal risk does not match operation policy")
            if not handler.supports(evidence):
                reasons.append("evidence does not support this operation")
            artifact = proposal.rollback_artifact
            if handler.policy.requires_rollback and not artifact.restore_tested:
                reasons.append("verified rollback artifact is required")
            if artifact.target_digest != proposal.target.digest():
                reasons.append("rollback artifact target does not match proposal target")
            if artifact.scenario_id != evidence.scenario_id:
                reasons.append("rollback artifact scenario does not match evidence")

        expected_fingerprint = proposal.approval_fingerprint()
        if approval is None:
            reasons.append("approval is required")
        elif approval.fingerprint != expected_fingerprint:
            reasons.append("approval fingerprint does not match complete proposal")

        return PolicyDecision(allowed=not reasons, reasons=tuple(reasons))
