import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MATRIX = ROOT / "config" / "media-build-matrix.json"
MATRIX_BUILDER = ROOT / "scripts" / "Build-CodexRescueMediaMatrix.ps1"
ISO_BUILDER = ROOT / "scripts" / "Build-RescueIso.ps1"
ISO_VERIFIER = ROOT / "scripts" / "Test-RescueIso.ps1"


class MediaBuildMatrixTests(unittest.TestCase):
    def test_matrix_defines_four_exact_independently_identified_artifacts(self) -> None:
        matrix = json.loads(MATRIX.read_text(encoding="utf-8"))
        self.assertEqual(matrix["schemaVersion"], 1)
        artifacts = {item["artifactId"]: item for item in matrix["artifacts"]}
        self.assertEqual(
            set(artifacts),
            {"x64-2023CA", "x64-2011CA", "arm64-2023CA", "arm64-2011CA"},
        )
        self.assertEqual(artifacts["x64-2023CA"]["adkVersion"], "10.1.26100.2454")
        self.assertEqual(artifacts["x64-2023CA"]["servicingUpdate"], "KB5101684")
        self.assertEqual(artifacts["arm64-2023CA"]["adkVersion"], "10.1.28000.1")
        self.assertEqual(artifacts["arm64-2023CA"]["servicingUpdate"], "KB5101681")
        self.assertEqual(artifacts["arm64-2023CA"]["evidenceTier"], "Experimental")

    def test_matrix_builder_requires_a_matching_servicing_receipt(self) -> None:
        source = MATRIX_BUILDER.read_text(encoding="utf-8")
        self.assertIn("ServicingReceiptPath", source)
        self.assertIn("PackageSha256", source)
        self.assertIn("Signature", source)
        self.assertIn("AdkVersion", source)
        self.assertIn("KnowledgeBase", source)
        self.assertIn("No compatible artifacts", source)
        self.assertNotIn("Invoke-WebRequest", source)

    def test_iso_builder_parameterizes_architecture_and_trust_path(self) -> None:
        source = ISO_BUILDER.read_text(encoding="utf-8")
        self.assertIn("[ValidateSet('amd64', 'arm64')]", source)
        self.assertIn("[ValidateSet('2023CA', '2011CA')]", source)
        self.assertIn("$Architecture", source)
        self.assertIn("$TrustPath", source)
        self.assertIn("if ($TrustPath -ceq '2023CA')", source)
        self.assertIn("'/BOOTEX'", source)
        self.assertIn("ArtifactId", source)

    def test_iso_verifier_records_architecture_trust_and_toolchain_provenance(self) -> None:
        source = ISO_VERIFIER.read_text(encoding="utf-8")
        for field in (
            "ArtifactId",
            "Architecture",
            "TrustPath",
            "AdkVersion",
            "ServicingUpdate",
            "InjectedSourceInventory",
            "bootaa64.efi",
            "bootx64.efi",
        ):
            self.assertIn(field, source)
        self.assertIn("ContainsRecoveryMaterial = $false", source)

    def test_each_matrix_artifact_gets_hash_sbom_and_provenance(self) -> None:
        source = MATRIX_BUILDER.read_text(encoding="utf-8")
        for required in (
            "SourceRevision",
            ".sha256",
            ".spdx.json",
            ".provenance.json",
            "InjectedSourceInventory",
            "SourceCatalogSha256",
            "ProvenanceTier",
            "ContainsRecoveryMaterial = $false",
        ):
            self.assertIn(required, source)


if __name__ == "__main__":
    unittest.main()
