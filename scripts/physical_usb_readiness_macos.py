#!/usr/bin/env python3
"""Create a non-destructive macOS readiness plan for Codex Rescue USB.

This tool validates an ISO, requires exactly one external physical writable USB
whole disk, and can save a JSON plan to internal non-target storage. It never
erases, partitions, formats, unmounts, or writes the USB and never launches an
external writer.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import re
import subprocess
import sys
from typing import Any


EXPECTED_ALPHA13_SHA256 = (
    "67E79C37021879BAE2BC405B4618B666D6FD11397227D95C111353020E64A794"
)
DISKUTIL = "/usr/sbin/diskutil"
DF = "/bin/df"


def validate_iso(path: Path | str, expected_sha256: str) -> dict[str, Any]:
    iso_path = Path(path).expanduser().resolve()
    expected = expected_sha256.strip().upper()
    if not re.fullmatch(r"[0-9A-F]{64}", expected):
        raise ValueError("Expected SHA-256 must contain exactly 64 hexadecimal characters.")
    if iso_path.suffix.lower() != ".iso":
        raise ValueError("Select an .iso file.")
    if not iso_path.is_file() or iso_path.stat().st_size <= 0:
        raise ValueError("The selected ISO must be a non-empty file.")

    digest = hashlib.sha256()
    with iso_path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    actual = digest.hexdigest().upper()
    if actual != expected:
        raise ValueError(f"ISO SHA-256 mismatch. Expected {expected}; found {actual}.")

    return {
        "Path": str(iso_path),
        "FileName": iso_path.name,
        "SizeBytes": iso_path.stat().st_size,
        "Sha256": actual,
    }


def select_eligible_disk(
    whole_disks: list[str],
    disk_info_by_identifier: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    eligible: list[dict[str, Any]] = []
    for identifier in whole_disks:
        info = disk_info_by_identifier.get(identifier, {})
        if not (
            info.get("DeviceIdentifier") == identifier
            and info.get("WholeDisk") is True
            and info.get("Internal") is False
            and info.get("VirtualOrPhysical") == "Physical"
            and info.get("WritableMedia") is True
            and str(info.get("BusProtocol", "")).upper() == "USB"
            and int(info.get("Size", 0)) > 0
        ):
            continue
        eligible.append(
            {
                "DeviceIdentifier": identifier,
                "DeviceNode": f"/dev/{identifier}",
                "MediaName": str(info.get("MediaName", "")).strip(),
                "SerialNumber": str(info.get("SerialNumber", "")).strip(),
                "SizeBytes": int(info["Size"]),
                "BusProtocol": str(info["BusProtocol"]),
                "Internal": False,
                "VirtualOrPhysical": "Physical",
                "WritableMedia": True,
            }
        )

    if len(eligible) != 1:
        raise ValueError(
            "Expected exactly one external, physical, writable USB whole disk; "
            f"found {len(eligible)}. Disconnect every USB storage device except "
            "the intended blank rescue drive, then rerun the audit."
        )
    return eligible[0]


def get_confirmation_token(iso: dict[str, Any], disk: dict[str, Any]) -> str:
    return "PLAN {device} {size} {hash_prefix}".format(
        device=disk["DeviceIdentifier"],
        size=disk["SizeBytes"],
        hash_prefix=iso["Sha256"][:12],
    )


def build_plan(
    iso: dict[str, Any],
    disk: dict[str, Any],
    supplied_token: str,
    *,
    live_evidence: bool,
) -> dict[str, Any]:
    expected_token = get_confirmation_token(iso, disk)
    if supplied_token != expected_token:
        raise ValueError(
            "The confirmation token does not match the current ISO and USB target. "
            f"Required token: {expected_token}"
        )
    return {
        "SchemaVersion": 1,
        "CreatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "Platform": "macOS",
        "EvidenceSource": "LiveMacOS" if live_evidence else "ContractFixture",
        "LiveEvidence": live_evidence,
        "Iso": iso,
        "TargetDisk": disk,
        "WritePerformed": False,
        "ExternalWriterRequired": True,
        "OperatorConfirmationRecorded": True,
        "SafetyBoundary": (
            "This plan records readiness only. It does not authorize erasing or "
            "writing the target and it does not prove physical bootability."
        ),
    }


def assert_safe_plan_destination(
    destination_whole_disk_info: dict[str, Any],
    target_identifier: str,
) -> None:
    destination_identifier = str(
        destination_whole_disk_info.get("ParentWholeDisk")
        or destination_whole_disk_info.get("DeviceIdentifier")
        or ""
    )
    if not (
        destination_whole_disk_info.get("Internal") is True
        and destination_identifier
        and destination_identifier != target_identifier
    ):
        raise ValueError(
            "The plan must be saved to internal non-target storage, never to the "
            "selected USB or another external disk."
        )


def write_plan(path: Path | str, plan: dict[str, Any]) -> None:
    plan_path = Path(path).expanduser()
    if plan_path.suffix.lower() != ".json":
        raise ValueError("The readiness plan path must end in .json.")
    plan_path.parent.mkdir(parents=False, exist_ok=True)
    with plan_path.open("x", encoding="utf-8") as handle:
        json.dump(plan, handle, indent=2)
        handle.write("\n")


def _run(command: list[str]) -> bytes:
    allowed = (
        command == [DISKUTIL, "list", "-plist", "external", "physical"]
        or (
            len(command) == 4
            and command[:3] == [DISKUTIL, "info", "-plist"]
            and bool(command[3])
        )
        or (len(command) == 3 and command[:2] == [DF, "-P"] and bool(command[2]))
    )
    if not allowed:
        raise ValueError(f"Command is outside the read-only allowlist: {command!r}")
    completed = subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return completed.stdout


def _disk_info(identifier: str) -> dict[str, Any]:
    return plistlib.loads(_run([DISKUTIL, "info", "-plist", identifier]))


def get_live_eligible_disk() -> dict[str, Any]:
    listing = plistlib.loads(_run([DISKUTIL, "list", "-plist", "external", "physical"]))
    whole_disks = [str(value) for value in listing.get("WholeDisks", [])]
    info_by_identifier = {identifier: _disk_info(identifier) for identifier in whole_disks}
    return select_eligible_disk(whole_disks, info_by_identifier)


def get_plan_destination_whole_disk_info(plan_path: Path) -> dict[str, Any]:
    parent = plan_path.expanduser().resolve().parent
    if not parent.is_dir():
        raise ValueError("The readiness plan parent directory must already exist.")
    output = _run([DF, "-P", str(parent)]).decode("utf-8", errors="strict")
    lines = [line for line in output.splitlines() if line.strip()]
    if len(lines) < 2:
        raise ValueError("Unable to resolve the readiness plan destination disk.")
    device_node = lines[-1].split()[0]
    volume_info = _disk_info(device_node)
    whole_identifier = str(
        volume_info.get("ParentWholeDisk") or volume_info.get("DeviceIdentifier") or ""
    )
    if not whole_identifier:
        raise ValueError("Unable to resolve the readiness plan destination whole disk.")
    return _disk_info(whole_identifier)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate the Codex Rescue ISO and exactly one external physical USB "
            "without writing either device."
        )
    )
    parser.add_argument("--iso", required=True, type=Path)
    parser.add_argument("--expected-sha256", default=EXPECTED_ALPHA13_SHA256)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--confirmation-token", default="")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    if platform.system() != "Darwin":
        raise RuntimeError("Live physical USB readiness requires macOS.")
    args = parse_args(sys.argv[1:] if argv is None else argv)

    iso = validate_iso(args.iso, args.expected_sha256)
    disk = get_live_eligible_disk()
    token = get_confirmation_token(iso, disk)
    preview = {
        "Iso": iso,
        "TargetDisk": disk,
        "RequiredConfirmationToken": token,
        "WritePerformed": False,
        "ExternalWriterRequired": True,
    }
    print(json.dumps(preview, indent=2))

    if args.plan is None:
        print("Readiness audit only. No plan saved and no USB write performed.")
        return 0
    if not args.confirmation_token:
        raise ValueError(f"Saving a plan requires --confirmation-token '{token}'.")

    # Revalidate both identities immediately before the one allowed write: the
    # local JSON readiness plan. The target USB itself is never written.
    final_iso = validate_iso(args.iso, args.expected_sha256)
    final_disk = get_live_eligible_disk()
    plan = build_plan(
        final_iso,
        final_disk,
        args.confirmation_token,
        live_evidence=True,
    )
    destination_info = get_plan_destination_whole_disk_info(args.plan)
    assert_safe_plan_destination(destination_info, final_disk["DeviceIdentifier"])
    write_plan(args.plan, plan)
    print(f"Saved non-destructive readiness plan: {args.plan.expanduser().resolve()}")
    print("No USB write was performed. A separate writer and confirmation are still required.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"Readiness blocked: {error}", file=sys.stderr)
        raise SystemExit(2)
