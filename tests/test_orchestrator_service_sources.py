from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
ORCHESTRATOR = ROOT / "orchestrator"
APP = ORCHESTRATOR / "src" / "CodexRescue.Orchestrator"
DOTNET_TESTS = ORCHESTRATOR / "tests" / "CodexRescue.Orchestrator.Tests"


class OrchestratorServiceSourceTests(unittest.TestCase):
    def test_dotnet_tests_cover_contracts_state_security_and_privacy(self) -> None:
        project = DOTNET_TESTS / "CodexRescue.Orchestrator.Tests.csproj"
        self.assertTrue(project.is_file())
        project_source = project.read_text(encoding="utf-8")
        self.assertIn('MSTest.TestFramework" Version="4.3.3"', project_source)
        self.assertIn('MSTest.TestAdapter" Version="4.3.3"', project_source)
        self.assertIn('Microsoft.NET.Test.Sdk" Version="18.8.1"', project_source)

        tests = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted(DOTNET_TESTS.glob("*.cs"))
        )
        for expectation in (
            "ExpiredPlanIsRejected",
            "UnknownOperationIsRejected",
            "ManifestSignatureAndArtifactHashAreVerified",
            "ChangedArtifactHashIsRejected",
            "CheckpointTamperingIsRejected",
            "TelemetryRequiresPolicyAndConsent",
            "SecretLikeCheckpointStateIsRejected",
            "UacCancellationDoesNotAdvanceWorkflow",
        ):
            self.assertIn(expectation, tests)

    def test_state_machine_has_explicit_plan_apply_verify_and_resume_states(self) -> None:
        source = (APP / "Workflow" / "OrchestratorStateMachine.cs").read_text(
            encoding="utf-8"
        )
        for state in (
            "AuditRunning",
            "PlanReady",
            "AwaitingApproval",
            "Applying",
            "RestartRequired",
            "Verifying",
            "Completed",
            "Blocked",
        ):
            self.assertIn(state, source)
        self.assertIn("UacCancelled", source)
        self.assertIn("InvalidOperationException", source)

    def test_release_verifier_requires_detached_signature_and_artifact_hashes(self) -> None:
        source = (APP / "Services" / "SignedReleaseVerifier.cs").read_text(
            encoding="utf-8"
        )
        self.assertIn("SignedCms", source)
        self.assertIn("CheckSignature", source)
        self.assertIn("expectedPublisherIdentity", source)
        self.assertIn("1.3.6.1.5.5.7.3.3", source)
        self.assertIn("X500DistinguishedName", source)
        self.assertIn("Rfc3161TimestampToken", source)
        self.assertIn("VerificationTime", source)
        self.assertIn("SHA256.HashData", source)
        self.assertIn("FixedTimeEquals", source)
        self.assertIn("ReleaseManifestV1.SupportedSchemaVersion", source)

    def test_host_audit_is_local_only_and_reports_required_categories(self) -> None:
        source = (APP / "Services" / "HostAuditService.cs").read_text(
            encoding="utf-8"
        )
        for component in (
            "Windows host",
            "WinPE toolchain",
            "Signing trust",
            "Codex CLI",
            "Proxmox connector",
            "Network & telemetry",
        ):
            self.assertIn(component, source)
        for forbidden in (
            "HttpClient",
            "WebRequest",
            "Invoke-WebRequest",
            "Process.Start",
        ):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
