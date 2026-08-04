from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from codex_rescue.models import (
    BitLockerState,
    EvidenceSnapshot,
    StorageHealth,
    TargetFingerprint,
)
from codex_rescue.secret_policy import SECRET_FIELD_TOKENS


class FixtureError(ValueError):
    pass


class FixtureNotFound(FixtureError):
    pass


class FixtureIntegrityError(FixtureError):
    pass


_ID_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
_GUID_PATTERN = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
_SERIAL_PATTERN = re.compile(r"^[A-Za-z0-9._-]{3,64}$")
_FILESYSTEM_PATTERN = re.compile(r"^[A-Za-z0-9._-]{3,64}$")
_KEY_ID_PATTERN = re.compile(r"^[A-Fa-f0-9-]{8,64}$")
PROBLEM_TAXONOMY = (
    ("pc-wont-boot", "PC won't boot", "Boot media, encryption, and startup evidence"),
    (
        "windows-crashes-loops",
        "Windows crashes or loops",
        "Startup Repair, BCD, and crash-loop evidence",
    ),
    ("recover-files", "Recover my files", "Copy and recovery to separate storage"),
    (
        "check-disk-hardware",
        "Check disk and hardware",
        "Storage health, memory, and hardware diagnostics",
    ),
    ("fix-networking", "Fix networking", "Adapter, DHCP, DNS, and connectivity"),
    (
        "security-evidence",
        "Scan and collect security evidence",
        "Read-only collection for authorized review",
    ),
    (
        "advanced-tools",
        "Advanced technician tools",
        "Explicitly gated expert workflows",
    ),
)
_CATEGORY_IDS = {item[0] for item in PROBLEM_TAXONOMY}


