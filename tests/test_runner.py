from __future__ import annotations

import unittest

from tests.helpers import proposal

from codex_rescue.models import ExecutionResult, PostActionEvidence
from codex_rescue.runner import (
    FixturePostActionProbe,
    SimulatedRepairRunner,
    SimulatedVerifier,
)


class SimulatedVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.proposal = proposal()
        self.runner = SimulatedRepairRunner()
        self.verifier = SimulatedVerifier()
        self.probe = FixturePostActionProbe()

    def test_verifier_independently_checks_receipt_against_proposal(self) -> None:
        execution = self.runner.execute(self.proposal)
        post_evidence = self.probe.collect(self.proposal)

        result = self.verifier.verify(self.proposal, execution, post_evidence)

        self.assertTrue(result.passed)

    def test_verifier_rejects_tampered_runner_output(self) -> None:
        execution = self.runner.execute(self.proposal)
        tampered = ExecutionResult(
            success=execution.success,
            message=execution.message,
            output={**dict(execution.output), "target_digest": "different-target"},
        )
        post_evidence = self.probe.collect(self.proposal)

        result = self.verifier.verify(self.proposal, tampered, post_evidence)

        self.assertFalse(result.passed)

    def test_verifier_rejects_independent_post_action_failure(self) -> None:
        execution = self.runner.execute(self.proposal)
        failed_evidence = PostActionEvidence(
            source="fixture://post-action/bcd-rebuild",
            target_digest=self.proposal.target.digest(),
            bcd_valid=False,
            rollback_artifact_present=True,
        )

        result = self.verifier.verify(
            self.proposal,
            execution,
            failed_evidence,
        )

        self.assertFalse(result.passed)


if __name__ == "__main__":
    unittest.main()
