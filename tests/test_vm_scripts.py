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

    def test_bitlocker_fixture_requires_new_exact_size_disks_and_token(self) -> None:
        fixture = (ROOT / "scripts" / "New-BitLockerTestFixture.ps1").read_text(
            encoding="utf-8"
        )

        self.assertIn("PartitionStyle -ne 'RAW'", fixture)
        self.assertIn("Refusing boot or system disk", fixture)
        self.assertIn("expected disposable 3 GiB disk", fixture)
        self.assertIn("expected disposable 1 GiB disk", fixture)
        self.assertIn("CREATE DISPOSABLE BITLOCKER FIXTURE", fixture)
        self.assertIn("SupportsShouldProcess", fixture)
        self.assertIn("PreventDeviceEncryption", fixture)
        self.assertIn("Both disposable volumes must be fully decrypted", fixture)
        self.assertIn("-RecoveryKeyProtector", fixture)

    def test_bitlocker_fixture_records_no_recovery_material(self) -> None:
        fixture = (ROOT / "scripts" / "New-BitLockerTestFixture.ps1").read_text(
            encoding="utf-8"
        )

        self.assertIn("ExternalKeyFileCount", fixture)
        self.assertIn("KeyVolumeEncryptionState", fixture)
        self.assertIn("-Recurse -Force", fixture)
        self.assertIn("ContainsRecoveryMaterial = $false", fixture)
        self.assertNotIn("RecoveryPassword", fixture)
        self.assertNotIn("externalKeyFiles[0]", fixture)

    def test_recovery_password_fixture_requires_one_new_exact_disk_and_console(self) -> None:
        fixture = (
            ROOT / "scripts" / "New-BitLockerRecoveryPasswordFixture.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("PartitionStyle -ne 'RAW'", fixture)
        self.assertIn("Refusing boot or system disk", fixture)
        self.assertIn("expected disposable 1 GiB disk", fixture)
        self.assertIn("CREATE DISPOSABLE RECOVERY PASSWORD FIXTURE", fixture)
        self.assertIn("SupportsShouldProcess", fixture)
        self.assertIn("[Console]::IsInputRedirected", fixture)
        self.assertIn("[Console]::IsOutputRedirected", fixture)
        self.assertIn("Do not run this command through Codex", fixture)

    def test_recovery_password_fixture_keeps_secret_out_of_parent_and_audit(self) -> None:
        fixture = (
            ROOT / "scripts" / "New-BitLockerRecoveryPasswordFixture.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("manage-bde.exe", fixture)
        self.assertIn("-RecoveryPassword", fixture)
        self.assertIn("-UsedSpaceOnly", fixture)
        self.assertIn("-SkipHardwareTest", fixture)
        self.assertIn("Start-Process", fixture)
        self.assertIn("-Wait", fixture)
        self.assertIn("RecoveryPasswordProtectorCount", fixture)
        self.assertIn("ContainsRecoveryMaterial = $false", fixture)
        self.assertNotIn("GetKeyProtectorNumericalPassword", fixture)
        self.assertNotIn("Set-Clipboard", fixture)
        self.assertNotIn("Start-Transcript", fixture)

    def test_codex_workspace_launcher_requires_package_and_exact_consent(self) -> None:
        launcher = (
            ROOT / "scripts" / "Open-CodexRecoveryWorkspace.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("Get-AppxPackage", launcher)
        self.assertIn("Get-AppxPackage -AllUsers", launcher)
        self.assertIn("OpenAI.Codex", launcher)
        self.assertIn("START CODEX RECOVERY WORKSPACE", launcher)
        self.assertIn("NetworkConsentGranted", launcher)
        self.assertIn("Start-Process 'codex:'", launcher)
        self.assertIn("AuditOnly", launcher)

    def test_codex_workspace_launcher_never_imports_recovery_material(self) -> None:
        launcher = (
            ROOT / "scripts" / "Open-CodexRecoveryWorkspace.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("AutomaticEvidenceImport = $false", launcher)
        self.assertIn("RecoveryMaterialAllowed = $false", launcher)
        self.assertNotIn("RecoveryPassword", launcher)
        self.assertNotIn("*.bek", launcher)
        self.assertNotIn("CODEX_BITLOCKER.KEY", launcher)
        self.assertNotIn("Invoke-WebRequest", launcher)

    def test_codex_workspace_cmd_runs_the_guarded_powershell_launcher(self) -> None:
        launcher = (
            ROOT / "scripts" / "Open-CodexRecoveryWorkspace.cmd"
        ).read_text(encoding="utf-8")

        self.assertIn("Open-CodexRecoveryWorkspace.ps1", launcher)
        self.assertIn("-ExecutionPolicy Bypass", launcher)

    def test_network_gate_requires_exact_adapter_and_action_token(self) -> None:
        gate = (ROOT / "scripts" / "Set-CodexRecoveryNetwork.ps1").read_text(
            encoding="utf-8"
        )

        self.assertIn("Get-NetAdapter -IncludeHidden", gate)
        self.assertIn("Where-Object HardwareInterface -eq $true", gate)
        self.assertIn("InterfaceIndex", gate)
        self.assertIn("DISABLE-CODEX-RECOVERY-NETWORK", gate)
        self.assertIn("ENABLE-CODEX-RECOVERY-NETWORK", gate)
        self.assertIn("SupportsShouldProcess", gate)
        self.assertIn("Test-Administrator", gate)

    def test_network_gate_changes_only_the_selected_adapter(self) -> None:
        gate = (ROOT / "scripts" / "Set-CodexRecoveryNetwork.ps1").read_text(
            encoding="utf-8"
        )

        self.assertIn("Disable-NetAdapter -Name $adapter.Name -IncludeHidden", gate)
        self.assertIn("Enable-NetAdapter -Name $adapter.Name -IncludeHidden", gate)
        self.assertIn("Where-Object ifIndex -eq $InterfaceIndex", gate)
        self.assertIn("'Not Present'", gate)
        self.assertNotIn("Disable-NetAdapter *", gate)
        self.assertNotIn("Enable-NetAdapter *", gate)
        self.assertNotIn("Invoke-WebRequest", gate)

    def test_offline_startup_policy_is_exact_scoped_and_rollback_capable(self) -> None:
        policy = (
            ROOT / "scripts" / "Set-CodexRecoveryOfflineStartup.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("New-ScheduledTaskTrigger -AtStartup", policy)
        self.assertIn("New-ScheduledTaskPrincipal -UserId 'SYSTEM'", policy)
        self.assertIn("Get-NetAdapter -IncludeHidden", policy)
        self.assertIn("Where-Object HardwareInterface -eq `$true", policy)
        self.assertIn("Where-Object ifIndex -eq $InterfaceIndex", policy)
        self.assertIn(
            "Disable-NetAdapter -Name `$matches[0].Name -IncludeHidden", policy
        )
        self.assertIn("'Not Present'", policy)
        self.assertIn("INSTALL-CODEX-RECOVERY-OFFLINE-BOOT", policy)
        self.assertIn("REMOVE-CODEX-RECOVERY-OFFLINE-BOOT", policy)
        self.assertIn("Unregister-ScheduledTask -TaskName $taskName", policy)
        self.assertNotIn("Disable-NetAdapter *", policy)
        self.assertNotIn("Invoke-WebRequest", policy)

    def test_offline_startup_policy_locks_its_system_task_script(self) -> None:
        policy = (
            ROOT / "scripts" / "Set-CodexRecoveryOfflineStartup.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("Join-Path $env:ProgramData 'CodexRescue'", policy)
        self.assertIn("icacls.exe", policy)
        self.assertIn("S-1-5-18:(OI)(CI)(F)", policy)
        self.assertIn("S-1-5-32-544:(OI)(CI)(F)", policy)
        self.assertIn("S-1-5-32-545:(OI)(CI)(RX)", policy)
        self.assertIn("Set-Content -LiteralPath $policyPath", policy)

    def test_codex_evidence_summary_verifies_manifest_and_checksum_list(self) -> None:
        summary = (ROOT / "scripts" / "New-CodexEvidenceSummary.ps1").read_text(
            encoding="utf-8"
        )

        self.assertIn("manifest.json", summary)
        self.assertIn("SHA256SUMS.txt", summary)
        self.assertIn("Get-FileHash", summary)
        self.assertIn("SchemaVersion -ne 1", summary)
        self.assertIn("expectedDiagnosticFiles", summary)
        self.assertIn("windows-installations.json", summary)
        self.assertIn("expectedChecksumCount", summary)
        self.assertIn("must not contain directories", summary)
        self.assertIn("Refusing to write the summary inside", summary)

    def test_codex_evidence_summary_excludes_raw_sensitive_details(self) -> None:
        summary = (ROOT / "scripts" / "New-CodexEvidenceSummary.ps1").read_text(
            encoding="utf-8"
        )

        self.assertIn("RawNetworkDetailsIncluded: false", summary)
        self.assertIn("RecoveryMaterialIncluded: false", summary)
        self.assertIn("SourceClockExternallyValidated: false", summary)
        self.assertIn("recoveryPasswordPattern", summary)
        self.assertNotIn("Invoke-WebRequest", summary)
        self.assertNotIn("Start-Process", summary)
        self.assertNotIn("Get-NetIPAddress", summary)

    def test_codex_evidence_summary_redacts_offline_windows_inventory(self) -> None:
        summary = (ROOT / "scripts" / "New-CodexEvidenceSummary.ps1").read_text(
            encoding="utf-8"
        )

        self.assertIn("OfflineWindowsInventoryCaptured", summary)
        self.assertIn("OfflineWindowsInstallationCount", summary)
        self.assertIn("OfflineUserProfileCount", summary)
        self.assertIn("AutopilotEventLogPresentCount", summary)
        self.assertIn("MdmAdminEventLogPresentCount", summary)
        self.assertIn("AutopilotEventCountSampled", summary)
        self.assertIn("AutopilotErrorCount", summary)
        self.assertIn("AutopilotWarningCount", summary)
        self.assertIn("MdmAdminEventCountSampled", summary)
        self.assertIn("MdmAdminErrorCount", summary)
        self.assertIn("MdmAdminWarningCount", summary)
        self.assertIn("OfflineBootStorePresentCount", summary)
        self.assertIn("OfflineBootStoreEnumeratedCount", summary)
        self.assertIn("OfflineBootEntryCount", summary)
        self.assertIn("UserNamesIncluded", summary)
        self.assertIn("RawEventPayloadsIncluded", summary)
        self.assertIn("RecoveryMaterialIncluded", summary)
        self.assertNotIn("RedactedRoot", summary)
        self.assertNotIn("KnownFoldersPresent", summary)

    def test_codex_evidence_summary_requires_explicit_false_privacy_flags(self) -> None:
        summary = (ROOT / "scripts" / "New-CodexEvidenceSummary.ps1").read_text(
            encoding="utf-8"
        )

        self.assertIn("function Assert-ExplicitFalse", summary)
        self.assertIn("PSObject.Properties", summary)
        self.assertIn("FileNamesEnumerated", summary)
        self.assertIn("FileContentsRead", summary)


if __name__ == "__main__":
    unittest.main()
