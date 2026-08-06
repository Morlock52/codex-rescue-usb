import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class TechnicianWorkspacePrerequisiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repository_root = Path(__file__).resolve().parents[1]
        cls.script_path = (
            cls.repository_root
            / "scripts"
            / "Test-TechnicianWorkspacePrerequisite.ps1"
        )
        cls.pwsh = shutil.which("pwsh")

    def run_contract_fixture(self, fixture: dict) -> dict:
        if self.pwsh is None:
            self.skipTest("PowerShell 7 is not installed on this test host")

        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_path = Path(temporary_directory) / "fixture.json"
            fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
            completed = subprocess.run(
                [
                    self.pwsh,
                    "-NoLogo",
                    "-NoProfile",
                    "-File",
                    str(self.script_path),
                    "-ContractFixturePath",
                    str(fixture_path),
                    "-AsJson",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    @staticmethod
    def passing_fixture() -> dict:
        return {
            "IsWindows": True,
            "IsWindows11": True,
            "IsWinPE": False,
            "Is64BitOperatingSystem": True,
            "WindowsPowerShell51Available": True,
            "TotalMemoryGB": 12,
            "SystemDriveFreeGB": 80,
            "FirmwareType": "UEFI",
            "SecureBootEnabled": True,
            "TpmPresent": True,
            "TpmReady": True,
            "TpmVersion": "2.0",
            "HardwareAdapterCount": 1,
            "ActiveHardwareAdapterCount": 0,
            "GuestAgentInstalled": True,
            "GuestAgentRunning": True,
            "GuestAgentStartMode": "Automatic",
        }

    def test_script_is_read_only_and_documents_fixture_boundary(self) -> None:
        source = self.script_path.read_text(encoding="utf-8")

        self.assertIn(".SYNOPSIS", source)
        self.assertIn("ContractFixturePath", source)
        self.assertIn("Contract fixtures never count as live readiness evidence", source)
        for disallowed in (
            "Set-NetAdapter",
            "Enable-NetAdapter",
            "Disable-NetAdapter",
            "Start-Process",
            "Invoke-WebRequest",
            "Invoke-RestMethod",
            "winget",
            "Install-Module",
            "Remove-Item",
            "Set-ItemProperty",
        ):
            self.assertNotIn(disallowed, source)

    def test_passing_fixture_validates_contract_but_not_live_readiness(self) -> None:
        result = self.run_contract_fixture(self.passing_fixture())

        self.assertEqual(result["SchemaVersion"], 1)
        self.assertEqual(result["EvidenceSource"], "ContractFixture")
        self.assertFalse(result["LiveEvidence"])
        self.assertTrue(result["AllRequiredChecksPass"])
        self.assertFalse(result["ReadyForProvisioning"])
        self.assertEqual(len(result["Checks"]), 11)
        self.assertFalse(result["ContainsIdentifiers"])
        self.assertFalse(result["ContainsCredentials"])

    def test_fixture_fails_memory_and_offline_network_requirements(self) -> None:
        fixture = self.passing_fixture()
        fixture["TotalMemoryGB"] = 6
        fixture["ActiveHardwareAdapterCount"] = 1

        result = self.run_contract_fixture(fixture)
        checks = {check["Name"]: check for check in result["Checks"]}

        self.assertFalse(result["AllRequiredChecksPass"])
        self.assertFalse(result["ReadyForProvisioning"])
        self.assertEqual(checks["Memory"]["Status"], "Failed")
        self.assertEqual(checks["NetworkDefaultOffline"]["Status"], "Failed")

    def test_windows_service_auto_start_value_is_accepted(self) -> None:
        fixture = self.passing_fixture()
        fixture["GuestAgentStartMode"] = "Auto"

        result = self.run_contract_fixture(fixture)
        checks = {check["Name"]: check for check in result["Checks"]}

        self.assertTrue(result["AllRequiredChecksPass"])
        self.assertEqual(checks["GuestAgent"]["Status"], "Passed")


if __name__ == "__main__":
    unittest.main()
