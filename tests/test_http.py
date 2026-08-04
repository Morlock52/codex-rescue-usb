from __future__ import annotations

import json
import threading
import unittest
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from tests.helpers import ROOT

from codex_rescue.fixtures import FixtureRepository
from codex_rescue.http_server import build_server
from codex_rescue.service import CaseService


@contextmanager
def running_server() -> Iterator[str]:
    service = CaseService(FixtureRepository(ROOT / "fixtures"))
    server = build_server(service, ROOT / "web", port=0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        host, port = server.server_address
        yield f"http://{host}:{port}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def request_json(
    base_url: str,
    path: str,
    method: str = "GET",
    payload: dict[str, str] | None = None,
) -> tuple[int, dict[str, object]]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(
        base_url + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        response = urlopen(request, timeout=2)
    except HTTPError as error:
        try:
            return error.code, json.loads(error.read().decode("utf-8"))
        finally:
            error.close()
    with response:
        return response.status, json.loads(response.read().decode("utf-8"))


class HttpServerTests(unittest.TestCase):
    def test_server_binds_to_loopback_and_reports_fixture_boundary(self) -> None:
        service = CaseService(FixtureRepository(ROOT / "fixtures"))
        server = build_server(service, ROOT / "web", port=0)
        try:
            self.assertEqual(server.server_address[0], "127.0.0.1")
        finally:
            server.server_close()

        with running_server() as base_url:
            status, payload = request_json(base_url, "/api/health")

        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "ok")
        self.assertTrue(payload["fixture_only"])
        self.assertFalse(payload["host_commands_enabled"])

    def test_fixture_case_can_be_approved_and_simulated(self) -> None:
        with running_server() as base_url:
            status, scenarios = request_json(base_url, "/api/scenarios")
            self.assertEqual(status, 200)
            self.assertEqual(len(scenarios["scenarios"]), 3)

            status, case = request_json(
                base_url,
                "/api/cases",
                "POST",
                {"scenario_id": "boot-loop"},
            )
            self.assertEqual(status, 201)
            self.assertEqual(case["stage"], "proposed")
            self.assertNotIn("recovery_key", json.dumps(case).lower())

            case_id = str(case["case_id"])
            proposal = case["proposal"]
            self.assertIsInstance(proposal, dict)
            assert isinstance(proposal, dict)

            status, blocked = request_json(
                base_url,
                f"/api/cases/{case_id}/approve",
                "POST",
                {
                    "proposal_id": str(proposal["proposal_id"]),
                    "target_digest": "wrong-target",
                },
            )
            self.assertEqual(status, 409)
            self.assertIn("target digest does not match", blocked["error"])

            status, approved = request_json(
                base_url,
                f"/api/cases/{case_id}/approve",
                "POST",
                {
                    "proposal_id": str(proposal["proposal_id"]),
                    "target_digest": str(proposal["target_digest"]),
                },
            )
            self.assertEqual(status, 200)
            self.assertEqual(approved["stage"], "approved")

            status, completed = request_json(
                base_url,
                f"/api/cases/{case_id}/execute",
                "POST",
                {},
            )
            self.assertEqual(status, 200)
            self.assertEqual(completed["stage"], "verified")
            self.assertTrue(completed["verification"]["passed"])

    def test_static_console_has_no_external_runtime_dependencies(self) -> None:
        with running_server() as base_url:
            with urlopen(base_url + "/", timeout=2) as response:
                body = response.read().decode("utf-8")

        self.assertIn("Codex Rescue USB", body)
        self.assertNotIn("https://", body)
        self.assertNotIn("http://", body)


if __name__ == "__main__":
    unittest.main()
