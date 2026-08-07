from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "orchestrator" / "src" / "CodexRescue.Orchestrator"


class OrchestratorTelemetrySourceTests(unittest.TestCase):
    def test_otlp_queue_is_opt_in_https_allowlisted_and_clearable(self) -> None:
        source = (APP / "Services" / "TelemetryQueueService.cs").read_text(
            encoding="utf-8"
        )
        self.assertIn("OpenTelemetry.Exporter.OpenTelemetryProtocol", (APP / "CodexRescue.Orchestrator.csproj").read_text(encoding="utf-8"))
        self.assertIn("Uri.UriSchemeHttps", source)
        self.assertIn("CanTransmit", source)
        self.assertIn("ResourceBuilder.CreateEmpty", source)
        self.assertIn("ClearQueue", source)
        self.assertIn("Disable", source)
        self.assertIn("TestEndpoint", source)
        self.assertNotIn("Environment.MachineName", source)
        self.assertNotIn("Environment.UserName", source)

    def test_ui_shows_exact_fields_and_all_operator_controls(self) -> None:
        xaml = (APP / "MainWindow.xaml").read_text(encoding="utf-8")
        code = (APP / "MainWindow.xaml.cs").read_text(encoding="utf-8")
        for label in ("Exact outgoing fields", "Disable", "Clear queue", "Test endpoint"):
            self.assertIn(label, xaml)
        for handler in ("DisableTelemetry_Click", "ClearTelemetry_Click", "TestTelemetry_Click"):
            self.assertIn(handler, code)


if __name__ == "__main__":
    unittest.main()
