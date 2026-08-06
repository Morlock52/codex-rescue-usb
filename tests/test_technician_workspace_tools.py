import json
import re
import unittest
from pathlib import Path


class TechnicianWorkspaceToolManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repository_root = Path(__file__).resolve().parents[1]
        cls.manifest_path = (
            cls.repository_root
            / "config"
            / "technician-workspace-tools.json"
        )

    def load_manifest(self) -> dict:
        return json.loads(self.manifest_path.read_text(encoding="utf-8"))

    def test_manifest_has_bounded_install_providers_and_required_toolchain(self) -> None:
        manifest = self.load_manifest()
        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertEqual(manifest["asOfDate"], "2026-08-05")
        self.assertEqual(
            manifest["policy"]["network"],
            "offline-default-explicit-maintenance-window",
        )

        winget_ids = {item["id"] for item in manifest["wingetPackages"]}
        self.assertTrue(
            {
                "Microsoft.PowerShell",
                "Git.Git",
                "OpenJS.NodeJS.LTS",
                "Microsoft.VisualStudioCode",
                "Microsoft.Sysinternals",
                "7zip.7zip",
            }.issubset(winget_ids)
        )
        self.assertTrue(
            all(item["versionPolicy"] == "resolve-and-record" for item in manifest["wingetPackages"])
        )

    def test_codex_cli_is_pinned_and_authentication_is_post_image_only(self) -> None:
        manifest = self.load_manifest()
        codex = manifest["codexCli"]

        self.assertEqual(codex["provider"], "npm")
        self.assertEqual(codex["package"], "@openai/codex")
        self.assertRegex(codex["version"], r"^\d+\.\d+\.\d+$")
        self.assertTrue(codex["integrity"].startswith("sha512-"))
        self.assertEqual(codex["authentication"], "interactive-post-image-only")
        self.assertFalse(codex["persistAuthenticationInImage"])

    def test_graph_modules_are_version_pinned_and_cloud_writes_are_excluded(self) -> None:
        manifest = self.load_manifest()
        modules = {item["name"]: item for item in manifest["powerShellModules"]}

        for name in (
            "Microsoft.Graph.Authentication",
            "Microsoft.Graph.DeviceManagement",
            "Microsoft.Graph.Identity.DirectoryManagement",
            "Microsoft.Graph.Groups",
            "Microsoft.Graph.Users",
        ):
            self.assertEqual(modules[name]["version"], "2.39.0")
            self.assertEqual(modules[name]["repository"], "PSGallery")

        self.assertEqual(modules["WindowsAutoPilotIntune"]["version"], "5.7")
        self.assertFalse(manifest["policy"]["allowCloudWriteActions"])
        self.assertFalse(manifest["policy"]["allowRecoveryKeyRetrieval"])

    def test_manifest_contains_no_credentials_or_disk_writer(self) -> None:
        manifest = self.load_manifest()
        serialized = json.dumps(manifest, sort_keys=True)

        self.assertIsNone(
            re.search(
                r"(?i)(api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|password)\s*[:=]\s*[^\"\s]",
                serialized,
            )
        )
        all_names = serialized.lower()
        for excluded in ("rufus", "ventoy"):
            self.assertNotIn(excluded, all_names)


if __name__ == "__main__":
    unittest.main()
