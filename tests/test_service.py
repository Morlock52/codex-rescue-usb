from __future__ import annotations

import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from dataclasses import FrozenInstanceError
from threading import Barrier
from pathlib import Path

from tests.helpers import ROOT

from codex_rescue.artifacts import PostActionFixtureRepository
from codex_rescue.fixtures import FixtureError, FixtureRepository
from codex_rescue.models import CaseStage
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
            case.proposal.approval_fingerprint(),
        )
        completed = self.service.execute(case.case_id)

        self.assertEqual(case.stage, "proposed")
        self.assertEqual(approved.stage, "approved")
        self.assertEqual(completed.stage, "verified")
        self.assertTrue(completed.execution.success)
        self.assertTrue(completed.verification.passed)

        with self.assertRaises(FrozenInstanceError):
            completed.stage = "failed"

        with self.assertRaises(FrozenInstanceError):
            completed.execution.receipt.target_digest = "mutated"

        with self.assertRaises(PolicyBlocked) as blocked:
            self.service.execute(case.case_id)
        self.assertIn("one execution", str(blocked.exception))

    def test_one_approval_cannot_race_into_two_executions(self) -> None:
        case = self.service.create_case("boot-loop")
        assert case.proposal is not None
        self.service.approve(
            case.case_id,
            case.proposal.approval_fingerprint(),
        )
        barrier = Barrier(2)

        def execute_once() -> str:
            barrier.wait(timeout=2)
            try:
                return self.service.execute(case.case_id).stage
            except PolicyBlocked:
                return "blocked"

        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda _: execute_once(), range(2)))

        self.assertEqual(results.count("verified"), 1)
        self.assertEqual(results.count("blocked"), 1)

    def test_missing_post_action_evidence_consumes_approval_and_fails_case(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            service = CaseService(
                FixtureRepository(ROOT / "fixtures"),
                post_actions=PostActionFixtureRepository(Path(temp_dir)),
            )
            case = service.create_case("boot-loop")
            assert case.proposal is not None
            service.approve(case.case_id, case.proposal.approval_fingerprint())

            failed = service.execute(case.case_id)

        self.assertEqual(failed.stage, CaseStage.FAILED)
        self.assertFalse(failed.verification.passed)
        self.assertIn("unavailable", failed.verification.message)
        with self.assertRaises(PolicyBlocked):
            service.execute(case.case_id)

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
            fake_recovery_password = "-".join(["111111"] * 8)
            fixture_json = (
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
                        "recovery_key": "__FAKE_RECOVERY_PASSWORD__"
                    }
                }"""
            )
            fixture_path.write_text(
                fixture_json.replace(
                    "__FAKE_RECOVERY_PASSWORD__", fake_recovery_password
                ),
                encoding="utf-8",
            )

            repository = FixtureRepository(Path(temp_dir))
            with self.assertRaises(FixtureError):
                repository.load("unsafe")


if __name__ == "__main__":
    unittest.main()
