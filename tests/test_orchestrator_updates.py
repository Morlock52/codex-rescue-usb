from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SERVICES = (
    ROOT
    / "orchestrator"
    / "src"
    / "CodexRescue.Orchestrator"
    / "Services"
)


class OrchestratorUpdateSourceTests(unittest.TestCase):
    def test_maintenance_window_requires_network_consent_and_expires(self) -> None:
        source = (SERVICES / "MaintenanceWindowService.cs").read_text(
            encoding="utf-8"
        )
        self.assertIn("NetworkConsent", source)
        self.assertIn("ExpiresAtUtc", source)
        self.assertIn("RequireOpen", source)
        self.assertIn("Close", source)
        self.assertIn("TimeSpan.FromMinutes(30)", source)

    def test_online_release_check_is_fixed_repo_and_window_gated(self) -> None:
        source = (SERVICES / "GitHubReleaseUpdateService.cs").read_text(
            encoding="utf-8"
        )
        self.assertIn("Morlock52/codex-rescue-usb", source)
        self.assertIn("RequireOpen", source)
        self.assertIn("release-manifest.json", source)
        self.assertIn("release-manifest.json.p7", source)
        self.assertIn("SignedReleaseVerifier", source)
        self.assertNotIn("Authorization", source)
        self.assertNotIn("github login", source.lower())

    def test_offline_import_rejects_zip_escape_and_verifies_before_cache(self) -> None:
        source = (SERVICES / "OfflineBundleImporter.cs").read_text(
            encoding="utf-8"
        )
        self.assertIn("ZipArchive", source)
        self.assertIn("escapes the staging directory", source)
        self.assertIn("SignedReleaseVerifier", source)
        self.assertIn("requireTrustedChain: true", source)
        self.assertLess(source.index("VerifyAsync"), source.index("PromoteVerifiedBundle"))
        self.assertNotIn("Process.Start", source)

    def test_release_cache_keeps_current_and_n_minus_one_and_refuses_downgrade(self) -> None:
        source = (SERVICES / "ReleaseCacheManager.cs").read_text(encoding="utf-8")
        self.assertIn("downgrade", source.lower())
        self.assertIn("N-1", source)
        self.assertIn("OrderByDescending", source)
        self.assertIn("Skip(2)", source)
        self.assertNotIn("ForceUpdateFromAnyVersion", source)

    def test_appinstaller_launcher_uses_local_verified_file_not_uri_protocol(self) -> None:
        source = (SERVICES / "AppInstallerLauncher.cs").read_text(encoding="utf-8")
        self.assertIn(".appinstaller", source)
        self.assertIn("UseShellExecute = true", source)
        self.assertNotIn("ms-appinstaller:", source)
        self.assertNotIn("Add-AppxPackage", source)

    def test_rollback_is_separate_reverified_n_minus_one_and_operator_visible(self) -> None:
        source = (SERVICES / "RollbackInstallerService.cs").read_text(
            encoding="utf-8"
        )
        self.assertIn("GetRollbackCandidate", source)
        self.assertIn("SignedReleaseVerifier", source)
        self.assertIn("requireTrustedChain: true", source)
        self.assertIn("ForceUpdateFromAnyVersion", source)
        self.assertIn("FileMode.CreateNew", source)
        self.assertNotIn("Process.Start", source)


if __name__ == "__main__":
    unittest.main()
