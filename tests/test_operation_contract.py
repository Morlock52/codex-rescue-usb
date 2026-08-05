from __future__ import annotations

import unittest
from dataclasses import replace

from tests.helpers import ROOT

from codex_rescue.fixtures import FixtureRepository
from codex_rescue.models import RiskLevel, SimulationReceipt
from codex_rescue.service import CaseService, PolicyBlocked


class OperationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = CaseService(FixtureRepository(ROOT / "fixtures"))

    def test_proposal_contains_complete_safety_contract(self) -> None:
        case = self.service.create_case("boot-loop")
        assert case.proposal is not None

        proposal = case.proposal
        self.assertTrue(proposal.inputs)
        self.assertTrue(proposal.preconditions)
        self.assertEqual(proposal.permitted_commands, ())
        self.assertTrue(proposal.expected_outputs)
        self.assertTrue(proposal.stop_conditions)
        self.assertTrue(proposal.verification_plan)
        self.assertTrue(proposal.rollback_artifact.restore_tested)
        self.assertEqual(proposal.risk, RiskLevel.REVERSIBLE)

    def test_broker_detects_secret_material_without_caller_flag(self) -> None:
        case = self.service.create_case("boot-loop")
        assert case.proposal is not None
        fake_recovery_password = "-".join(["111111"] * 8)
        unsafe = replace(
            case.proposal,
            summary=f"Use {fake_recovery_password}",
        )

        decision = self.service.broker.evaluate(unsafe, case.evidence, None)

        self.assertFalse(decision.allowed)
        self.assertIn("proposal contains secret material", decision.reasons)

    def test_approval_is_bound_to_full_proposal_digest(self) -> None:
        case = self.service.create_case("boot-loop")
        assert case.proposal is not None
        fingerprint = case.proposal.approval_fingerprint()
        tampered = replace(fingerprint, proposal_digest="0" * 64)

        with self.assertRaises(PolicyBlocked):
            self.service.approve(case.case_id, tampered)

    def test_execution_returns_typed_receipt_and_independent_fixture_evidence(self) -> None:
        case = self.service.create_case("boot-loop")
        assert case.proposal is not None
        approved = self.service.approve(
            case.case_id,
            case.proposal.approval_fingerprint(),
        )

        completed = self.service.execute(approved.case_id)

        self.assertIsInstance(completed.execution.receipt, SimulationReceipt)
        self.assertTrue(completed.execution.receipt.verify_digest())
        self.assertTrue(completed.post_action_evidence.source_fixture_digest)
        self.assertEqual(
            completed.post_action_evidence.rollback_artifact_digest,
            case.proposal.rollback_artifact.content_digest,
        )


if __name__ == "__main__":
    unittest.main()
