from __future__ import annotations

import unittest

from tests.helpers import proposal

from codex_rescue.models import ExecutionResult
from codex_rescue.runner import SimulatedRepairRunner, SimulatedVerifier


class SimulatedVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.proposal = proposal()
        self.runner = SimulatedRepairRunner()
        self.verifier = SimulatedVerifier()

    def test_verifier_independently_checks_receipt_against_proposal(self) -> None:
        execution = self.runner.execute(self.proposal)

        result = self.verifier.verify(self.proposal, execution)

        self.assertTrue(result.passed)

    def test_verifier_rejects_tampered_runner_output(self) -> None:
        execution = self.runner.execute(self.proposal)
        tampered = ExecutionResult(
            success=execution.success,
            message=execution.message,
            output={**execution.output, "target_digest": "different-target"},
        )

        result = self.verifier.verify(self.proposal, tampered)

        self.assertFalse(result.passed)


if __name__ == "__main__":
    unittest.main()
