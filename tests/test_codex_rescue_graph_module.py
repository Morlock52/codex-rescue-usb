from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "PowerShell" / "Modules" / "CodexRescue.Graph"


class CodexRescueGraphModuleTests(unittest.TestCase):
    def test_public_surface_is_small_and_read_only(self) -> None:
        expected = {
            "Connect-CodexRescueGraphReadOnly",
            "Disconnect-CodexRescueGraphReadOnly",
            "Get-CodexRescueCloudDeviceHealth",
            "Test-CodexRescueGraphPrerequisite",
        }
        actual = {path.stem for path in (MODULE / "Public").glob("*.ps1")}

        self.assertEqual(expected, actual)
        self.assertFalse(any("Set-" in name or "Remove-" in name for name in actual))

    def test_connection_requires_exact_consent_and_process_context(self) -> None:
        source = (
            MODULE / "Public" / "Connect-CodexRescueGraphReadOnly.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("CONNECT CODEX RESCUE READ ONLY GRAPH", source)
        self.assertIn("-cne $requiredToken", source)
        self.assertIn("ContextScope = 'Process'", source)
        self.assertIn("AuthType -ne 'Delegated'", source)
        self.assertNotIn("ClientSecret", source)
        self.assertNotIn("CertificateThumbprint", source)
        self.assertNotIn("AccessToken", source)

    def test_scope_set_is_fixed_and_excludes_write_and_key_permissions(self) -> None:
        source = (
            MODULE / "Private" / "Get-CodexRescueGraphRequiredScope.ps1"
        ).read_text(encoding="utf-8")

        for scope in (
            "Device.Read.All",
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementServiceConfig.Read.All",
            "BitlockerKey.ReadBasic.All",
        ):
            self.assertIn(scope, source)

        self.assertNotIn("ReadWrite", source)
        self.assertNotIn("PrivilegedOperations", source)
        self.assertNotIn("BitlockerKey.Read.All", source)
        self.assertNotIn("Directory.Read.All", source)

        session_source = (
            MODULE / "Private" / "Assert-CodexRescueGraphSession.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn("$allowedSessionScopes", session_source)
        self.assertIn("contains an unrelated scope", session_source)

    def test_request_broker_is_get_only_and_rejects_recovery_key_values(self) -> None:
        source = (
            MODULE / "Private" / "Invoke-CodexRescueGraphGet.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("Invoke-MgGraphRequest -Method GET", source)
        self.assertIn("/v1.0/", source)
        self.assertIn(r"select\s*=\s*key", source)
        self.assertIn("recoverykeys/", source)
        self.assertIn("BitLocker recovery-key list endpoint permits only", source)
        self.assertIn("Request path is outside", source)
        for method in ("POST", "PATCH", "PUT", "DELETE"):
            self.assertNotIn(f"-Method {method}", source)

        public_source = (
            MODULE / "Public" / "Get-CodexRescueCloudDeviceHealth.ps1"
        ).read_text(encoding="utf-8")
        bitlocker_query = next(
            line for line in public_source.splitlines()
            if "recoveryKeys?%24filter=" in line
        )
        self.assertNotIn("%24top", bitlocker_query)
        self.assertNotIn("%24select", bitlocker_query)

    def test_cloud_result_is_identifier_free_and_distinguishes_query_outcomes(self) -> None:
        public_source = (
            MODULE / "Public" / "Get-CodexRescueCloudDeviceHealth.ps1"
        ).read_text(encoding="utf-8")
        outcome_source = (
            MODULE / "Private" / "Get-CodexRescueGraphErrorOutcome.ps1"
        ).read_text(encoding="utf-8")
        source = public_source + outcome_source

        for outcome in (
            "PermissionDenied",
            "NotFound",
            "Unavailable",
            "Healthy",
            "Warning",
        ):
            self.assertIn(outcome, source)
        self.assertIn("IdentifiersIncluded = $false", source)
        self.assertIn("RecoveryKeyMaterialRequested = $false", source)
        self.assertIn("RecoveryKeyMaterialCollected = $false", source)
        self.assertIn("WriteRequestsPerformed = 0", source)
        self.assertIn("HTTPMethodsUsed = @('GET')", source)
        self.assertNotIn("$select=key", source.lower())
        self.assertNotIn("RecoveryPassword", source)

    def test_validation_rejects_identifiers_tokens_and_recovery_material(self) -> None:
        source = (
            MODULE / "Private" / "Assert-CodexRescueCloudResult.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("GUID-shaped identifier", source)
        self.assertIn("email-shaped identifier", source)
        self.assertIn("recovery-password-shaped value", source)
        self.assertIn("token-shaped value", source)
        self.assertIn("RecoveryKeyMaterialCollected -ne $false", source)
        self.assertIn("CredentialsCollected -ne $false", source)

    def test_native_harness_uses_mocked_gets_and_scans_output(self) -> None:
        harness = (
            ROOT / "tests" / "windows" / "Test-CodexRescueGraphModule.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("function Invoke-MgGraphRequest", harness)
        self.assertIn("$Method -ne 'GET'", harness)
        self.assertIn("$mockResult.CloudRequestsPerformed -eq 5", harness)
        self.assertIn("$mockResult.WriteRequestsPerformed -eq 0", harness)
        self.assertIn("$mockResult.RecoveryKeyMaterialRequested -eq $false", harness)
        self.assertIn("$guardRejectedKeyRead", harness)
        self.assertIn("$permissionCheck.Outcome -eq 'PermissionDenied'", harness)
        self.assertNotIn("Connect-MgGraph", harness)


if __name__ == "__main__":
    unittest.main()
