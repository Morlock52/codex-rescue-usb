from __future__ import annotations

from codex_rescue.models import (
    Approval,
    ExecutionResult,
    PostActionEvidence,
    RepairProposal,
    VerificationResult,
)
from codex_rescue.operations import OperationRegistry


class SimulatedRepairRunner:
    """Dispatch an approved fixture-only operation without host command access."""

    def __init__(self, registry: OperationRegistry) -> None:
        self.registry = registry

    def execute(
        self,
        proposal: RepairProposal,
        approval: Approval,
    ) -> ExecutionResult:
        return self.registry.require(proposal.operation).execute(proposal, approval)


class SimulatedVerifier:
    """Dispatch independent verification for a registered operation."""

    def __init__(self, registry: OperationRegistry) -> None:
        self.registry = registry

    def verify(
        self,
        proposal: RepairProposal,
        approval: Approval,
        execution: ExecutionResult,
        post_evidence: PostActionEvidence,
    ) -> VerificationResult:
        return self.registry.require(proposal.operation).verify(
            proposal,
            approval,
            execution,
            post_evidence,
        )
