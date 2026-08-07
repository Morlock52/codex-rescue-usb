from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "orchestrator" / "src" / "CodexRescue.Orchestrator"


class SupportBundleSourceTests(unittest.TestCase):
    def test_export_is_new_sanitized_zip_and_never_copies_raw_receipts(self) -> None:
        source = (APP / "Services" / "SupportBundleExporter.cs").read_text(
            encoding="utf-8"
        )
        self.assertIn("ZipArchive", source)
        self.assertIn("CreateNew", source)
        self.assertIn("ActionReceiptV1.SupportedSchemaVersion", source)
        self.assertIn("ContainsRecoveryMaterial", source)
        self.assertIn("support-summary.json", source)
        self.assertNotIn("CreateEntryFromFile", source)
        self.assertIn("BeforeEvidence.Count", source)
        self.assertIn("AfterEvidence.Count", source)
        self.assertNotIn("CreateEntry(\"receipt", source)
        self.assertIn('TryGetProperty("ActionId"', source)
        self.assertIn('TryGetProperty("VerificationSucceeded"', source)

    def test_receipts_ui_has_operator_visible_export_handler(self) -> None:
        xaml = (APP / "MainWindow.xaml").read_text(encoding="utf-8")
        code = (APP / "MainWindow.xaml.cs").read_text(encoding="utf-8")
        self.assertIn('Content="Export support bundle"', xaml)
        self.assertIn('Click="ExportSupportBundle_Click"', xaml)
        self.assertIn("ExportSupportBundle_Click", code)


if __name__ == "__main__":
    unittest.main()
