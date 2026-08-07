from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
PACKAGING = ROOT / "orchestrator" / "packaging"
WORKFLOWS = ROOT / ".github" / "workflows"


class OrchestratorPackagingTests(unittest.TestCase):
    def test_msix_manifest_is_full_trust_desktop_and_standard_user_app(self) -> None:
        manifest = PACKAGING / "AppxManifest.template.xml"
        source = manifest.read_text(encoding="utf-8")
        ET.fromstring(source)
        self.assertIn('EntryPoint="Windows.FullTrustApplication"', source)
        self.assertIn('rescap:Capability Name="runFullTrust"', source)
        self.assertIn('MinVersion="10.0.22621.0"', source)
        self.assertNotIn("requireAdministrator", source)
        self.assertNotIn("allowElevation", source)

    def test_packager_requires_signed_payload_and_uses_windows_sdk_tools(self) -> None:
        source = (PACKAGING / "Build-MsixPackage.ps1").read_text(encoding="utf-8")
        self.assertIn("Get-AuthenticodeSignature", source)
        self.assertIn("Status -ne 'Valid'", source)
        self.assertIn("makeappx.exe", source)
        self.assertIn("AppxManifest.xml", source)
        self.assertIn("CodexRescue.Broker.exe", source)
        self.assertIn("assets-manifest.json", source)
        self.assertNotIn("New-SelfSignedCertificate", source)
        self.assertNotIn("Set-AuthenticodeSignature", source)

    def test_appinstaller_uses_direct_download_and_operator_visible_updates(self) -> None:
        source = (PACKAGING / "CodexRescue.appinstaller.template.xml").read_text(
            encoding="utf-8"
        )
        ET.fromstring(source)
        self.assertIn("<MainBundle", source)
        self.assertIn('ShowPrompt="true"', source)
        self.assertIn('UpdateBlocksActivation="false"', source)
        self.assertNotIn("ForceUpdateFromAnyVersion", source)
        self.assertNotIn("ms-appinstaller:", source)

    def test_ci_builds_and_tests_windows_source_without_claiming_signed_release(self) -> None:
        source = (WORKFLOWS / "orchestrator-ci.yml").read_text(encoding="utf-8")
        self.assertIn("windows-2025", source)
        self.assertIn("dotnet test", source)
        self.assertIn("python -m unittest discover", source)
        self.assertIn("UNSIGNED-DEVELOPER", source)
        self.assertNotIn("artifact-signing-action", source)

    def test_release_uses_oidc_artifact_signing_and_protected_tags(self) -> None:
        source = (WORKFLOWS / "orchestrator-release.yml").read_text(
            encoding="utf-8"
        )
        for required in (
            "id-token: write",
            "production-signing",
            "azure/login@v3",
            "azure/artifact-signing-action@v2",
            "timestamp.acs.microsoft.com",
            "New-SignedAssetCatalog.ps1",
            "Build-MsixPackage.ps1",
            "New-SpdxSbom.ps1",
            "attest-build-provenance",
            "rollback",
        ):
            self.assertIn(required, source)
        self.assertIn("tags:", source)
        self.assertIn("orchestrator-v*", source)


if __name__ == "__main__":
    unittest.main()
