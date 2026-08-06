from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "physical_usb_readiness_macos.py"


def load_readiness_module():
    spec = importlib.util.spec_from_file_location("physical_usb_readiness_macos", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load the macOS readiness module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MacOsPhysicalUsbReadinessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_readiness_module()
        self.usb = {
            "DeviceIdentifier": "disk7",
            "WholeDisk": True,
            "Internal": False,
            "VirtualOrPhysical": "Physical",
            "WritableMedia": True,
            "BusProtocol": "USB",
            "Size": 64_023_257_088,
            "MediaName": "Disposable Rescue USB",
            "SerialNumber": "LAB-USB-001",
        }

    def test_selects_exactly_one_external_physical_writable_usb_whole_disk(self) -> None:
        selected = self.module.select_eligible_disk(
            ["disk7"],
            {"disk7": self.usb},
        )

        self.assertEqual(selected["DeviceIdentifier"], "disk7")
        self.assertEqual(selected["BusProtocol"], "USB")
        self.assertEqual(selected["SizeBytes"], 64_023_257_088)
        self.assertFalse(selected["Internal"])

        with self.assertRaisesRegex(ValueError, "found 0"):
            self.module.select_eligible_disk(
                ["disk0"],
                {
                    "disk0": {
                        **self.usb,
                        "DeviceIdentifier": "disk0",
                        "Internal": True,
                    }
                },
            )

        with self.assertRaisesRegex(ValueError, "found 2"):
            self.module.select_eligible_disk(
                ["disk7", "disk8"],
                {
                    "disk7": self.usb,
                    "disk8": {**self.usb, "DeviceIdentifier": "disk8"},
                },
            )

    def test_iso_hash_and_exact_token_bind_the_plan_to_disk_size_and_iso(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            iso_path = Path(temp_dir) / "Codex-Rescue.iso"
            iso_path.write_bytes(b"verified disposable iso fixture")
            expected_hash = hashlib.sha256(iso_path.read_bytes()).hexdigest().upper()

            iso = self.module.validate_iso(iso_path, expected_hash)
            disk = self.module.select_eligible_disk(["disk7"], {"disk7": self.usb})
            token = self.module.get_confirmation_token(iso, disk)
            plan = self.module.build_plan(iso, disk, token, live_evidence=True)

        self.assertIn("disk7", token)
        self.assertIn(str(self.usb["Size"]), token)
        self.assertIn(expected_hash[:12], token)
        self.assertEqual(plan["Iso"]["Sha256"], expected_hash)
        self.assertEqual(plan["TargetDisk"]["DeviceIdentifier"], "disk7")
        self.assertTrue(plan["LiveEvidence"])
        self.assertFalse(plan["WritePerformed"])
        self.assertTrue(plan["ExternalWriterRequired"])
        self.assertTrue(plan["OperatorConfirmationRecorded"])

        with self.assertRaisesRegex(ValueError, "confirmation token"):
            self.module.build_plan(iso, disk, "PLAN WRONG TARGET", live_evidence=True)

    def test_plan_destination_must_be_internal_and_is_never_overwritten(self) -> None:
        internal_destination = {
            "DeviceIdentifier": "disk3",
            "ParentWholeDisk": "disk3",
            "WholeDisk": True,
            "Internal": True,
            "VirtualOrPhysical": "Physical",
        }
        self.module.assert_safe_plan_destination(internal_destination, "disk7")

        with self.assertRaisesRegex(ValueError, "internal non-target"):
            self.module.assert_safe_plan_destination(
                {**internal_destination, "Internal": False},
                "disk7",
            )
        with self.assertRaisesRegex(ValueError, "internal non-target"):
            self.module.assert_safe_plan_destination(
                {**internal_destination, "DeviceIdentifier": "disk7", "ParentWholeDisk": "disk7"},
                "disk7",
            )

        with tempfile.TemporaryDirectory() as temp_dir:
            plan_path = Path(temp_dir) / "physical-alpha-plan.json"
            plan = {"SchemaVersion": 1, "WritePerformed": False}
            self.module.write_plan(plan_path, plan)
            self.assertEqual(json.loads(plan_path.read_text(encoding="utf-8")), plan)
            with self.assertRaises(FileExistsError):
                self.module.write_plan(plan_path, plan)

    def test_script_contains_only_allowlisted_read_only_disk_commands(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8").lower()

        self.assertIn("diskutil", script)
        self.assertIn("external", script)
        self.assertIn("physical", script)
        self.assertIn("writeperformed", script)
        self.assertIn("externalwriterrequired", script)
        for forbidden in (
            "diskutil erase",
            "diskutil partition",
            "diskutil reformat",
            "diskutil apfs",
            " dd ",
            "balenaetcher",
            "start-process",
            "subprocess.popen",
            "shell=true",
        ):
            self.assertNotIn(forbidden, script)


if __name__ == "__main__":
    unittest.main()
