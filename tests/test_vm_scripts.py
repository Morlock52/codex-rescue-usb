from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BuildVmScriptTests(unittest.TestCase):
    def test_repair_accepts_already_current_pnputil_result(self) -> None:
        repair = (ROOT / "scripts" / "Repair-BuildVm.ps1").read_text(
            encoding="utf-8"
        )

        self.assertIn("0, 259", repair)
        self.assertIn("Already exists in the system", repair)
        self.assertIn("Start-Service -Name $agentService.Name", repair)
        self.assertNotIn("Restart-Service", repair)

    def test_toolchain_accepts_winget_no_upgrade_result(self) -> None:
        installer = (ROOT / "scripts" / "Install-BuildVmToolchain.ps1").read_text(
            encoding="utf-8"
        )

        self.assertIn("$noApplicableUpgradeExitCode", installer)
        self.assertIn("AlreadyCurrent", installer)

    def test_bitlocker_fixture_requires_new_exact_size_disks_and_token(self) -> None:
        fixture = (ROOT / "scripts" / "New-BitLockerTestFixture.ps1").read_text(
            encoding="utf-8"
        )

        self.assertIn("PartitionStyle -ne 'RAW'", fixture)
        self.assertIn("Refusing boot or system disk", fixture)
        self.assertIn("expected disposable 3 GiB disk", fixture)
        self.assertIn("expected disposable 1 GiB disk", fixture)
        self.assertIn("CREATE DISPOSABLE BITLOCKER FIXTURE", fixture)
        self.assertIn("SupportsShouldProcess", fixture)
        self.assertIn("PreventDeviceEncryption", fixture)
        self.assertIn("Both disposable volumes must be fully decrypted", fixture)
        self.assertIn("-RecoveryKeyProtector", fixture)

    def test_bitlocker_fixture_records_no_recovery_material(self) -> None:
        fixture = (ROOT / "scripts" / "New-BitLockerTestFixture.ps1").read_text(
            encoding="utf-8"
        )

        self.assertIn("ExternalKeyFileCount", fixture)
        self.assertIn("KeyVolumeEncryptionState", fixture)
        self.assertIn("-Recurse -Force", fixture)
        self.assertIn("ContainsRecoveryMaterial = $false", fixture)
        self.assertNotIn("RecoveryPassword", fixture)
        self.assertNotIn("externalKeyFiles[0]", fixture)

    def test_codex_workspace_launcher_requires_package_and_exact_consent(self) -> None:
        launcher = (
            ROOT / "scripts" / "Open-CodexRecoveryWorkspace.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("Get-AppxPackage", launcher)
        self.assertIn("Get-AppxPackage -AllUsers", launcher)
        self.assertIn("OpenAI.Codex", launcher)
        self.assertIn("START CODEX RECOVERY WORKSPACE", launcher)
        self.assertIn("NetworkConsentGranted", launcher)
        self.assertIn("Start-Process 'codex:'", launcher)
        self.assertIn("AuditOnly", launcher)

    def test_codex_workspace_launcher_never_imports_recovery_material(self) -> None:
        launcher = (
            ROOT / "scripts" / "Open-CodexRecoveryWorkspace.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("AutomaticEvidenceImport = $false", launcher)
        self.assertIn("RecoveryMaterialAllowed = $false", launcher)
        self.assertNotIn("RecoveryPassword", launcher)
        self.assertNotIn("*.bek", launcher)
        self.assertNotIn("CODEX_BITLOCKER.KEY", launcher)
        self.assertNotIn("Invoke-WebRequest", launcher)

    def test_codex_workspace_cmd_runs_the_guarded_powershell_launcher(self) -> None:
        launcher = (
            ROOT / "scripts" / "Open-CodexRecoveryWorkspace.cmd"
        ).read_text(encoding="utf-8")

        self.assertIn("Open-CodexRecoveryWorkspace.ps1", launcher)
        self.assertIn("-ExecutionPolicy Bypass", launcher)


if __name__ == "__main__":
    unittest.main()
