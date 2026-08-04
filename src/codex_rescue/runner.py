from __future__ import annotations

from codex_rescue.models import (
    ExecutionResult,
    Operation,
    PostActionEvidence,
    RepairProposal,
    VerificationResult,
)


class SimulatedRepairRunner:
    """Fixture-only runner. It cannot invoke the shell or modify a disk."""

    def execute(self, proposal: RepairProposal) -> ExecutionResult:
        if proposal.operation != Operation.SIMULATE_BCD_REBUILD:
            return ExecutionResult(
                success=False,
                message="Simulation does not implement this operation.",
                output={"mode": "simulation"},
            )
        return ExecutionResult(
            success=True,
            message="Simulated BCD rebuild completed.",
            output={
                "mode": "simulation",
                "operation": proposal.operation.value,
                "target_digest": proposal.target.digest(),
                "receipt_digest": proposal.receipt_digest(),
            },
        )


class FixturePostActionProbe:
    """Collect separate, immutable post-action evidence from fixture state."""

    def collect(self, proposal: RepairProposal) -> PostActionEvidence:
        if proposal.operation != Operation.SIMULATE_BCD_REBUILD:
            return PostActionEvidence(
                source="fixture://post-action/unsupported",
                target_digest=proposal.target.digest(),
                bcd_valid=False,
                rollback_artifact_present=False,
            )
        return PostActionEvidence(
            source="fixture://post-action/bcd-rebuild",
            target_digest=proposal.target.digest(),
            bcd_valid=True,
            rollback_artifact_present=True,
        )


class SimulatedVerifier:
    """Verify the receipt against proposal facts without invoking the runner."""

    def verify(
        self,
        proposal: RepairProposal,
        execution: ExecutionResult,
        post_evidence: PostActionEvidence,
    ) -> VerificationResult:
        if proposal.operation != Operation.SIMULATE_BCD_REBUILD:
            return VerificationResult(False, "No verifier exists for this operation.")
        passed = bool(
            execution.success
            and execution.output.get("mode") == "simulation"
            and execution.output.get("operation") == proposal.operation.value
            and execution.output.get("target_digest") == proposal.target.digest()
            and execution.output.get("receipt_digest") == proposal.receipt_digest()
            and post_evidence.source == "fixture://post-action/bcd-rebuild"
            and post_evidence.target_digest == proposal.target.digest()
            and post_evidence.rollback_artifact_present
            and post_evidence.bcd_valid
        )
        return VerificationResult(
            passed=passed,
            message=(
                "Independent fixture verification passed."
                if passed
                else "Independent fixture verification failed."
            ),
        )