def _reject_secret_fields(value: Any, path: str = "root") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = str(key).strip().lower().replace("-", "_")
            if any(token in normalized for token in SECRET_FIELD_TOKENS):
                raise FixtureIntegrityError(
                    f"secret field is forbidden at {path}.{key}"
                )
            _reject_secret_fields(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _reject_secret_fields(child, f"{path}[{index}]")


def _expect_object(value: object, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise FixtureIntegrityError(f"{path} must be an object")
    return value


def _expect_exact_keys(
    value: dict[str, Any],
    path: str,
    required: set[str],
    optional: set[str] | None = None,
) -> None:
    optional = optional or set()
    missing = sorted(required - set(value))
    unexpected = sorted(set(value) - required - optional)
    if missing:
        raise FixtureIntegrityError(f"{path} is missing fields: {', '.join(missing)}")
    if unexpected:
        raise FixtureIntegrityError(
            f"{path} has unexpected fields: {', '.join(unexpected)}"
        )


def _expect_string(value: object, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise FixtureIntegrityError(f"{path} must be a non-empty string")
    return value.strip()


def _expect_boolean(value: object, path: str) -> bool:
    if type(value) is not bool:
        raise FixtureIntegrityError(f"{path} must be a boolean")
    return value


def _expect_nonnegative_integer(value: object, path: str) -> int:
    if type(value) is not int or value < 0:
        raise FixtureIntegrityError(f"{path} must be a nonnegative integer")
    return value


class FixtureRepository:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()

    def list_scenario_summaries(self) -> list[dict[str, object]]:
        summaries: list[dict[str, object]] = []
        index = self._index()
        for scenario_id, payload in index.items():
            presentation = payload["presentation"]
            summaries.append(
                {
                    "id": scenario_id,
                    "title": payload["title"],
                    "category": payload["category"],
                    "label": presentation["label"],
                    "description": presentation["description"],
                    "order": presentation["order"],
                }
            )
        return sorted(summaries, key=lambda item: (item["order"], item["id"]))

    def problem_catalog(self) -> list[dict[str, object]]:
        summaries = self.list_scenario_summaries()
        by_category: dict[str, list[dict[str, object]]] = {}
        for summary in summaries:
            by_category.setdefault(str(summary["category"]), []).append(summary)
        return [
            {
                "id": category_id,
                "label": label,
                "description": description,
                "status": "available" if by_category.get(category_id) else "planned",
                "scenarios": by_category.get(category_id, []),
            }
            for category_id, label, description in PROBLEM_TAXONOMY
        ]

    def load(self, scenario_id: str) -> EvidenceSnapshot:
        if not _ID_PATTERN.fullmatch(scenario_id):
            raise FixtureNotFound(f"unknown fixture: {scenario_id}")
        payload = self._index().get(scenario_id)
        if payload is None:
            raise FixtureNotFound(f"unknown fixture: {scenario_id}")
        target_data = payload["target"]
        evidence_data = payload["evidence"]
        return EvidenceSnapshot(
            scenario_id=scenario_id,
            title=payload["title"],
            category=payload["category"],
            target=TargetFingerprint(
                disk_serial=target_data["disk_serial"],
                partition_guid=target_data["partition_guid"],
                filesystem_uuid=target_data["filesystem_uuid"],
                windows_path=target_data["windows_path"],
                bitlocker_key_id=target_data["bitlocker_key_id"],
            ),
            smart_status=StorageHealth(evidence_data["smart_status"]),
            read_errors=evidence_data["read_errors"],
            bitlocker_state=BitLockerState(evidence_data["bitlocker_state"]),
            bcd_valid=evidence_data["bcd_valid"],
            boot_files_present=evidence_data["boot_files_present"],
            network_available=evidence_data["network_available"],
            notes=tuple(evidence_data["notes"]),
        )

    def _index(self) -> dict[str, dict[str, Any]]:
        index: dict[str, dict[str, Any]] = {}
        for path in sorted(self.root.glob("*.json")):
            resolved = path.resolve()
            if resolved.parent != self.root:
                raise FixtureIntegrityError("fixture path escapes repository root")
            payload = self._read_validated(resolved)
            scenario_id = payload["id"]
            if scenario_id in index:
                raise FixtureIntegrityError(f"duplicate fixture id: {scenario_id}")
            index[scenario_id] = payload
        return index

    def _read_validated(self, path: Path) -> dict[str, Any]:
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise FixtureIntegrityError(f"invalid fixture: {path.name}") from error
        payload = _expect_object(payload, "fixture")
        _reject_secret_fields(payload)
        _expect_exact_keys(
            payload,
            "fixture",
            {"id", "title", "category", "presentation", "target", "evidence"},
        )
        fixture_id = _expect_string(payload["id"], "fixture.id")
        if not _ID_PATTERN.fullmatch(fixture_id) or path.stem != fixture_id:
            raise FixtureIntegrityError("fixture id must match its safe filename")
        payload["id"] = fixture_id
        payload["title"] = _expect_string(payload["title"], "fixture.title")
        category = _expect_string(payload["category"], "fixture.category")
        if category not in _CATEGORY_IDS:
            raise FixtureIntegrityError("fixture.category is not in the problem taxonomy")
        payload["category"] = category
        self._validate_presentation(payload)
        self._validate_target(payload)
        self._validate_evidence(payload)
        return payload

    @staticmethod
    def _validate_presentation(payload: dict[str, Any]) -> None:
        value = _expect_object(payload["presentation"], "fixture.presentation")
        _expect_exact_keys(
            value,
            "fixture.presentation",
            {"label", "description", "order"},
        )
        value["label"] = _expect_string(value["label"], "fixture.presentation.label")
        value["description"] = _expect_string(
            value["description"], "fixture.presentation.description"
        )
        value["order"] = _expect_nonnegative_integer(
            value["order"], "fixture.presentation.order"
        )

    @staticmethod
    def _validate_target(payload: dict[str, Any]) -> None:
        value = _expect_object(payload["target"], "fixture.target")
        _expect_exact_keys(
            value,
            "fixture.target",
            {
                "disk_serial",
                "partition_guid",
                "filesystem_uuid",
                "windows_path",
                "bitlocker_key_id",
            },
        )
        disk_serial = _expect_string(value["disk_serial"], "fixture.target.disk_serial")
        partition_guid = _expect_string(
            value["partition_guid"], "fixture.target.partition_guid"
        )
        filesystem_uuid = _expect_string(
            value["filesystem_uuid"], "fixture.target.filesystem_uuid"
        )
        windows_path = _expect_string(value["windows_path"], "fixture.target.windows_path")
        if not _SERIAL_PATTERN.fullmatch(disk_serial):
            raise FixtureIntegrityError("fixture.target.disk_serial has invalid format")
        if not _GUID_PATTERN.fullmatch(partition_guid):
            raise FixtureIntegrityError("fixture.target.partition_guid has invalid format")
        if not _FILESYSTEM_PATTERN.fullmatch(filesystem_uuid):
            raise FixtureIntegrityError("fixture.target.filesystem_uuid has invalid format")
        if not windows_path.startswith("\\") or ".." in windows_path:
            raise FixtureIntegrityError("fixture.target.windows_path has invalid format")
        key_id = value["bitlocker_key_id"]
        if key_id is not None:
            key_id = _expect_string(key_id, "fixture.target.bitlocker_key_id")
            if not _KEY_ID_PATTERN.fullmatch(key_id):
                raise FixtureIntegrityError("fixture.target.bitlocker_key_id has invalid format")
        value.update(
            disk_serial=disk_serial,
            partition_guid=partition_guid,
            filesystem_uuid=filesystem_uuid,
            windows_path=windows_path,
            bitlocker_key_id=key_id,
        )

    @staticmethod
    def _validate_evidence(payload: dict[str, Any]) -> None:
        value = _expect_object(payload["evidence"], "fixture.evidence")
        _expect_exact_keys(
            value,
            "fixture.evidence",
            {
                "smart_status",
                "read_errors",
                "bitlocker_state",
                "bcd_valid",
                "boot_files_present",
                "network_available",
                "notes",
            },
        )
        try:
            value["smart_status"] = StorageHealth(
                _expect_string(value["smart_status"], "fixture.evidence.smart_status")
            ).value
            value["bitlocker_state"] = BitLockerState(
                _expect_string(
                    value["bitlocker_state"], "fixture.evidence.bitlocker_state"
                )
            ).value
        except ValueError as error:
            raise FixtureIntegrityError("fixture evidence contains an unknown enum") from error
        value["read_errors"] = _expect_nonnegative_integer(
            value["read_errors"], "fixture.evidence.read_errors"
        )
        for field in ("bcd_valid", "boot_files_present", "network_available"):
            value[field] = _expect_boolean(value[field], f"fixture.evidence.{field}")
        notes = value["notes"]
        if not isinstance(notes, list):
            raise FixtureIntegrityError("fixture.evidence.notes must be an array")
        value["notes"] = [
            _expect_string(note, f"fixture.evidence.notes[{index}]")
            for index, note in enumerate(notes)
        ]
