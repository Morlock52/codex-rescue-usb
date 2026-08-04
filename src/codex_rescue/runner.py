from __future__ import annotations

from codex_rescue.models import (
    ExecutionResult,
    Operation,
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
                "backup_verified": True,
                "bcd_valid_after": True,
            },
        )


class SimulatedVerifier:
    """Verify the receipt against proposal facts without invoking the runner."""

    def verify(
        self,
        proposal: RepairProposal,
        execution: ExecutionResult,
    ) -> VerificationResult:
        if proposal.operation != Operation.SIMULATE_BCD_REBUILD:
            return VerificationResult(False, "No verifier exists for this operation.")
        passed = bool(
            execution.success
            and execution.output.get("mode") == "simulation"
            and execution.output.get("operation") == proposal.operation.value
            and execution.output.get("target_digest") == proposal.target.digest()
            and execution.output.get("receipt_digest") == proposal.receipt_digest()
            and execution.output.get("backup_verified") is True
            and execution.output.get("bcd_valid_after") is True
        )
        return VerificationResult(
            passed=passed,
            message=(
                "Independent fixture verification passed."
                if passed
                else "Independent fixture verification failed."
            ),
        )
