from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from codex_rescue.fixtures import FixtureIntegrityError
from codex_rescue.models import (
    EvidenceSnapshot,
    Operation,
    PostActionEvidence,
    RepairProposal,
    RollbackArtifact,
    TargetFingerprint,
    canonical_digest,
)


_OPERATION_FILENAMES = {
    Operation.SIMULATE_BCD_REBUILD: "bcd-rebuild",
}


def _operation_fixture_path(
    root: Path,
    scenario_id: str,
    operation: Operation,
) -> Path:
    operation_name = _OPERATION_FILENAMES.get(operation)
    if operation_name is None:
        raise FixtureIntegrityError("operation has no artifact fixture")
    path = (root / f"{scenario_id}-{operation_name}.json").resolve()
    if path.parent != root or not path.is_file():
        raise FixtureIntegrityError("operation artifact fixture is missing")
    return path


def _read_object(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise FixtureIntegrityError(f"invalid artifact fixture: {path.name}") from error
    if not isinstance(payload, dict):
        raise FixtureIntegrityError(f"artifact fixture must be an object: {path.name}")
    return payload


def _require_exact_keys(
    payload: dict[str, Any],
    required: set[str],
    path: Path,
) -> None:
    if set(payload) != required:
        raise FixtureIntegrityError(f"artifact fixture schema mismatch: {path.name}")


def _target_from_payload(value: object, path: Path) -> TargetFingerprint:
    if not isinstance(value, dict):
        raise FixtureIntegrityError(f"artifact target is invalid: {path.name}")
    _require_exact_keys(
        value,
        {
            "disk_serial",
            "partition_guid",
            "filesystem_uuid",
            "windows_path",
            "bitlocker_key_id",
        },
        path,
    )
    if not all(
        isinstance(value[key], str) and value[key].strip()
        for key in ("disk_serial", "partition_guid", "filesystem_uuid", "windows_path")
    ):
        raise FixtureIntegrityError(f"artifact target is incomplete: {path.name}")
    if value["bitlocker_key_id"] is not None and not isinstance(
        value["bitlocker_key_id"], str
    ):
        raise FixtureIntegrityError(f"artifact key id is invalid: {path.name}")
    return TargetFingerprint(**value)


class RollbackArtifactRepository:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()

    def load_for(
        self,
        evidence: EvidenceSnapshot,
        operation: Operation,
    ) -> RollbackArtifact:
        path = _operation_fixture_path(self.root, evidence.scenario_id, operation)
        payload = _read_object(path)
        _require_exact_keys(
            payload,
            {
                "artifact_id",
                "scenario_id",
                "operation",
                "kind",
                "target",
                "payload",
                "expected_content_digest",
                "restore_test",
                "verified_at",
            },
            path,
        )
        if payload["scenario_id"] != evidence.scenario_id:
            raise FixtureIntegrityError("rollback artifact scenario does not match")
        if payload["operation"] != operation.value:
            raise FixtureIntegrityError("rollback artifact operation does not match")
        target = _target_from_payload(payload["target"], path)
        if target.digest() != evidence.target.digest():
            raise FixtureIntegrityError("rollback artifact target does not match evidence")
        content_digest = canonical_digest(payload["payload"])
        if content_digest != payload["expected_content_digest"]:
            raise FixtureIntegrityError("rollback artifact content digest does not match")
        restore_test = payload["restore_test"]
        if not isinstance(restore_test, dict) or set(restore_test) != {
            "status",
            "restored_content_digest",
        }:
            raise FixtureIntegrityError("rollback restore test is invalid")
        restore_tested = bool(
            restore_test["status"] == "passed"
            and restore_test["restored_content_digest"] == content_digest
        )
        if not restore_tested:
            raise FixtureIntegrityError("rollback artifact restore test failed")
        for key in ("artifact_id", "kind", "verified_at"):
            if not isinstance(payload[key], str) or not payload[key].strip():
                raise FixtureIntegrityError(f"rollback artifact {key} is invalid")
        return RollbackArtifact(
            artifact_id=payload["artifact_id"],
            scenario_id=evidence.scenario_id,
            kind=payload["kind"],
            target_digest=target.digest(),
            content_digest=content_digest,
            restore_tested=True,
            verified_at=payload["verified_at"],
        )

class PostActionFixtureRepository:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()

    def collect(
        self,
        evidence: EvidenceSnapshot,
        proposal: RepairProposal,
    ) -> PostActionEvidence:
        path = _operation_fixture_path(
            self.root,
            evidence.scenario_id,
            proposal.operation,
        )
        payload = _read_object(path)
        _require_exact_keys(
            payload,
            {
                "scenario_id",
                "operation",
                "target",
                "observed",
                "observed_at",
            },
            path,
        )
        if payload["scenario_id"] != evidence.scenario_id:
            raise FixtureIntegrityError("post-action scenario does not match")
        if payload["operation"] != proposal.operation.value:
            raise FixtureIntegrityError("post-action operation does not match")
        target = _target_from_payload(payload["target"], path)
        observed = payload["observed"]
        if not isinstance(observed, dict) or set(observed) != {
            "bcd_valid",
            "rollback_artifact_digest",
        }:
            raise FixtureIntegrityError("post-action observations are invalid")
        if type(observed["bcd_valid"]) is not bool:
            raise FixtureIntegrityError("post-action bcd_valid must be boolean")
        if not isinstance(observed["rollback_artifact_digest"], str):
            raise FixtureIntegrityError("post-action artifact digest is invalid")
        if not isinstance(payload["observed_at"], str) or not payload["observed_at"]:
            raise FixtureIntegrityError("post-action timestamp is invalid")
        return PostActionEvidence(
            source=f"fixture://post-action/{path.name}",
            source_fixture_digest=canonical_digest(payload),
            scenario_id=evidence.scenario_id,
            operation=proposal.operation,
            target_digest=target.digest(),
            bcd_valid=observed["bcd_valid"],
            rollback_artifact_digest=observed["rollback_artifact_digest"],
            observed_at=payload["observed_at"],
        )
