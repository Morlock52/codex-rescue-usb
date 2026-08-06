import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class GuestAgentBootstrapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repository_root = Path(__file__).resolve().parents[1]
        cls.script_path = (
            cls.repository_root
            / "scripts"
            / "Install-TechnicianWorkspaceGuestAgent.ps1"
        )
        cls.pwsh = shutil.which("pwsh")

    @staticmethod
    def passing_fixture() -> dict:
        return {
            "IsWindows": True,
            "IsWinPE": False,
            "IsAdministrator": True,
            "InstallerCandidateCount": 1,
            "InstallerFileName": "qemu-ga-x86_64.msi",
            "InstallerSignatureStatus": "Valid",
            "InstallerSignerSubject": "CN=Red Hat, Inc.",
            "ServiceInstalled": False,
            "ServiceRunning": False,
            "ServiceStartMode": "Unavailable",
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
                    "-Mode",
                    "Audit",
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

    def test_passing_fixture_proves_contract_but_not_live_install_readiness(self) -> None:
        result = self.run_fixture(self.passing_fixture())

        self.assertEqual(result["SchemaVersion"], 1)
        self.assertEqual(result["Mode"], "Audit")
        self.assertEqual(result["EvidenceSource"], "ContractFixture")
        self.assertFalse(result["LiveEvidence"])
        self.assertTrue(result["InstallerContractPasses"])
        self.assertFalse(result["ReadyForInstall"])
        self.assertEqual(result["ChangesMade"], 0)
        self.assertEqual(result["NetworkRequestsMade"], 0)

    def test_invalid_signer_or_ambiguous_installer_fails_contract(self) -> None:
        fixture = self.passing_fixture()
        fixture["InstallerCandidateCount"] = 2
        fixture["InstallerSignatureStatus"] = "NotSigned"
        fixture["InstallerSignerSubject"] = ""

        result = self.run_fixture(fixture)
        checks = {check["Name"]: check for check in result["Checks"]}

        self.assertFalse(result["InstallerContractPasses"])
        self.assertEqual(checks["ExactInstallerCandidate"]["Status"], "Failed")
        self.assertEqual(checks["TrustedInstallerSignature"]["Status"], "Failed")

    def test_apply_path_is_offline_guarded_and_uses_msiexec_safely(self) -> None:
        source = self.script_path.read_text(encoding="utf-8")

        self.assertIn("SupportsShouldProcess = $true", source)
        self.assertIn("ConfirmImpact = 'High'", source)
        self.assertIn("INSTALL QEMU GUEST AGENT", source)
        self.assertIn("Test-Administrator", source)
        self.assertIn("Get-AuthenticodeSignature", source)
        self.assertIn("qemu-ga-x86_64.msi", source)
        self.assertIn("msiexec.exe", source)
        self.assertIn("/norestart", source)
        self.assertIn("QEMU-GA", source)
        for disallowed in (
            "Invoke-WebRequest",
            "Invoke-RestMethod",
            "Start-BitsTransfer",
            "winget install",
            "Install-Module",
        ):
            self.assertNotIn(disallowed, source)


if __name__ == "__main__":
    unittest.main()
