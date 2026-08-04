from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tests.helpers import ROOT

from codex_rescue.case_store import JsonlCaseStore, verify_event_chain
from codex_rescue.fixtures import FixtureRepository
from codex_rescue.service import CaseService


class CaseAuditTests(unittest.TestCase):
    def test_case_events_are_timestamped_hashed_and_persisted(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            store = JsonlCaseStore(Path(temp_dir))
            service = CaseService(
                FixtureRepository(ROOT / "fixtures"),
                case_store=store,
            )
            case = service.create_case("boot-loop")
            assert case.proposal is not None
            service.approve(case.case_id, case.proposal.approval_fingerprint())
            service.execute(case.case_id)

            events = store.read(case.case_id)
            restarted_service = CaseService(
                FixtureRepository(ROOT / "fixtures"),
                case_store=JsonlCaseStore(Path(temp_dir)),
            )
            restarted_events = restarted_service.get_case_events(case.case_id)

        self.assertGreaterEqual(len(events), 5)
        self.assertTrue(all(event.occurred_at for event in events))
        self.assertTrue(verify_event_chain(events))
        self.assertEqual(events, restarted_events)
        payloads = {event.kind: json.loads(event.payload_json) for event in events}
        self.assertEqual(payloads["evidence.loaded"]["scenario_id"], "boot-loop")
        self.assertIn("proposal_digest", payloads["proposal.created"])
        self.assertIn("fingerprint", payloads["approval.granted"])
        self.assertIn("receipt", payloads["execution.completed"])
        self.assertIn("post_action_evidence", payloads["verification.completed"])


if __name__ == "__main__":
    unittest.main()
