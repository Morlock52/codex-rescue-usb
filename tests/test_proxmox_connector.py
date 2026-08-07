from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SERVICES = ROOT / "orchestrator" / "src" / "CodexRescue.Orchestrator" / "Services"


class ProxmoxConnectorSourceTests(unittest.TestCase):
    def test_profile_validation_is_https_pinned_and_bounded(self) -> None:
        source = (SERVICES / "ProxmoxConnectorFactory.cs").read_text(encoding="utf-8")
        self.assertIn('Uri.UriSchemeHttps', source)
        self.assertIn('CertificateFingerprint', source)
        self.assertIn('SHA256', source)
        self.assertIn('FixedTimeEquals', source)
        self.assertIn('SessionOnly', source)
        self.assertIn('WindowsCredentialManager', source)
        self.assertNotIn('DangerousAcceptAnyServerCertificateValidator', source)

    def test_connector_creates_only_disconnected_labeled_x64_uefi_vm(self) -> None:
        source = (SERVICES / "ProxmoxConnectorService.cs").read_text(encoding="utf-8")
        self.assertIn('codex-rescue-', source)
        self.assertIn('["bios"] = "ovmf"', source)
        self.assertIn('["arch"] = "x86_64"', source)
        self.assertIn('["tags"] = _resourceLabel', source)
        self.assertIn('Disconnected', source)
        self.assertNotIn('["net0"]', source)
        self.assertIn('MaximumRunMinutes', source)

    def test_cleanup_rechecks_label_and_requires_target_phrase(self) -> None:
        source = (SERVICES / "ProxmoxConnectorService.cs").read_text(encoding="utf-8")
        self.assertIn('DELETE VM', source)
        self.assertIn('FixedPhraseEquals', source)
        self.assertIn('GetVmConfigAsync', source)
        self.assertIn('Resource label changed; cleanup refused.', source)
        self.assertIn('tracked.Contains', source)


if __name__ == "__main__":
    unittest.main()
