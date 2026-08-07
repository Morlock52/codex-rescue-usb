from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "orchestrator" / "src" / "CodexRescue.Orchestrator"


class OrchestratorUpdateUiSourceTests(unittest.TestCase):
    def test_setup_ui_exposes_explicit_online_offline_and_close_controls(self) -> None:
        xaml = (APP / "MainWindow.xaml").read_text(encoding="utf-8")
        code = (APP / "MainWindow.xaml.cs").read_text(encoding="utf-8")
        for label in (
            "Open 30-minute window",
            "Check signed release",
            "Import offline bundle",
            "Close window",
        ):
            self.assertIn(label, xaml)
        for handler in (
            "OpenMaintenance_Click",
            "CheckRelease_Click",
            "ImportOfflineBundle_Click",
            "CloseMaintenance_Click",
        ):
            self.assertIn(handler, code)

    def test_update_identity_comes_from_installed_signed_package(self) -> None:
        source = (APP / "Services" / "PublisherIdentityService.cs").read_text(
            encoding="utf-8"
        )
        self.assertIn("Package.Current.Id.Publisher", source)
        self.assertIn("signed MSIX package context", source)
        self.assertNotIn("Thumbprint", source)


if __name__ == "__main__":
    unittest.main()
