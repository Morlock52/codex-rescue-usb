from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "Open-PhysicalUsbReadinessGui.ps1"
LAUNCHER = ROOT / "scripts" / "Open-PhysicalUsbReadinessGui.cmd"


class PhysicalUsbReadinessTests(unittest.TestCase):
    def test_gui_validates_the_release_iso_and_exactly_one_usb_disk(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8")

        self.assertIn(
            "5E2E1F90765DF00BAA3F9EA66282DBB4A1C981B87FBCAD9C6533ABF66AC58089",
            script,
        )
        self.assertIn("Get-FileHash -LiteralPath $resolvedIso", script)
        self.assertIn("-Algorithm SHA256", script)
        self.assertIn("Get-Disk", script)
        self.assertIn("$_.BusType -eq 'USB'", script)
        self.assertIn("!$_.IsBoot", script)
        self.assertIn("!$_.IsSystem", script)
        self.assertIn("!$_.IsOffline", script)
        self.assertIn("!$_.IsReadOnly", script)
        self.assertIn("$eligibleDisks.Count -ne 1", script)
        self.assertIn("UniqueId", script)
        self.assertIn("SerialNumber", script)

    def test_gui_requires_fresh_operator_confirmation_and_writes_only_a_plan(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8")

        self.assertIn("I confirmed the disk number, model, serial, and size", script)
        self.assertIn("$confirmationCheckBox.Checked = $false", script)
        self.assertIn("SaveFileDialog", script)
        self.assertIn("Test-Path -LiteralPath $planPath", script)
        self.assertIn("Get-Partition -DriveLetter", script)
        self.assertIn("$destinationDisk.BusType -eq 'USB'", script)
        self.assertIn("The plan must be saved to local non-USB storage", script)
        self.assertIn("ConvertTo-Json", script)
        self.assertIn("WritePerformed = $false", script)
        self.assertIn("ExternalWriterRequired = $true", script)
        self.assertIn("OperatorConfirmationRecorded = $true", script)
        self.assertIn("does not authorize erasing or writing", script)

    def test_gui_contains_no_disk_mutation_or_writer_launch_operations(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8").lower()

        for forbidden in (
            "clear-disk",
            "initialize-disk",
            "new-partition",
            "format-volume",
            "remove-partition",
            "set-disk",
            "diskpart",
            "physicaldrive",
            "start-process",
            "invoke-webrequest",
            "invoke-restmethod",
        ):
            self.assertNotIn(forbidden, script)

    def test_cmd_launcher_uses_sta_for_windows_forms(self) -> None:
        launcher = LAUNCHER.read_text(encoding="utf-8")

        self.assertIn("powershell.exe", launcher)
        self.assertIn("-STA", launcher)
        self.assertIn("Open-PhysicalUsbReadinessGui.ps1", launcher)


if __name__ == "__main__":
    unittest.main()
