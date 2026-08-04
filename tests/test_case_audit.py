from __future__ import annotations

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

        self.assertGreaterEqual(len(events), 5)
        self.assertTrue(all(event.occurred_at for event in events))
        self.assertTrue(verify_event_chain(events))


if __name__ == "__main__":
    unittest.main()
