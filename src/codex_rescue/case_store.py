from __future__ import annotations

import json
import os
import re
from dataclasses import asdict
from pathlib import Path
from threading import RLock
from typing import Protocol

from codex_rescue.models import CaseEvent


_CASE_ID_PATTERN = re.compile(r"^[a-f0-9]{32}$")


class CaseStore(Protocol):
    def append(self, event: CaseEvent) -> None: ...

    def read(self, case_id: str) -> tuple[CaseEvent, ...]: ...


class InMemoryCaseStore:
    def __init__(self) -> None:
        self._events: dict[str, list[CaseEvent]] = {}

    def append(self, event: CaseEvent) -> None:
        self._events.setdefault(event.case_id, []).append(event)

    def read(self, case_id: str) -> tuple[CaseEvent, ...]:
        return tuple(self._events.get(case_id, ()))


class JsonlCaseStore:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.root, 0o700)
        self._lock = RLock()

    def append(self, event: CaseEvent) -> None:
        path = self._path(event.case_id)
        line = json.dumps(asdict(event), sort_keys=True, separators=(",", ":"))
        with self._lock:
            with path.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")
            os.chmod(path, 0o600)

    def read(self, case_id: str) -> tuple[CaseEvent, ...]:
        path = self._path(case_id)
        if not path.exists():
            return ()
        events: list[CaseEvent] = []
        with self._lock:
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except (OSError, UnicodeError) as error:
                raise ValueError("case audit log cannot be read") from error
        for line in lines:
            try:
                payload = json.loads(line)
                events.append(CaseEvent(**payload))
            except (TypeError, json.JSONDecodeError) as error:
                raise ValueError("case audit log is malformed") from error
        if not verify_event_chain(events):
            raise ValueError("case audit hash chain is invalid")
        return tuple(events)

    def _path(self, case_id: str) -> Path:
        if not _CASE_ID_PATTERN.fullmatch(case_id):
            raise ValueError("case id has invalid format")
        path = (self.root / f"{case_id}.jsonl").resolve()
        if path.parent != self.root:
            raise ValueError("case path escapes audit root")
        return path


def verify_event_chain(events: tuple[CaseEvent, ...] | list[CaseEvent]) -> bool:
    previous_hash = ""
    for index, event in enumerate(events, start=1):
        if event.sequence != index:
            return False
        if event.previous_hash != previous_hash or not event.verify_hash():
            return False
        previous_hash = event.event_hash
    return True
