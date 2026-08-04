from __future__ import annotations

import json
import mimetypes
import re
from dataclasses import asdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from codex_rescue.fixtures import FixtureIntegrityError, FixtureNotFound
from codex_rescue.models import ApprovalFingerprint
from codex_rescue.serialization import case_to_dict
from codex_rescue.service import CaseNotFound, CaseService, PolicyBlocked


_CASE_ROUTE = re.compile(r"^/api/cases/([a-f0-9]{32})$")
_AUDIT_ROUTE = re.compile(r"^/api/cases/([a-f0-9]{32})/audit$")
_ACTION_ROUTE = re.compile(r"^/api/cases/([a-f0-9]{32})/(approve|execute)$")
_STATIC_ROUTES = {
    "/": "index.html",
    "/assets/styles.css": "assets/styles.css",
    "/assets/app.js": "assets/app.js",
}


def build_server(
    service: CaseService,
    static_root: Path,
    port: int = 8080,
) -> ThreadingHTTPServer:
    root = static_root.resolve()

    class RescueRequestHandler(BaseHTTPRequestHandler):
        server_version = "CodexRescue/0.2"

        def do_GET(self) -> None:  # noqa: N802
            try:
                self._handle_get()
            except CaseNotFound:
                self._send_error(404, "case not found")
            except FixtureNotFound as error:
                self._send_error(404, str(error))
            except FixtureIntegrityError:
                self._send_error(500, "trusted fixture integrity failure")
            except ValueError:
                self._send_error(500, "case audit integrity failure")

        def _handle_get(self) -> None:
            if self.path == "/api/health":
                self._send_json(
                    200,
                    {
                        "status": "ok",
                        "fixture_only": True,
                        "host_commands_enabled": False,
                        "codex_contacted": False,
                    },
                )
                return
            if self.path == "/api/scenarios":
                self._send_json(
                    200,
                    {
                        "scenarios": service.list_scenario_summaries(),
                        "categories": service.problem_catalog(),
                    },
                )
                return
            audit_match = _AUDIT_ROUTE.fullmatch(self.path)
            if audit_match:
                events = service.get_case_events(audit_match[1])
                self._send_json(200, {"events": [asdict(event) for event in events]})
                return
            case_match = _CASE_ROUTE.fullmatch(self.path)
            if case_match:
                self._send_json(200, case_to_dict(service.get_case(case_match[1])))
                return
            if self.path in _STATIC_ROUTES:
                self._send_static(root / _STATIC_ROUTES[self.path])
                return
            self._send_error(404, "not found")

        def do_POST(self) -> None:  # noqa: N802
            try:
                self._handle_post()
            except CaseNotFound:
                self._send_error(404, "case not found")
            except FixtureNotFound as error:
                self._send_error(404, str(error))
            except FixtureIntegrityError:
                self._send_error(500, "trusted fixture integrity failure")
            except PolicyBlocked as error:
                self._send_error(409, str(error), list(error.reasons))
            except (KeyError, TypeError, ValueError, UnicodeError, json.JSONDecodeError) as error:
                self._send_error(400, f"invalid request: {error}")

        def _handle_post(self) -> None:
            payload = self._read_json()
            if self.path == "/api/cases":
                self._require_exact_fields(payload, {"scenario_id"})
                case = service.create_case(self._required_text(payload, "scenario_id"))
                self._send_json(201, case_to_dict(case))
                return

            action_match = _ACTION_ROUTE.fullmatch(self.path)
            if action_match is None:
                self._send_error(404, "not found")
                return
            case_id, action = action_match.groups()
            if action == "approve":
                self._require_exact_fields(payload, {"fingerprint"})
                case = service.approve(
                    case_id,
                    self._approval_fingerprint(payload["fingerprint"]),
                )
            else:
                self._require_exact_fields(payload, set())
                case = service.execute(case_id)
            self._send_json(200, case_to_dict(case))

        def _read_json(self) -> dict[str, Any]:
            content_type = self.headers.get("Content-Type", "").split(";", 1)[0]
            if content_type != "application/json":
                raise TypeError("Content-Type must be application/json")
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError as error:
                raise ValueError("invalid content length") from error
            if length < 0 or length > 65_536:
                raise ValueError("request body is too large")
            raw = self.rfile.read(length)
            value = json.loads(raw.decode("utf-8") or "{}")
            if not isinstance(value, dict):
                raise TypeError("JSON body must be an object")
            return value

        @classmethod
        def _approval_fingerprint(cls, value: object) -> ApprovalFingerprint:
            if not isinstance(value, dict):
                raise TypeError("fingerprint must be an object")
            cls._require_exact_fields(
                value,
                {"proposal_id", "proposal_digest", "target_digest"},
            )
            return ApprovalFingerprint(
                proposal_id=cls._required_text(value, "proposal_id"),
                proposal_digest=cls._required_text(value, "proposal_digest"),
                target_digest=cls._required_text(value, "target_digest"),
            )

        @staticmethod
        def _required_text(payload: dict[str, Any], key: str) -> str:
            value = payload[key]
            if not isinstance(value, str) or not value.strip():
                raise TypeError(f"{key} must be a non-empty string")
            return value.strip()

        @staticmethod
        def _require_exact_fields(
            payload: dict[str, Any],
            expected: set[str],
        ) -> None:
            missing = sorted(expected - set(payload))
            unexpected = sorted(set(payload) - expected)
            if missing:
                raise ValueError("missing request fields: " + ", ".join(missing))
            if unexpected:
                raise ValueError(
                    "unexpected request fields: " + ", ".join(unexpected)
                )

        def _send_static(self, path: Path) -> None:
            try:
                body = path.read_bytes()
            except OSError:
                self._send_error(404, "asset not found")
                return
            content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            self.send_response(200)
            self._send_common_headers(content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _send_json(self, status: int, payload: dict[str, object]) -> None:
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self._send_common_headers("application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _send_error(
            self,
            status: int,
            message: str,
            reasons: list[str] | None = None,
        ) -> None:
            payload: dict[str, object] = {"error": message}
            if reasons is not None:
                payload["reasons"] = reasons
            self._send_json(status, payload)

        def _send_common_headers(self, content_type: str) -> None:
            self.send_header("Content-Type", content_type)
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header(
                "Content-Security-Policy",
                "default-src 'self'; script-src 'self'; style-src 'self'; "
                "img-src 'self'; connect-src 'self'; object-src 'none'; "
                "base-uri 'none'; frame-ancestors 'none'",
            )

        def log_message(self, format: str, *args: object) -> None:
            return

    return ThreadingHTTPServer(("127.0.0.1", port), RescueRequestHandler)
