from __future__ import annotations

import unittest
from dataclasses import replace

from tests.helpers import ROOT

from codex_rescue.fixtures import FixtureRepository
from codex_rescue.service import CaseService


class SimulatedVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = CaseService(FixtureRepository(ROOT / "fixtures"))
        case = self.service.create_case("boot-loop")
        assert case.proposal is not None
        self.case = self.service.approve(
            case.case_id,
            case.proposal.approval_fingerprint(),
        )
        self.proposal = self.case.proposal
        self.approval = self.case.approval
        assert self.proposal is not None
        assert self.approval is not None
        self.handler = self.service.registry.require(self.proposal.operation)

    def test_verifier_independently_checks_receipt_against_proposal(self) -> None:
        execution = self.handler.execute(self.proposal, self.approval)
        post_evidence = self.service.post_actions.collect(
            self.case.evidence,
            self.proposal,
        )

        result = self.handler.verify(
            self.proposal,
            self.approval,
            execution,
            post_evidence,
        )

        self.assertTrue(result.passed)

    def test_verifier_rejects_tampered_typed_receipt(self) -> None:
        execution = self.handler.execute(self.proposal, self.approval)
        assert execution.receipt is not None
        tampered = replace(
            execution,
            receipt=replace(execution.receipt, target_digest="different-target"),
        )
        post_evidence = self.service.post_actions.collect(
            self.case.evidence,
            self.proposal,
        )

        result = self.handler.verify(
            self.proposal,
            self.approval,
            tampered,
            post_evidence,
        )

        self.assertFalse(result.passed)

    def test_verifier_rejects_independent_post_action_failure(self) -> None:
        execution = self.handler.execute(self.proposal, self.approval)
        post_evidence = self.service.post_actions.collect(
            self.case.evidence,
            self.proposal,
        )
        failed_evidence = replace(post_evidence, bcd_valid=False)

        result = self.handler.verify(
            self.proposal,
            self.approval,
            execution,
            failed_evidence,
        )

        self.assertFalse(result.passed)


if __name__ == "__main__":
    unittest.main()
