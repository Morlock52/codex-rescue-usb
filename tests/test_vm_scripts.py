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


if __name__ == "__main__":
    unittest.main()
