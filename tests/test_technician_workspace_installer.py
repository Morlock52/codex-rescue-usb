import json
import shutil
import subprocess
import unittest
from pathlib import Path


class TechnicianWorkspaceInstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repository_root = Path(__file__).resolve().parents[1]
        cls.script_path = (
            cls.repository_root
            / "scripts"
            / "Install-TechnicianWorkspaceToolchain.ps1"
        )
        cls.manifest_path = (
            cls.repository_root
            / "config"
            / "technician-workspace-tools.json"
        )
        cls.pwsh = shutil.which("pwsh")

    def run_plan(self) -> dict:
        if self.pwsh is None:
            self.skipTest("PowerShell 7 is not installed on this test host")

        completed = subprocess.run(
            [
                self.pwsh,
                "-NoLogo",
                "-NoProfile",
                "-File",
                str(self.script_path),
                "-ManifestPath",
                str(self.manifest_path),
                "-Mode",
                "Plan",
                "-AsJson",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    def test_plan_mode_is_cross_platform_and_has_zero_side_effects(self) -> None:
        result = self.run_plan()

        self.assertEqual(result["SchemaVersion"], 1)
        self.assertEqual(result["Mode"], "Plan")
        self.assertFalse(result["ApplyAuthorized"])
        self.assertEqual(result["ChangesMade"], 0)
        self.assertEqual(result["NetworkRequestsMade"], 0)
        self.assertEqual(result["WinGetPackageCount"], 7)
        self.assertEqual(result["PowerShellModuleCount"], 8)
        self.assertEqual(result["CodexCli"]["Package"], "@openai/codex")
        self.assertEqual(result["CodexCli"]["Version"], "0.146.1")
        self.assertFalse(result["PersistCredentialsInImage"])

    def test_apply_path_has_exact_legal_safety_and_prerequisite_gates(self) -> None:
        source = self.script_path.read_text(encoding="utf-8")

        self.assertIn("SupportsShouldProcess = $true", source)
        self.assertIn("ConfirmImpact = 'High'", source)
        self.assertIn("INSTALL CODEX RESCUE TOOLCHAIN", source)
        self.assertIn("PackageAgreementsApproved", source)
        self.assertIn("ReadyForProvisioning", source)
        self.assertIn("Test-TechnicianWorkspacePrerequisite.ps1", source)
        self.assertIn("Test-Administrator", source)
        self.assertIn("--accept-package-agreements", source)
        self.assertIn("--accept-source-agreements", source)

    def test_installers_use_exact_allowlisted_identifiers_and_versions(self) -> None:
        source = self.script_path.read_text(encoding="utf-8")

        self.assertIn("--id", source)
        self.assertIn("--exact", source)
        self.assertIn("-RequiredVersion", source)
        self.assertIn("dist.integrity", source)
        self.assertIn("npmIntegrity", source)
        self.assertIn("--global", source)
        self.assertNotIn("Set-PSRepository", source)
        self.assertNotIn("codex login", source.lower())

    def test_plan_contains_no_credentials_or_cloud_write_actions(self) -> None:
        result = self.run_plan()
        serialized = json.dumps(result).lower()

        for forbidden in (
            "client secret",
            "api key",
            "access token",
            "refresh token",
            "recovery key",
            "autopilot reset",
            "fresh start",
            "wipe",
            "retire",
        ):
            self.assertNotIn(forbidden, serialized)


if __name__ == "__main__":
    unittest.main()
