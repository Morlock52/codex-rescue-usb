from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tests.helpers import ROOT

from codex_rescue.fixtures import (
    FixtureIntegrityError,
    FixtureNotFound,
    FixtureRepository,
)


def valid_fixture() -> dict[str, object]:
    return {
        "id": "strict-fixture",
        "title": "Strict fixture",
        "category": "pc-wont-boot",
        "presentation": {
            "label": "Strict fixture",
            "description": "Schema-validation fixture",
            "order": 1,
        },
        "target": {
            "disk_serial": "NVME-DEMO-100",
            "partition_guid": "11111111-2222-3333-4444-555555555555",
            "filesystem_uuid": "AAAA-BBBB",
            "windows_path": "\\Windows",
            "bitlocker_key_id": None,
        },
        "evidence": {
            "smart_status": "healthy",
            "read_errors": 0,
            "bitlocker_state": "not-encrypted",
            "bcd_valid": False,
            "boot_files_present": True,
            "network_available": False,
            "notes": ["Fixture evidence only"],
        },
    }


class FixtureSecurityTests(unittest.TestCase):
    def test_load_rejects_scenario_path_traversal(self) -> None:
        repository = FixtureRepository(ROOT / "fixtures")

        with self.assertRaises(FixtureNotFound):
            repository.load("../boot-loop")

    def test_fixture_booleans_are_not_coerced_from_strings(self) -> None:
        payload = valid_fixture()
        payload["evidence"]["bcd_valid"] = "false"

        with self.fixture_repository(payload) as repository:
            with self.assertRaises(FixtureIntegrityError):
                repository.load("strict-fixture")

    def test_fixture_rejects_negative_counts_and_unknown_enums(self) -> None:
        for field, value in (("read_errors", -1), ("smart_status", "maybe")):
            payload = valid_fixture()
            payload["evidence"][field] = value
            with self.subTest(field=field):
                with self.fixture_repository(payload) as repository:
                    with self.assertRaises(FixtureIntegrityError):
                        repository.load("strict-fixture")

    def test_fixture_rejects_secret_alias_fields(self) -> None:
        payload = valid_fixture()
        payload["evidence"]["bitlocker_recovery_key"] = "not-allowed"

        with self.fixture_repository(payload) as repository:
            with self.assertRaises(FixtureIntegrityError):
                repository.load("strict-fixture")

    @staticmethod
    def fixture_repository(payload: dict[str, object]):
        class FixtureContext:
            def __enter__(self) -> FixtureRepository:
                self.temp = tempfile.TemporaryDirectory()
                path = Path(self.temp.name) / "strict-fixture.json"
                path.write_text(json.dumps(payload), encoding="utf-8")
                return FixtureRepository(Path(self.temp.name))

            def __exit__(self, *args: object) -> None:
                self.temp.cleanup()

        return FixtureContext()


if __name__ == "__main__":
    unittest.main()
