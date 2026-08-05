from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
XAML = ROOT / "PowerShell" / "Dashboard" / "CodexRescueDashboard.xaml"
SCRIPT = ROOT / "scripts" / "Open-CodexRescueDashboard.ps1"
LAUNCHER = ROOT / "scripts" / "Open-CodexRescueDashboard.cmd"


class WpfDashboardTests(unittest.TestCase):
    def test_xaml_is_valid_and_binds_all_structured_check_cards(self) -> None:
        source = XAML.read_text(encoding="utf-8")
        ET.fromstring(source)

        self.assertIn('ItemsSource="{Binding CheckCards}"', source)
        self.assertIn('ItemsSource="{Binding TimelineEntries}"', source)
        self.assertIn('Text="{Binding HealthScoreText}"', source)
        self.assertIn('Text="{Binding NetworkStateBadge}"', source)
        self.assertIn('Text="{Binding CloudStateBadge}"', source)
        self.assertIn('Width="1200"', source)
        self.assertIn('Height="740"', source)

    def test_dashboard_has_separate_report_controls_and_no_repair_control(self) -> None:
        source = XAML.read_text(encoding="utf-8")

        self.assertIn('x:Name="OpenDetailedReportButton"', source)
        self.assertIn('x:Name="ShowSanitizedZipButton"', source)
        self.assertIn('APPROVAL GATE CLOSED', source)
        self.assertNotIn('Run Repair', source)
        self.assertNotIn('Invoke-CodexRescueSafeRepair', source)

    def test_launcher_uses_sta_windows_powershell(self) -> None:
        launcher = LAUNCHER.read_text(encoding="utf-8")

        self.assertIn("powershell.exe", launcher)
        self.assertIn("-Sta", launcher)
        self.assertIn("Open-CodexRescueDashboard.ps1", launcher)

    def test_dashboard_validates_structured_assessment_before_rendering(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8")

        self.assertIn("Get-CodexRescueDeviceHealth", script)
        self.assertIn("ConvertFrom-Json", script)
        self.assertIn("Invoke-CodexRescueValidation -Assessment $assessment -Strict", script)
        self.assertIn("New-CodexRescueDashboardModel", script)
        self.assertNotIn("Format-Table", script)
        self.assertNotIn("Out-String", script)

    def test_dashboard_preserves_offline_and_no_automatic_handoff_boundaries(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8")

        self.assertIn("RepairControlsAvailable = $false", script)
        self.assertIn("AutomaticCodexUpload = $false", script)
        self.assertIn("CloudStateBadge = 'CLOUD DISABLED'", script)
        self.assertNotIn("Connect-MgGraph", script)
        self.assertNotIn("Invoke-WebRequest", script)
        self.assertNotIn("Start-BitsTransfer", script)
        self.assertTrue(script.isascii())


if __name__ == "__main__":
    unittest.main()
