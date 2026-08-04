from __future__ import annotations

from codex_rescue.models import (
    ExecutionResult,
    RepairProposal,
    VerificationResult,
)


class SimulatedRepairRunner:
    """Fixture-only runner. It cannot invoke the shell or modify a disk."""

    def execute(self, proposal: RepairProposal) -> ExecutionResult:
        if proposal.operation != "simulate.bcd.rebuild":
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
                "backup_verified": True,
                "bcd_valid_after": True,
            },
        )

    def verify(
        self,
        proposal: RepairProposal,
        execution: ExecutionResult,
    ) -> VerificationResult:
        if proposal.operation != "simulate.bcd.rebuild":
            return VerificationResult(False, "No verifier exists for this operation.")
        passed = bool(
            execution.success
            and execution.output.get("mode") == "simulation"
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
