from __future__ import annotations

import unittest
from dataclasses import replace

from tests.helpers import approval, evidence, proposal, target

from codex_rescue.models import BitLockerState
from codex_rescue.operations import OperationRegistry
from codex_rescue.safety import SafetyBroker


class SafetyBrokerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.broker = SafetyBroker(OperationRegistry())

    def test_valid_fixture_proposal_is_allowed_after_approval(self) -> None:
        item = proposal()

        decision = self.broker.evaluate(item, evidence(), approval(item))

        self.assertTrue(decision.allowed)
        self.assertEqual(decision.reasons, ())

    def test_execution_is_blocked_without_approval(self) -> None:
        decision = self.broker.evaluate(proposal(), evidence(), None)

        self.assertFalse(decision.allowed)
        self.assertIn("approval is required", decision.reasons)

    def test_target_mismatch_is_blocked(self) -> None:
        item = proposal(target=target(disk_serial="OTHER-DISK"))

        decision = self.broker.evaluate(item, evidence(), approval(item))

        self.assertFalse(decision.allowed)
        self.assertIn("proposal target does not match evidence target", decision.reasons)

    def test_ambiguous_target_is_blocked_even_when_fingerprints_match(self) -> None:
        ambiguous_target = target(disk_serial="")
        item = proposal(target=ambiguous_target)

        decision = self.broker.evaluate(
            item,
            evidence(target=ambiguous_target),
            approval(item),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("proposal target is ambiguous", decision.reasons)

    def test_missing_rollback_artifact_is_blocked(self) -> None:
        item = proposal()
        item = replace(
            item,
            rollback_artifact=replace(item.rollback_artifact, restore_tested=False),
        )

        decision = self.broker.evaluate(item, evidence(), approval(item))

        self.assertFalse(decision.allowed)
        self.assertIn("verified rollback artifact is required", decision.reasons)

    def test_secret_bearing_proposal_is_blocked(self) -> None:
        item = proposal(
            summary=(
                "Use 111111-111111-111111-111111-111111-111111-111111-111111"
            )
        )

        decision = self.broker.evaluate(item, evidence(), approval(item))

        self.assertFalse(decision.allowed)
        self.assertIn("proposal contains secret material", decision.reasons)

    def test_unknown_operation_is_blocked(self) -> None:
        item = proposal(operation="shell.arbitrary")

        decision = self.broker.evaluate(item, evidence(), approval(item))

        self.assertFalse(decision.allowed)
        self.assertIn("operation is not allowlisted", decision.reasons)

    def test_failing_drive_blocks_ordinary_write(self) -> None:
        item = proposal()

        decision = self.broker.evaluate(
            item,
            evidence(smart_status="failing", read_errors=4),
            approval(item),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("storage health blocks ordinary repair", decision.reasons)

    def test_locked_bitlocker_blocks_ordinary_write(self) -> None:
        item = proposal()

        decision = self.broker.evaluate(
            item,
            evidence(bitlocker_state=BitLockerState.LOCKED),
            approval(item),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("BitLocker volume is locked", decision.reasons)

    def test_approval_must_match_proposal_target(self) -> None:
        item = proposal()
        mismatched_approval = replace(
            approval(item),
            fingerprint=replace(
                item.approval_fingerprint(),
                target_digest=target(disk_serial="OTHER-DISK").digest(),
            ),
        )

        decision = self.broker.evaluate(item, evidence(), mismatched_approval)

        self.assertFalse(decision.allowed)
        self.assertIn(
            "approval fingerprint does not match complete proposal",
            decision.reasons,
        )


if __name__ == "__main__":
    unittest.main()
