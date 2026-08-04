from __future__ import annotations

from dataclasses import dataclass

from codex_rescue.models import (
    Approval,
    BitLockerState,
    EvidenceSnapshot,
    ExecutionResult,
    Operation,
    PostActionEvidence,
    RepairProposal,
    RiskLevel,
    RollbackArtifact,
    SimulationReceipt,
    StorageHealth,
    VerificationResult,
)


@dataclass(frozen=True)
class OperationPolicy:
    risk: RiskLevel
    requires_rollback: bool


class SimulatedBcdRebuildHandler:
    operation = Operation.SIMULATE_BCD_REBUILD
    policy = OperationPolicy(risk=RiskLevel.READ_ONLY, requires_rollback=True)

    def supports(self, evidence: EvidenceSnapshot) -> bool:
        return bool(
            evidence.smart_status == StorageHealth.HEALTHY
            and evidence.read_errors == 0
            and evidence.bitlocker_state != BitLockerState.LOCKED
            and evidence.boot_files_present
            and not evidence.bcd_valid
        )

    def create_proposal(
        self,
        proposal_id: str,
        evidence: EvidenceSnapshot,
        rollback_artifact: RollbackArtifact,
    ) -> RepairProposal:
        return RepairProposal(
            proposal_id=proposal_id,
            operation=self.operation,
            target=evidence.target,
            risk=self.policy.risk,
            summary="Simulate rebuilding the fixture Windows boot configuration.",
            reason="The fixture reports a missing or invalid BCD store.",
            simulated_change="BCD state changes from invalid to valid inside fixture data.",
            host_impact="No host disk, volume, boot file, or command is touched.",
            inputs=(
                "Validated boot-loop fixture evidence",
                "Exact target fingerprint",
                "Verified fixture BCD rollback artifact",
            ),
            preconditions=(
                "Storage health is healthy with zero read errors",
                "BitLocker is not locked",
                "Boot files are present and BCD validation failed",
                "Approval fingerprint matches the complete proposal",
            ),
            permitted_commands=(),
            expected_outputs=(
                "Typed simulation receipt",
                "Independent post-action fixture observation",
                "Verification result bound to the proposal and rollback artifact",
            ),
            rollback_artifact=rollback_artifact,
            stop_conditions=(
                "Target identity changes",
                "Rollback artifact verification fails",
                "Evidence no longer supports BCD reconstruction",
                "Approval fingerprint differs from the current proposal",
                "Post-action fixture contradicts the expected result",
            ),
            verification_plan=(
                "Verify the typed receipt digest and approval fingerprint",
                "Load the separate post-action fixture",
                "Match target and rollback artifact digests",
                "Require BCD validation to pass",
            ),
        )

    def execute(
        self,
        proposal: RepairProposal,
        approval: Approval,
    ) -> ExecutionResult:
        receipt = SimulationReceipt.create(
            proposal,
            approval,
            result_code="fixture.bcd-rebuild.simulated",
        )
        return ExecutionResult(
            success=True,
            message="Simulated BCD rebuild completed with zero host impact.",
            receipt=receipt,
        )

    def verify(
        self,
        proposal: RepairProposal,
        approval: Approval,
        execution: ExecutionResult,
        post_evidence: PostActionEvidence,
    ) -> VerificationResult:
        receipt = execution.receipt
        passed = bool(
            execution.success
            and receipt is not None
            and receipt.verify_digest()
            and receipt.operation == proposal.operation
            and receipt.proposal_digest == proposal.digest()
            and receipt.approval_fingerprint_digest == approval.fingerprint.digest()
            and receipt.target_digest == proposal.target.digest()
            and post_evidence.scenario_id == proposal.rollback_artifact.scenario_id
            and post_evidence.operation == proposal.operation
            and post_evidence.target_digest == proposal.target.digest()
            and post_evidence.rollback_artifact_digest
            == proposal.rollback_artifact.content_digest
            and post_evidence.bcd_valid
        )
        return VerificationResult(
            passed=passed,
            message=(
                "Independent fixture verification passed."
                if passed
                else "Independent fixture verification failed; retain the last safe state."
            ),
        )


class OperationRegistry:
    def __init__(self) -> None:
        handlers = (SimulatedBcdRebuildHandler(),)
        self._handlers = {handler.operation: handler for handler in handlers}

    def get(self, operation: Operation):
        return self._handlers.get(operation)

    def require(self, operation: Operation):
        handler = self.get(operation)
        if handler is None:
            raise ValueError(f"operation is not registered: {operation}")
        return handler
