from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class WinPEScriptSafetyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.collector = (ROOT / "winpe" / "Collect-RescueEvidence.cmd").read_text(
            encoding="utf-8"
        )
        self.startup = (ROOT / "winpe" / "startnet.cmd").read_text(encoding="utf-8")
        self.manifest = (ROOT / "winpe" / "New-EvidenceManifest.ps1").read_text(
            encoding="utf-8"
        )
        self.builder = (ROOT / "scripts" / "Build-RescueIso.ps1").read_text(
            encoding="utf-8"
        )
        self.unlocker = (
            ROOT / "winpe" / "Unlock-BitLockerWithRecoveryKey.cmd"
        ).read_text(encoding="utf-8")

    def test_destination_requires_explicit_marker_before_writing(self) -> None:
        marker_check = self.collector.index("CODEX_EVIDENCE.DEST")
        output_assignment = self.collector.index("CodexRescueEvidence")
        first_diagnostic = self.collector.index("diskpart /s")

        self.assertLess(marker_check, output_assignment)
        self.assertLess(output_assignment, first_diagnostic)

    def test_ram_drive_and_existing_package_are_rejected(self) -> None:
        drive_scan = self.collector.split("for %%D in (", 1)[1].split(") do", 1)[0]
        self.assertNotIn("C", drive_scan.split())
        self.assertNotIn("X", drive_scan.split())
        self.assertIn('if exist "!OUT!" goto :existing', self.collector)
        self.assertIn("No evidence was overwritten.", self.collector)

    def test_exactly_one_prepared_destination_is_required(self) -> None:
        self.assertIn('if "!DEST_COUNT!"=="0" goto :unprepared', self.collector)
        self.assertIn('if not "!DEST_COUNT!"=="1" goto :ambiguous', self.collector)

    def test_startup_banner_describes_the_enforced_marker_gate(self) -> None:
        self.assertIn("CODEX_EVIDENCE.DEST", self.startup)
        self.assertNotIn("only to a removable drive", self.startup)

    def test_driver_inventory_uses_winpe_supported_dism(self) -> None:
        self.assertIn("dism /Online /Get-Drivers /Format:Table", self.collector)
        self.assertNotIn("driverquery", self.collector)

    def test_evidence_manifest_runs_after_collection_and_is_failure_gated(self) -> None:
        first_diagnostic = self.collector.index("diskpart /s")
        manifest_call = self.collector.index("New-EvidenceManifest.ps1")

        self.assertLess(first_diagnostic, manifest_call)
        self.assertIn("if errorlevel 1 goto :manifestfailed", self.collector)
        self.assertIn("package is incomplete", self.collector)

    def test_manifest_revalidates_destination_and_hashes_evidence(self) -> None:
        self.assertIn("CODEX_EVIDENCE.DEST", self.manifest)
        self.assertIn("CodexRescueEvidence", self.manifest)
        self.assertIn("Get-FileHash", self.manifest)
        self.assertIn("manifest.json", self.manifest)
        self.assertIn("SHA256SUMS.txt", self.manifest)

    def test_manifest_marks_the_winpe_clock_as_unvalidated(self) -> None:
        self.assertIn("ClockSource = 'WinPE system clock'", self.manifest)
        self.assertIn("ClockExternallyValidated = $false", self.manifest)

    def test_builder_adds_supported_powershell_dependencies_in_order(self) -> None:
        components = (
            "WinPE-WMI",
            "WinPE-SecureStartup",
            "WinPE-NetFx",
            "WinPE-Scripting",
            "WinPE-PowerShell",
        )
        positions = [self.builder.index(component) for component in components]

        self.assertEqual(positions, sorted(positions))
        self.assertIn("/Add-Package", self.builder)
        self.assertIn("New-EvidenceManifest.ps1", self.builder)
        self.assertIn('"/Image:$mount"', self.builder)
        self.assertIn('"/PackagePath:$componentCab"', self.builder)
        self.assertNotIn("'/Image:' + $mount", self.builder)

    def test_bitlocker_unlock_requires_exact_local_key_and_target_gates(self) -> None:
        self.assertIn("CODEX_BITLOCKER.KEY", self.unlocker)
        self.assertIn('if not "!KEYDRIVE_COUNT!"=="1"', self.unlocker)
        self.assertIn('if not "!KEYFILE_COUNT!"=="1"', self.unlocker)
        self.assertIn('UNLOCK !TARGET!:', self.unlocker)
        self.assertIn('-RecoveryKey "!KEYFILE!"', self.unlocker)
        self.assertIn('-RecoveryKey "!KEYFILE!" >nul 2>&1', self.unlocker)
        self.assertNotIn("-RecoveryPassword", self.unlocker)
        self.assertIn('pushd "!TARGET!:\\"', self.unlocker)
        self.assertIn("status display above is informational", self.unlocker)

    def test_bitlocker_unlock_blocks_system_and_ram_drives_without_logging(self) -> None:
        target_scan = self.unlocker.split("for %%D in (", 1)[1].split(") do", 1)[0]
        self.assertNotIn("C", target_scan.split())
        self.assertNotIn("X", target_scan.split())
        self.assertNotIn("Start-Transcript", self.unlocker)
        self.assertNotIn(">>", self.unlocker)
        self.assertIn('set "KEYFILE="', self.unlocker)


if __name__ == "__main__":
    unittest.main()
