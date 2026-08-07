from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "orchestrator" / "src" / "CodexRescue.Orchestrator"


class OrchestratorActionUiSourceTests(unittest.TestCase):
    def test_guided_ui_exposes_each_typed_plan_apply_workflow(self) -> None:
        xaml = (APP / "MainWindow.xaml").read_text(encoding="utf-8")
        code = (APP / "MainWindow.xaml.cs").read_text(encoding="utf-8")
        for label, handler in (
            ("Apply approved toolchain", "ApplyToolchain_Click"),
            ("Build selected media", "BuildMedia_Click"),
            ("Test verified x64 ISO", "TestProxmox_Click"),
            ("Plan and write USB", "WriteUsb_Click"),
            ("Prepare UEFI backup", "PrepareUefi_Click"),
            ("Apply UEFI repair", "ApplyUefi_Click"),
            ("Roll back UEFI repair", "RollbackUefi_Click"),
            ("Plan and run salvage", "SalvageBitLocker_Click"),
        ):
            self.assertIn(f'Content="{label}"', xaml)
            self.assertIn(f'Click="{handler}"', xaml)
            self.assertIn(handler, code)

    def test_read_only_plans_use_only_fixed_signed_packaged_scripts(self) -> None:
        source = (APP / "Services" / "PackagedPlanRunner.cs").read_text(
            encoding="utf-8"
        )
        self.assertIn("ReadOnlyPlanOperation", source)
        self.assertIn("assets-manifest.json", source)
        self.assertIn("SHA256.HashData", source)
        self.assertIn("PackagedBrokerVerifier", source)
        self.assertIn("ArgumentList.Add", source)
        self.assertIn('"AllSigned"', source)
        self.assertNotIn("-Command", source)
        self.assertNotIn("ScriptPath", source)

    def test_action_plan_factory_binds_package_manifest_target_and_expiry(self) -> None:
        source = (APP / "Services" / "BrokerPlanFactory.cs").read_text(
            encoding="utf-8"
        )
        self.assertIn("assets-manifest.json", source)
        self.assertIn("SHA256.HashData", source)
        self.assertIn("TargetFingerprints", source)
        self.assertIn("TimeSpan.FromMinutes(10)", source)
        self.assertIn("ActionPlanV1", source)

    def test_reboot_resume_ui_uses_machine_verified_checkpoint_store(self) -> None:
        xaml = (APP / "MainWindow.xaml").read_text(encoding="utf-8")
        code = (APP / "MainWindow.xaml.cs").read_text(encoding="utf-8")
        store = (APP / "Services" / "CheckpointStore.cs").read_text(encoding="utf-8")
        self.assertIn('Content="Resume verification"', xaml)
        self.assertIn('Click="ResumeCheckpoint_Click"', xaml)
        self.assertIn("CheckpointStore", code)
        self.assertIn("checkpointStore.Save", code)
        self.assertIn("protector.Verify", store)
        self.assertIn("flushToDisk: true", store)

    def test_future_repairs_are_visible_but_proposal_only(self) -> None:
        xaml = (APP / "MainWindow.xaml").read_text(encoding="utf-8")
        for label in (
            "Offline DISM",
            "Quick Machine Recovery",
            "File-copy recovery",
            "Driver injection",
            "Windows RE repair",
            "Offline SFC",
        ):
            self.assertIn(label, xaml)
        self.assertGreaterEqual(xaml.count("PROPOSAL ONLY"), 6)


if __name__ == "__main__":
    unittest.main()
