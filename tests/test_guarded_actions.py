from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
USB = ROOT / "scripts" / "Write-CodexRescueUsb.ps1"
UEFI = ROOT / "scripts" / "Invoke-CodexRescueUefiRepair.ps1"
SALVAGE = ROOT / "scripts" / "Invoke-CodexRescueBitLockerSalvage.ps1"


class GuardedActionTests(unittest.TestCase):
    def test_usb_writer_rejects_unsafe_or_changed_disk_identity(self) -> None:
        source = USB.read_text(encoding="utf-8")
        for gate in (
            "IsBoot",
            "IsSystem",
            "IsOffline",
            "IsReadOnly",
            "BusType",
            "USB",
            "page-file",
            "virtual",
            "Get-TargetFingerprint",
            "Re-scan",
            "Identity changed",
        ):
            self.assertIn(gate, source)
        self.assertIn("Get-Disk -Number $DiskNumber", source)
        self.assertNotIn("Get-Disk |", source)

    def test_usb_writer_verifies_iso_then_requires_target_bound_phrase(self) -> None:
        source = USB.read_text(encoding="utf-8")
        self.assertIn("VerificationSucceeded", source)
        self.assertIn("IsoSha256", source)
        self.assertIn("Get-FileHash", source)
        self.assertIn("ERASE USB DISK", source)
        self.assertIn("ConfirmationPhrase", source)
        self.assertLess(source.index("Identity changed"), source.index("Clear-Disk"))
        self.assertLess(source.index("ConfirmationPhrase"), source.index("Clear-Disk"))

    def test_usb_writer_uses_builtin_gpt_fat32_and_readback_verification(self) -> None:
        source = USB.read_text(encoding="utf-8")
        for operation in (
            "Clear-Disk",
            "Initialize-Disk",
            "New-Partition",
            "Format-Volume",
            "FAT32",
            "Mount-DiskImage",
            "-Access ReadOnly",
            "Copy-Item",
            "Readback",
            "ActionReceiptV1",
        ):
            self.assertIn(operation, source)
        self.assertNotIn("Invoke-Expression", source)

    def test_usb_writer_rechecks_cleared_state_and_uses_actual_free_extent(self) -> None:
        source = USB.read_text(encoding="utf-8")
        self.assertIn("Disk did not become RAW after Clear-Disk", source)
        self.assertIn("PartitionStyle -cne 'RAW'", source)
        self.assertIn("LargestFreeExtent", source)
        self.assertIn("-UseMaximumSize", source)
        self.assertLess(
            source.index("Disk did not become RAW after Clear-Disk"),
            source.index("Initialize-Disk"),
        )

    def test_uefi_repair_requires_unambiguous_pair_and_readable_backup(self) -> None:
        source = UEFI.read_text(encoding="utf-8")
        for gate in (
            "WindowsCandidates.Count -ne 1",
            "EfiCandidates.Count -ne 1",
            "FAT32",
            "BackupDirectory",
            "BackupManifest",
            "Get-FileHash",
            "Expand-Archive",
            "TargetFingerprint",
            "Identity changed",
        ):
            self.assertIn(gate, source)

    def test_uefi_repair_executes_only_minimal_bcdboot_and_has_rollback(self) -> None:
        source = UEFI.read_text(encoding="utf-8")
        self.assertIn("REPAIR UEFI", source)
        self.assertIn("bcdboot.exe", source)
        self.assertIn("'/s'", source)
        self.assertIn("'/f'", source)
        self.assertIn("'UEFI'", source)
        self.assertIn("Rollback", source)
        for forbidden in ("bootrec", "sfc.exe", "dism.exe", "/import"):
            self.assertNotIn(forbidden, source.lower())

    def test_uefi_prepare_saves_and_validates_a_locked_live_bcd_store(self) -> None:
        source = UEFI.read_text(encoding="utf-8")
        for operation in (
            "Registry::HKEY_LOCAL_MACHINE\\BCD00000000",
            "reg.exe",
            "'save'",
            "Saved BCD validation failed",
        ):
            self.assertIn(operation, source)
        self.assertIn("bcdedit.exe '/store' $backupBcdPath '/enum' '{bootmgr}'", source)
        self.assertLess(source.index("reg.exe"), source.index("Saved BCD validation failed"))

    def test_bitlocker_salvage_uses_only_bek_material_and_fixed_staging_names(self) -> None:
        source = SALVAGE.read_text(encoding="utf-8")
        self.assertIn("*.bek", source)
        self.assertIn("*.kpg", source)
        self.assertIn("recovery-material.bek", source)
        self.assertIn("key-package.kpg", source)
        self.assertIn("repair-bde.exe", source)
        self.assertIn("'-rk'", source)
        self.assertIn("'-kp'", source)
        self.assertNotIn("'-rp'", source)
        self.assertNotIn("RecoveryPassword", source)
        self.assertNotIn("Start-Transcript", source)

    def test_bitlocker_salvage_proves_distinct_blank_sized_output_and_marker(self) -> None:
        source = SALVAGE.read_text(encoding="utf-8")
        for gate in (
            "SourceDiskNumber -eq $OutputDiskNumber",
            "output disk is not blank",
            "OutputDisk.Size -lt $SourceDisk.Size",
            "OVERWRITE SALVAGE DISK",
            "Identity changed",
            "KnownMarkerSha256",
            "Get-FileHash",
            "ActionReceiptV1",
        ):
            self.assertIn(gate, source)
        self.assertLess(source.index("Identity changed"), source.index("repair-bde.exe"))


if __name__ == "__main__":
    unittest.main()
