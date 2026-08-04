from __future__ import annotations

import unittest

from tests.helpers import BitLockerState, evidence, target

from codex_rescue.diagnostics import analyze


class DiagnosticEngineTests(unittest.TestCase):
    def test_invalid_bcd_proposes_simulated_rebuild(self) -> None:
        findings = analyze(evidence())

        self.assertEqual(findings[0].code, "boot.bcd-invalid")
        self.assertEqual(findings[0].suggested_operation, "simulate.bcd.rebuild")
        self.assertFalse(findings[0].blocks_writes)

    def test_locked_bitlocker_blocks_repairs_without_accepting_a_key(self) -> None:
        findings = analyze(
            evidence(
                bitlocker_state=BitLockerState.LOCKED,
                target=target(bitlocker_key_id="ABCDEF12"),
            )
        )

        self.assertEqual(findings[0].code, "bitlocker.locked")
        self.assertTrue(findings[0].blocks_writes)
        self.assertIsNone(findings[0].suggested_operation)

    def test_failing_drive_takes_precedence_over_boot_repair(self) -> None:
        findings = analyze(evidence(smart_status="failing", read_errors=12))

        self.assertEqual(findings[0].code, "storage.failing")
        self.assertTrue(findings[0].blocks_writes)
        self.assertIsNone(findings[0].suggested_operation)


if __name__ == "__main__":
    unittest.main()
