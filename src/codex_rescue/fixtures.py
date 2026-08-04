from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from codex_rescue.models import BitLockerState, EvidenceSnapshot, TargetFingerprint


class FixtureError(ValueError):
    pass


_SECRET_FIELDS = {
    "api_key",
    "credential",
    "password",
    "recovery_key",
    "recovery_password",
    "secret",
    "token",
}


def _reject_secret_fields(value: Any, path: str = "root") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = str(key).strip().lower().replace("-", "_")
            if normalized in _SECRET_FIELDS:
                raise FixtureError(f"secret field is forbidden at {path}.{key}")
            _reject_secret_fields(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _reject_secret_fields(child, f"{path}[{index}]")


class FixtureRepository:
    def __init__(self, root: Path) -> None:
        self.root = root

    def list(self) -> list[dict[str, str]]:
        scenarios: list[dict[str, str]] = []
        for path in sorted(self.root.glob("*.json")):
            payload = self._read(path)
            scenarios.append(
                {
                    "id": str(payload["id"]),
                    "title": str(payload["title"]),
                    "category": str(payload["category"]),
                }
            )
        return scenarios

    def load(self, scenario_id: str) -> EvidenceSnapshot:
        path = self.root / f"{scenario_id}.json"
        if not path.is_file():
            raise FixtureError(f"unknown fixture: {scenario_id}")
        payload = self._read(path)
        if payload.get("id") != scenario_id:
            raise FixtureError("fixture id does not match filename")

        target_data = payload["target"]
        evidence_data = payload["evidence"]
        return EvidenceSnapshot(
            scenario_id=scenario_id,
            title=str(payload["title"]),
            category=str(payload["category"]),
            target=TargetFingerprint(
                disk_serial=str(target_data["disk_serial"]),
                partition_guid=str(target_data["partition_guid"]),
                filesystem_uuid=str(target_data["filesystem_uuid"]),
                windows_path=str(target_data["windows_path"]),
                bitlocker_key_id=target_data.get("bitlocker_key_id"),
            ),
            smart_status=str(evidence_data["smart_status"]),
            read_errors=int(evidence_data["read_errors"]),
            bitlocker_state=BitLockerState(evidence_data["bitlocker_state"]),
            bcd_valid=bool(evidence_data["bcd_valid"]),
            boot_files_present=bool(evidence_data["boot_files_present"]),
            network_available=bool(evidence_data["network_available"]),
            notes=tuple(str(note) for note in evidence_data.get("notes", [])),
        )

    @staticmethod
    def _read(path: Path) -> dict[str, Any]:
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise FixtureError(f"invalid fixture: {path.name}") from error
        if not isinstance(payload, dict):
            raise FixtureError("fixture root must be an object")
        _reject_secret_fields(payload)
        return payload
