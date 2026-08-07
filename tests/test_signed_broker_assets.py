from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
BROKER = ROOT / "orchestrator" / "src" / "CodexRescue.Broker"
PACKAGING = ROOT / "orchestrator" / "packaging"


class SignedBrokerAssetTests(unittest.TestCase):
    def test_catalog_maps_each_privileged_operation_to_one_fixed_asset(self) -> None:
        source = (BROKER / "SignedAssetCatalog.cs").read_text(encoding="utf-8")
        for mapping in (
            "ApplyToolchain",
            "BuildMedia",
            "WriteUsb",
            "RepairUefi",
            "SalvageBitLocker",
        ):
            self.assertIn(mapping, source)
        self.assertIn("AppContext.BaseDirectory", source)
        self.assertIn("assets-manifest.json", source)
        self.assertIn("SHA256.HashData", source)
        self.assertIn("WinVerifyTrust", source)
        self.assertIn("unexpected loose script", source)
        self.assertNotIn("ScriptPath", source)

    def test_broker_derives_expected_package_and_catalog_digest_itself(self) -> None:
        source = (BROKER / "Program.cs").read_text(encoding="utf-8")
        self.assertIn("AssemblyInformationalVersionAttribute", source)
        self.assertIn("catalog.Digest", source)
        self.assertIn("NamedPipeClientStream", source)
        self.assertIn("BrokerWireProtocol.ReadAsync", source)
        self.assertNotIn("Console.OpenStandardInput", source)
        self.assertNotIn("args[0]", source)
        self.assertNotIn("args[1]", source)

    def test_orchestrator_uses_uac_only_for_typed_broker_apply(self) -> None:
        source = (
            ROOT
            / "orchestrator"
            / "src"
            / "CodexRescue.Orchestrator"
            / "Services"
            / "BrokerClient.cs"
        ).read_text(encoding="utf-8")
        self.assertIn("NamedPipeServerStream", source)
        self.assertIn('Verb = "runas"', source)
        self.assertIn("BrokerWireProtocol.WriteAsync", source)
        self.assertIn("BrokerWireProtocol.ReadAsync", source)
        self.assertIn("ERROR_CANCELLED", source)
        self.assertNotIn("RedirectStandardInput", source)
        self.assertNotIn("-Command", source)

    def test_asset_runner_uses_fixed_windows_powershell_and_argument_list(self) -> None:
        source = (BROKER / "SignedPowerShellRunner.cs").read_text(encoding="utf-8")
        self.assertIn("System32", source)
        self.assertIn("WindowsPowerShell", source)
        self.assertIn("ExecutionPolicy", source)
        self.assertIn("AllSigned", source)
        self.assertIn("ArgumentList.Add", source)
        self.assertIn("RedirectStandardError = true", source)
        self.assertNotIn("Invoke-Expression", source)
        self.assertNotIn("-Command", source)

    def test_release_catalog_generator_requires_signed_scripts_before_hashing(self) -> None:
        source = (PACKAGING / "New-SignedAssetCatalog.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn("Get-AuthenticodeSignature", source)
        self.assertIn("Status -ne 'Valid'", source)
        self.assertIn("SignerCertificate.Thumbprint", source)
        self.assertIn("Get-FileHash", source)
        self.assertIn("assets-manifest.json", source)
        self.assertNotIn("Set-AuthenticodeSignature", source)


if __name__ == "__main__":
    unittest.main()
