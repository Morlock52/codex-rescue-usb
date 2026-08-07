from pathlib import Path
from html import unescape
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
ORCHESTRATOR = ROOT / "orchestrator"
CONTRACTS = ORCHESTRATOR / "src" / "CodexRescue.Contracts"
BROKER = ORCHESTRATOR / "src" / "CodexRescue.Broker"
APP = ORCHESTRATOR / "src" / "CodexRescue.Orchestrator"


class DotNetOrchestratorSourceTests(unittest.TestCase):
    def test_solution_contains_three_versioned_assemblies(self) -> None:
        solution = ORCHESTRATOR / "CodexRescue.Orchestrator.sln"
        self.assertTrue(solution.is_file())

        expected_projects = (
            CONTRACTS / "CodexRescue.Contracts.csproj",
            BROKER / "CodexRescue.Broker.csproj",
            APP / "CodexRescue.Orchestrator.csproj",
        )
        for project in expected_projects:
            self.assertTrue(project.is_file(), project)

        app_project = (APP / "CodexRescue.Orchestrator.csproj").read_text(
            encoding="utf-8"
        )
        self.assertIn("<TargetFramework>net8.0-windows", app_project)
        self.assertIn("<UseWPF>true</UseWPF>", app_project)
        self.assertIn("<SelfContained>true</SelfContained>", app_project)

    def test_contracts_define_all_v1_wire_models_without_secret_fields(self) -> None:
        source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted(CONTRACTS.rglob("*.cs"))
        )

        for contract in (
            "ActionPlanV1",
            "ActionReceiptV1",
            "CheckpointV1",
            "ReleaseManifestV1",
            "ProxmoxProfileV1",
            "TelemetryEnvelopeV1",
        ):
            self.assertIn(f"record {contract}", source)

        proxmox = (CONTRACTS / "ProxmoxProfileV1.cs").read_text(encoding="utf-8")
        for forbidden in ("Token", "Password", "Secret"):
            self.assertNotIn(f" {forbidden}", proxmox)

        telemetry = (CONTRACTS / "TelemetryEnvelopeV1.cs").read_text(
            encoding="utf-8"
        )
        for forbidden in (
            "UserName",
            "HostName",
            "DiskIdentifier",
            "IpAddress",
            "FileName",
            "RawError",
            "CommandOutput",
            "Prompt",
            "Credential",
            "RecoveryMaterial",
        ):
            self.assertNotIn(forbidden, telemetry)

    def test_broker_is_typed_allowlisted_and_exposes_no_shell_escape_hatch(self) -> None:
        source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted(BROKER.rglob("*.cs"))
        )

        self.assertIn("enum BrokerOperation", source)
        self.assertIn("IReadOnlyDictionary<BrokerOperation", source)
        self.assertIn("ValidateForExecution", source)
        self.assertIn("ManifestDigest", source)
        self.assertIn("ExpiresAtUtc", source)

        for forbidden in (
            "cmd.exe",
            "powershell.exe -Command",
            "ProcessStartInfo(\"powershell",
            "UserCommand",
            "ScriptPath",
            "ExecutablePath",
        ):
            self.assertNotIn(forbidden, source)

    def test_checkpoint_and_telemetry_services_enforce_safe_defaults(self) -> None:
        checkpoint = (APP / "Services" / "CheckpointProtector.cs").read_text(
            encoding="utf-8"
        )
        telemetry = (APP / "Services" / "TelemetryPolicy.cs").read_text(
            encoding="utf-8"
        )

        self.assertIn("HMACSHA256", checkpoint)
        self.assertIn("DataProtectionScope.LocalMachine", checkpoint)
        self.assertIn("FixedTimeEquals", checkpoint)

        self.assertIn("EnabledByDefault = false", telemetry)
        self.assertIn("AdministratorPolicyAllows", telemetry)
        self.assertIn("OperatorConsent", telemetry)
        self.assertIn("AllowedEventNames", telemetry)
        self.assertIn("TelemetryEnvelopeV1", telemetry)

    def test_wpf_shell_exposes_the_complete_guided_and_expert_workflow(self) -> None:
        main_window = APP / "MainWindow.xaml"
        source = main_window.read_text(encoding="utf-8")
        ET.fromstring(source)
        rendered_source = unescape(source)

        for label in (
            "Setup & Updates",
            "Build Matrix",
            "Proxmox Test Lab",
            "USB Target Confirmation",
            "UEFI Backup & Repair",
            "BitLocker Salvage",
            "Verification & Receipts",
            "Guided",
            "Expert",
            "ENTERPRISE TECHNICAL PREVIEW",
        ):
            self.assertIn(label, rendered_source)

        resources = (APP / "Themes" / "DesignTokens.xaml").read_text(
            encoding="utf-8"
        )
        ET.fromstring(resources)
        self.assertIn("Atkinson Hyperlegible", resources)
        self.assertIn("IBM Plex Mono", resources)
        self.assertIn('x:Key="FocusRingBrush"', resources)
        self.assertIn('x:Key="MinimumTargetSize">44', resources)


if __name__ == "__main__":
    unittest.main()
