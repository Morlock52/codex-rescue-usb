from __future__ import annotations

import json
import mimetypes
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from codex_rescue.fixtures import FixtureError
from codex_rescue.serialization import case_to_dict
from codex_rescue.service import CaseNotFound, CaseService, PolicyBlocked


_CASE_ROUTE = re.compile(r"^/api/cases/([a-f0-9]+)$")
_ACTION_ROUTE = re.compile(r"^/api/cases/([a-f0-9]+)/(approve|execute)$")
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
        server_version = "CodexRescue/0.1"

        def do_GET(self) -> None:  # noqa: N802
            if self.path == "/api/health":
                self._send_json(
                    200,
                    {
                        "status": "ok",
                        "fixture_only": True,
                        "host_commands_enabled": False,
                    },
                )
                return
            if self.path == "/api/scenarios":
                self._send_json(200, {"scenarios": service.list_scenarios()})
                return
            case_match = _CASE_ROUTE.fullmatch(self.path)
            if case_match:
                try:
                    self._send_json(200, case_to_dict(service.get_case(case_match[1])))
                except CaseNotFound:
                    self._send_error(404, "case not found")
                return
            if self.path in _STATIC_ROUTES:
                self._send_static(root / _STATIC_ROUTES[self.path])
                return
            self._send_error(404, "not found")

        def do_POST(self) -> None:  # noqa: N802
            try:
                payload = self._read_json()
                if self.path == "/api/cases":
                    scenario_id = self._required_text(payload, "scenario_id")
                    case = service.create_case(scenario_id)
                    self._send_json(201, case_to_dict(case))
                    return

                action_match = _ACTION_ROUTE.fullmatch(self.path)
                if action_match is None:
                    self._send_error(404, "not found")
                    return
                case_id, action = action_match.groups()
                if action == "approve":
                    case = service.approve(
                        case_id,
                        self._required_text(payload, "proposal_id"),
                        self._required_text(payload, "target_digest"),
                    )
                else:
                    case = service.execute(case_id)
                self._send_json(200, case_to_dict(case))
            except CaseNotFound:
                self._send_error(404, "case not found")
            except FixtureError as error:
                self._send_error(404, str(error))
            except PolicyBlocked as error:
                self._send_error(409, str(error), list(error.reasons))
            except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
                self._send_error(400, f"invalid request: {error}")

        def _read_json(self) -> dict[str, Any]:
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

        @staticmethod
        def _required_text(payload: dict[str, Any], key: str) -> str:
            value = payload[key]
            if not isinstance(value, str) or not value.strip():
                raise TypeError(f"{key} must be a non-empty string")
            return value

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
