import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class TechnicianWorkspaceVerifierTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repository_root = Path(__file__).resolve().parents[1]
        cls.script_path = (
            cls.repository_root
            / "scripts"
            / "Test-TechnicianWorkspaceToolchain.ps1"
        )
        cls.manifest_path = (
            cls.repository_root
            / "config"
            / "technician-workspace-tools.json"
        )
        cls.pwsh = shutil.which("pwsh")

    @staticmethod
    def passing_fixture() -> dict:
        return {
            "IsWindows": True,
            "IsWinPE": False,
            "HardwareAdapterCount": 1,
            "ActiveHardwareAdapterCount": 0,
            "OfflineStartupTaskInstalled": True,
            "OfflineStartupPolicyPresent": True,
            "ProjectPayloadPresent": True,
            "InstalledWinGetPackages": [
                {"Id": "Microsoft.PowerShell", "Version": "7.5.3"},
                {"Id": "Git.Git", "Version": "2.50.1"},
                {"Id": "OpenJS.NodeJS.LTS", "Version": "22.18.0"},
                {"Id": "Microsoft.Sysinternals", "Version": "2025.7.24"},
                {"Id": "7zip.7zip", "Version": "25.01"},
            ],
            "InstalledPowerShellModules": [
                {"Name": "PowerShellGet", "Version": "2.2.5"},
                {"Name": "Microsoft.WinGet.Client", "Version": "1.29.280"},
                {"Name": "Microsoft.Graph.Authentication", "Version": "2.39.0"},
                {"Name": "Microsoft.Graph.DeviceManagement", "Version": "2.39.0"},
                {
                    "Name": "Microsoft.Graph.Identity.DirectoryManagement",
                    "Version": "2.39.0",
                },
                {"Name": "Microsoft.Graph.Groups", "Version": "2.39.0"},
                {"Name": "Microsoft.Graph.Users", "Version": "2.39.0"},
                {"Name": "WindowsAutoPilotIntune", "Version": "5.7"},
            ],
            "CodexCommandAvailable": True,
            "CodexVersion": "0.146.1",
            "CodexAuthArtifactCount": 0,
            "CloudAuthArtifactCount": 0,
            "SensitiveEnvironmentVariableCount": 0,
            "ReceiptPresent": True,
            "ReceiptManifestAsOfDate": "2026-08-05",
            "ReceiptCodexIntegrityVerified": True,
            "ReceiptContainsSensitiveMaterial": False,
        }

    def run_fixture(self, fixture: dict) -> dict:
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
                    "-ManifestPath",
                    str(self.manifest_path),
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

    def test_script_is_read_only_and_documents_fixture_boundary(self) -> None:
        source = self.script_path.read_text(encoding="utf-8")

        self.assertIn(".SYNOPSIS", source)
        self.assertIn("ContractFixturePath", source)
        self.assertIn(
            "Contract fixtures never count as live generalization evidence",
            source,
        )
        for disallowed in (
            "Enable-NetAdapter",
            "Disable-NetAdapter",
            "Start-Process",
            "Invoke-WebRequest",
            "Invoke-RestMethod",
            "Install-Module",
            "Uninstall-Module",
            "Remove-Item",
            "Set-ItemProperty",
            "Register-ScheduledTask",
            "Unregister-ScheduledTask",
        ):
            self.assertNotIn(disallowed, source)

    def test_passing_fixture_proves_contract_but_not_live_readiness(self) -> None:
        result = self.run_fixture(self.passing_fixture())

        self.assertEqual(result["SchemaVersion"], 1)
        self.assertEqual(result["EvidenceSource"], "ContractFixture")
        self.assertFalse(result["LiveEvidence"])
        self.assertTrue(result["AllRequiredChecksPass"])
        self.assertFalse(result["ReadyForGeneralization"])
        self.assertEqual(len(result["Checks"]), 10)
        self.assertEqual(result["ChangesMade"], 0)
        self.assertEqual(result["NetworkRequestsMade"], 0)

    def test_online_authenticated_or_wrong_codex_fixture_fails(self) -> None:
        fixture = self.passing_fixture()
        fixture["ActiveHardwareAdapterCount"] = 1
        fixture["CodexVersion"] = "0.145.0"
        fixture["CodexAuthArtifactCount"] = 1

        result = self.run_fixture(fixture)
        checks = {check["Name"]: check for check in result["Checks"]}

        self.assertFalse(result["AllRequiredChecksPass"])
        self.assertEqual(checks["NetworkDefaultOffline"]["Status"], "Failed")
        self.assertEqual(checks["CodexCliVersion"]["Status"], "Failed")
        self.assertEqual(checks["CodexUnauthenticated"]["Status"], "Failed")

    def test_missing_required_package_module_and_receipt_fail(self) -> None:
        fixture = self.passing_fixture()
        fixture["InstalledWinGetPackages"] = fixture["InstalledWinGetPackages"][:-1]
        fixture["InstalledPowerShellModules"] = (
            fixture["InstalledPowerShellModules"][:-1]
        )
        fixture["ReceiptPresent"] = False
        fixture["ReceiptCodexIntegrityVerified"] = False

        result = self.run_fixture(fixture)
        checks = {check["Name"]: check for check in result["Checks"]}

        self.assertEqual(checks["RequiredWinGetPackages"]["Status"], "Failed")
        self.assertEqual(checks["RequiredPowerShellModules"]["Status"], "Failed")
        self.assertEqual(checks["InstallReceipt"]["Status"], "Failed")


if __name__ == "__main__":
    unittest.main()
