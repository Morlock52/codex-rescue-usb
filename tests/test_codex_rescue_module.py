from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "PowerShell" / "Modules" / "CodexRescue"


class CodexRescueModuleTests(unittest.TestCase):
    def test_phase_one_public_command_surface_is_complete_and_read_only(self) -> None:
        expected = {
            "Export-CodexRescueLogs",
            "Get-CodexRescueAutopilotStatus",
            "Get-CodexRescueBitLockerStatus",
            "Get-CodexRescueCertificateHealth",
            "Get-CodexRescueDeviceHealth",
            "Get-CodexRescueDriverStatus",
            "Get-CodexRescueEntraStatus",
            "Get-CodexRescueEventErrors",
            "Get-CodexRescueIntuneStatus",
            "Get-CodexRescueNetworkStatus",
            "Get-CodexRescueTpmStatus",
            "Get-CodexRescueWindowsUpdateStatus",
            "Invoke-CodexRescueValidation",
            "New-CodexRescueReport",
        }
        actual = {path.stem for path in (MODULE / "Public").glob("*.ps1")}
        self.assertEqual(expected, actual)
        self.assertNotIn("Invoke-CodexRescueSafeRepair", actual)

    def test_phase_one_diagnostics_do_not_contain_repair_commands(self) -> None:
        diagnostics = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (MODULE / "Public").glob("Get-*.ps1")
        ).lower()
        forbidden = (
            "clear-tpm",
            "disable-bitlocker",
            "remove-bitlockerkeyprotector",
            "dsregcmd.exe /leave",
            "disable-netadapter",
            "enable-netadapter",
            "resetbase",
            "restorehealth",
            "remove-itemproperty",
            "remove-ciminstance",
            "format-volume",
            "clear-disk",
            "initialize-disk",
            "bcdboot.exe",
            "bootrec.exe",
        )
        for command in forbidden:
            with self.subTest(command=command):
                self.assertNotIn(command, diagnostics)

    def test_raw_management_logs_require_exact_separate_consent(self) -> None:
        exporter = (MODULE / "Public" / "Export-CodexRescueLogs.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn("INCLUDE RAW WINDOWS MANAGEMENT LOGS", exporter)
        self.assertIn("-cne $requiredRawLogToken", exporter)
        self.assertIn("RawManagementLogsExcludedFromEscalationZip = $true", exporter)
        self.assertIn("RecoveryMaterialCollected = $false", exporter)
        self.assertIn("CredentialsCollected = $false", exporter)

    def test_validation_rejects_cloud_requests_and_duplicate_checks(self) -> None:
        validator = (
            MODULE / "Public" / "Invoke-CodexRescueValidation.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn("CloudRequestsPerformed -ne 0", validator)
        self.assertIn("SanitizationRequiredBeforeCodex -ne $true", validator)
        self.assertIn("Duplicate diagnostic check", validator)
        self.assertIn("Expected exactly", validator)

    def test_sanitizer_redacts_errors_and_volume_paths(self) -> None:
        sanitizer = (
            MODULE / "Private" / "Protect-CodexRescueAssessment.ps1"
        ).read_text(encoding="utf-8")
        for property_name in ("error(s)?", "exception", "mountpoint", "filepath", "fullpath", "root"):
            with self.subTest(property_name=property_name):
                self.assertIn(property_name, sanitizer)

    def test_online_network_checks_require_exact_consent(self) -> None:
        network = (
            MODULE / "Public" / "Get-CodexRescueNetworkStatus.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn("RUN CODEX RESCUE ONLINE TESTS", network)
        self.assertIn("-cne $requiredToken", network)
        self.assertIn("AdapterAddressesIncluded = $false", network)
        self.assertIn("DnsServerAddressesIncluded = $false", network)

    def test_launcher_imports_checked_in_module_and_validates_before_export(self) -> None:
        launcher = (
            ROOT / "scripts" / "Invoke-CodexRescueReadOnlyAssessment.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn("PowerShell\\Modules\\CodexRescue\\CodexRescue.psd1", launcher)
        self.assertIn("Invoke-CodexRescueValidation", launcher)
        self.assertIn("-Strict", launcher)
        self.assertIn("SupportsShouldProcess", launcher)

    def test_windows_runtime_harness_checks_the_sanitized_export_contract(self) -> None:
        harness = (
            ROOT / "tests" / "windows" / "Test-CodexRescueModule.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn("$commands.Count -eq 14", harness)
        self.assertIn("$validation.CheckCount -eq 10", harness)
        self.assertIn("$assessment.RepairActionsPerformed -eq 0", harness)
        self.assertIn("$assessment.CloudRequestsPerformed -eq 0", harness)
        self.assertIn("$assessment.OnlineNetworkTestsPerformed -eq $false", harness)
        self.assertIn("$intuneRawFiles.Count -eq 0", harness)
        self.assertIn("$eventRawFiles.Count -eq 0", harness)
        self.assertIn("$entryNames.Count -eq 3", harness)
        self.assertIn("A prohibited pattern was found in the sanitized ZIP", harness)


if __name__ == "__main__":
    unittest.main()
