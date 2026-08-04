from __future__ import annotations

from dataclasses import dataclass

from codex_rescue.models import (
    Approval,
    BitLockerState,
    EvidenceSnapshot,
    PolicyDecision,
    RepairProposal,
    RiskLevel,
    Operation,
)


@dataclass(frozen=True)
class OperationPolicy:
    risk: RiskLevel
    requires_rollback: bool


class SafetyBroker:
    """Validate structured proposals without executing commands."""

    _catalog = {
        Operation.SIMULATE_BCD_REBUILD: OperationPolicy(
            risk=RiskLevel.REVERSIBLE,
            requires_rollback=True,
        )
    }

    def evaluate(
        self,
        proposal: RepairProposal,
        evidence: EvidenceSnapshot,
        approval: Approval | None,
    ) -> PolicyDecision:
        reasons: list[str] = []
        policy = self._catalog.get(proposal.operation)

        if policy is None:
            reasons.append("operation is not allowlisted")
        if not proposal.target.is_unambiguous():
            reasons.append("proposal target is ambiguous")
        if proposal.target != evidence.target:
            reasons.append("proposal target does not match evidence target")
        if proposal.contains_secret:
            reasons.append("proposal contains secret material")
        if evidence.smart_status != "healthy" or evidence.read_errors > 0:
            reasons.append("storage health blocks ordinary repair")
        if evidence.bitlocker_state == BitLockerState.LOCKED:
            reasons.append("BitLocker volume is locked")

        if policy is not None:
            if proposal.risk != policy.risk:
                reasons.append("proposal risk does not match operation policy")
            if policy.requires_rollback and not proposal.rollback_required:
                reasons.append("operation policy requires rollback")
            if policy.requires_rollback and not proposal.rollback_artifact_ready:
                reasons.append("verified rollback artifact is required")

        if proposal.operation == Operation.SIMULATE_BCD_REBUILD and evidence.bcd_valid:
            reasons.append("BCD repair is not supported by the evidence")

        if approval is None:
            reasons.append("approval is required")
        else:
            if approval.proposal_id != proposal.proposal_id:
                reasons.append("approval does not match proposal")
            if approval.target_digest != proposal.target.digest():
                reasons.append("approval target does not match proposal target")

        return PolicyDecision(allowed=not reasons, reasons=tuple(reasons))
