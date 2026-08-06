from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "New-CodexRescueUefiBootRepairPlan.ps1"


class UefiBootRepairPlanTests(unittest.TestCase):
    def setUp(self) -> None:
        self.pwsh = shutil.which("pwsh")
        self.fixture = {
            "SchemaVersion": 1,
            "EvidenceSha256": "A" * 64,
            "EvidenceIntegrityVerified": True,
            "ContainsRecoveryMaterial": False,
            "ContainsSensitiveRawEvidence": False,
            "StorageHealth": "Healthy",
            "BitLockerState": "Unlocked",
            "FirmwareType": "UEFI",
            "WindowsDirectory": "D:\\Windows",
            "WindowsDirectoryVerified": True,
            "WindowsDiskUniqueId": "DISPOSABLE-DISK-001",
            "EfiSystemPartition": "S:",
            "EfiPartitionVerified": True,
            "EfiFileSystem": "FAT32",
            "EfiDiskUniqueId": "DISPOSABLE-DISK-001",
            "RollbackArtifactType": "EfiMicrosoftBootDirectoryBackup",
            "RollbackArtifactPath": "E:\\CodexRescueRollback\\EfiMicrosoftBoot.zip",
            "RollbackArtifactSha256": "B" * 64,
            "RollbackArtifactVerified": True,
            "RollbackRestoreTested": True,
        }

    def run_fixture(
        self,
        fixture: dict[str, object],
        *,
        output_path: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        if self.pwsh is None:
            self.skipTest("PowerShell 7 is required for the runtime contract test")
        fixture_path = Path(self.temp_dir) / "discovery.json"
        fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
        command = [
            self.pwsh,
            "-NoProfile",
            "-File",
            str(SCRIPT),
            "-ContractFixturePath",
            str(fixture_path),
        ]
        if output_path is None:
            command.append("-AsJson")
        else:
            command.extend(["-OutputPath", str(output_path)])
        return subprocess.run(command, text=True, capture_output=True, check=False)

    def test_contract_fixture_builds_an_inert_target_bound_proposal(self) -> None:
        with tempfile.TemporaryDirectory() as self.temp_dir:
            completed = self.run_fixture(self.fixture)

        self.assertEqual(completed.returncode, 0, completed.stderr)
        plan = json.loads(completed.stdout)
        self.assertEqual(plan["EvidenceSource"], "ContractFixture")
        self.assertFalse(plan["LiveEvidence"])
        self.assertFalse(plan["ReadyForApproval"])
        self.assertTrue(plan["ApprovalRequired"])
        self.assertFalse(plan["ApprovalRecorded"])
        self.assertFalse(plan["ExecutionAvailable"])
        self.assertFalse(plan["WritePerformed"])
        self.assertIsNone(plan["RequiredConfirmationToken"])
        self.assertEqual(plan["Operation"], "windows.bootfiles.rebuild.uefi")
        self.assertEqual(plan["PermittedExecutable"], "bcdboot.exe")
        self.assertEqual(
            plan["Arguments"],
            ["D:\\Windows", "/s", "S:", "/f", "UEFI", "/v"],
        )
        self.assertFalse(plan["FirmwareNvramWriteExpected"])
        self.assertEqual(
            plan["Rollback"]["ArtifactType"],
            "EfiMicrosoftBootDirectoryBackup",
        )
        self.assertTrue(plan["Rollback"]["RestoreTested"])
        self.assertRegex(plan["ProposalDigest"], r"^[A-F0-9]{64}$")
        self.assertRegex(plan["TargetFingerprint"], r"^[A-F0-9]{64}$")

    def test_secret_bearing_or_cross_disk_discovery_is_rejected(self) -> None:
        unsafe_cases = (
            ({**self.fixture, "ContainsRecoveryMaterial": True}, "recovery material"),
            (
                {**self.fixture, "EfiDiskUniqueId": "OTHER-DISK"},
                "same explicitly identified disk",
            ),
            (
                {**self.fixture, "RollbackRestoreTested": False},
                "restore-tested rollback",
            ),
        )
        for fixture, expected_message in unsafe_cases:
            with self.subTest(expected_message=expected_message):
                with tempfile.TemporaryDirectory() as self.temp_dir:
                    completed = self.run_fixture(fixture)
                self.assertNotEqual(completed.returncode, 0)
                self.assertIn(expected_message, completed.stderr.lower())

    def test_plan_output_refuses_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as self.temp_dir:
            output_path = Path(self.temp_dir) / "boot-repair-plan.json"
            first = self.run_fixture(self.fixture, output_path=output_path)
            second = self.run_fixture(self.fixture, output_path=output_path)

            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertTrue(output_path.is_file())
            plan = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertFalse(plan["WritePerformed"])
            self.assertNotEqual(second.returncode, 0)
            self.assertIn("refuses to overwrite", second.stderr.lower())

    def test_script_has_no_repair_execution_path(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8").lower()

        self.assertIn("executionavailable = $false", script)
        self.assertIn("writeperformed = $false", script)
        self.assertIn("contractfixture", script)
        self.assertIn("bcdboot.exe", script)
        for forbidden in (
            "start-process",
            "invoke-expression",
            "invoke-command",
            "& bcdboot",
            "& $",
            "bcdedit.exe /import",
            "format-volume",
            "set-partition",
            "remove-partition",
            "clear-disk",
        ):
            self.assertNotIn(forbidden, script)


if __name__ == "__main__":
    unittest.main()
