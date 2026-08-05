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


if __name__ == "__main__":
    unittest.main()
