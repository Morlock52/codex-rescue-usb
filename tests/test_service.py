from __future__ import annotations

import tempfile
import unittest
from dataclasses import FrozenInstanceError
from pathlib import Path

from tests.helpers import ROOT

from codex_rescue.fixtures import FixtureError, FixtureRepository
from codex_rescue.service import CaseService, PolicyBlocked


class CaseServiceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = CaseService(FixtureRepository(ROOT / "fixtures"))

    def test_boot_fixture_requires_approval_then_verifies_simulation(self) -> None:
        case = self.service.create_case("boot-loop")
        self.assertEqual(case.stage, "proposed")
        self.assertIsNotNone(case.proposal)

        with self.assertRaises(PolicyBlocked):
            self.service.execute(case.case_id)

        assert case.proposal is not None
        approved = self.service.approve(
            case.case_id,
            case.proposal.proposal_id,
            case.proposal.target.digest(),
        )
        completed = self.service.execute(case.case_id)

        self.assertEqual(case.stage, "proposed")
        self.assertEqual(approved.stage, "approved")
        self.assertEqual(completed.stage, "verified")
        self.assertTrue(completed.execution.success)
        self.assertTrue(completed.verification.passed)

        with self.assertRaises(FrozenInstanceError):
            completed.stage = "failed"

        with self.assertRaises(PolicyBlocked) as blocked:
            self.service.execute(case.case_id)
        self.assertIn("one execution", str(blocked.exception))

    def test_bitlocker_fixture_has_no_executable_proposal(self) -> None:
        case = self.service.create_case("bitlocker-locked")

        self.assertEqual(case.stage, "blocked")
        self.assertIsNone(case.proposal)
        with self.assertRaises(PolicyBlocked):
            self.service.execute(case.case_id)

    def test_failing_drive_fixture_has_no_executable_proposal(self) -> None:
        case = self.service.create_case("failing-drive")

        self.assertEqual(case.stage, "blocked")
        self.assertEqual(case.findings[0].code, "storage.failing")
        self.assertIsNone(case.proposal)

    def test_fixture_repository_rejects_secret_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture_path = Path(temp_dir) / "unsafe.json"
            fixture_path.write_text(
                """{
                    "id": "unsafe",
                    "title": "unsafe",
                    "category": "test",
                    "target": {
                        "disk_serial": "demo",
                        "partition_guid": "demo",
                        "filesystem_uuid": "demo",
                        "windows_path": "\\\\Windows",
                        "bitlocker_key_id": "ABCDEF12"
                    },
                    "evidence": {
                        "smart_status": "healthy",
                        "read_errors": 0,
                        "bitlocker_state": "locked",
                        "bcd_valid": false,
                        "boot_files_present": true,
                        "network_available": false,
                        "recovery_key": "111111-111111-111111-111111-111111-111111-111111-111111"
                    }
                }""",
                encoding="utf-8",
            )

            repository = FixtureRepository(Path(temp_dir))
            with self.assertRaises(FixtureError):
                repository.load("unsafe")


if __name__ == "__main__":
    unittest.main()
