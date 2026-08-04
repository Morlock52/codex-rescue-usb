from __future__ import annotations

from dataclasses import replace
from threading import RLock
from uuid import uuid4

from codex_rescue.artifacts import (
    PostActionFixtureRepository,
    RollbackArtifactRepository,
)
from codex_rescue.case_store import CaseStore, InMemoryCaseStore
from codex_rescue.diagnostics import analyze
from codex_rescue.fixtures import FixtureRepository
from codex_rescue.models import (
    Approval,
    ApprovalFingerprint,
    CaseEvent,
    CaseRecord,
    CaseStage,
    Operation,
    utc_now,
)
from codex_rescue.operations import OperationRegistry
from codex_rescue.runner import SimulatedRepairRunner, SimulatedVerifier
from codex_rescue.safety import SafetyBroker


class PolicyBlocked(RuntimeError):
    def __init__(self, reasons: tuple[str, ...]) -> None:
        super().__init__("; ".join(reasons))
        self.reasons = reasons


class CaseNotFound(KeyError):
    pass


class CaseService:
    def __init__(
        self,
        fixtures: FixtureRepository,
        *,
        case_store: CaseStore | None = None,
        rollback_artifacts: RollbackArtifactRepository | None = None,
        post_actions: PostActionFixtureRepository | None = None,
        registry: OperationRegistry | None = None,
    ) -> None:
        self.fixtures = fixtures
        self.case_store = case_store or InMemoryCaseStore()
        self.registry = registry or OperationRegistry()
        self.rollback_artifacts = rollback_artifacts or RollbackArtifactRepository(
            fixtures.root / "rollback"
        )
        self.post_actions = post_actions or PostActionFixtureRepository(
            fixtures.root / "post_action"
        )
        self.broker = SafetyBroker(self.registry)
        self.runner = SimulatedRepairRunner(self.registry)
        self.verifier = SimulatedVerifier(self.registry)
        self._cases: dict[str, CaseRecord] = {}
        self._lock = RLock()

    def list_scenario_summaries(self) -> list[dict[str, object]]:
        return self.fixtures.list_scenario_summaries()

    def problem_catalog(self) -> list[dict[str, object]]:
        return self.fixtures.problem_catalog()

    def create_case(self, scenario_id: str) -> CaseRecord:
        with self._lock:
            evidence = self.fixtures.load(scenario_id)
            findings = analyze(evidence)
            proposal = None
            operation = findings[0].suggested_operation
            if operation is not None:
                rollback = self.rollback_artifacts.load_for(evidence, operation)
                proposal = self.registry.require(operation).create_proposal(
                    uuid4().hex,
                    evidence,
                    rollback,
                )
            if any(finding.blocks_writes for finding in findings):
                stage = CaseStage.BLOCKED
            elif proposal is not None:
                stage = CaseStage.PROPOSED
            else:
                stage = CaseStage.DIAGNOSED

            case = CaseRecord(
                case_id=uuid4().hex,
                evidence=evidence,
                findings=findings,
                stage=stage,
                proposal=proposal,
            )
            case = self._record(case, "evidence.loaded", "Fixture evidence loaded")
            case = self._record(
                case,
                "diagnosis.completed",
                "Offline deterministic diagnosis completed",
            )
            if proposal is not None:
                case = self._record(
                    case,
                    "proposal.created",
                    "Complete simulated proposal and rollback artifact verified",
                )
            self._cases[case.case_id] = case
            return case

    def get_case(self, case_id: str) -> CaseRecord:
        with self._lock:
            try:
                return self._cases[case_id]
            except KeyError as error:
                raise CaseNotFound(case_id) from error

    def get_case_events(self, case_id: str) -> tuple[CaseEvent, ...]:
        self.get_case(case_id)
        return self.case_store.read(case_id)

    def approve(
        self,
        case_id: str,
        fingerprint: ApprovalFingerprint,
    ) -> CaseRecord:
        with self._lock:
            case = self.get_case(case_id)
            if case.proposal is None:
                raise PolicyBlocked(("case has no executable proposal",))
            if case.stage != CaseStage.PROPOSED:
                raise PolicyBlocked(("case is not awaiting approval",))
            if fingerprint != case.proposal.approval_fingerprint():
                raise PolicyBlocked(
                    ("approval fingerprint does not match complete proposal",)
                )
            approval = Approval(
                fingerprint=fingerprint,
                approved_by="local-user",
                approved_at=utc_now(),
            )
            updated = replace(
                case,
                approval=approval,
                stage=CaseStage.APPROVED,
            )
            updated = self._record(
                updated,
                "approval.granted",
                "Local user approved one exact simulated action",
            )
            self._cases[case_id] = updated
            return updated

    def execute(self, case_id: str) -> CaseRecord:
        with self._lock:
            case = self.get_case(case_id)
            if case.proposal is None:
                raise PolicyBlocked(("case has no executable proposal",))
            if case.approval is None:
                raise PolicyBlocked(("approval is required",))
            if case.stage != CaseStage.APPROVED:
                raise PolicyBlocked(("approval permits one execution only",))

            decision = self.broker.evaluate(
                case.proposal,
                case.evidence,
                case.approval,
            )
            if not decision.allowed:
                raise PolicyBlocked(decision.reasons)

            execution = self.runner.execute(case.proposal, case.approval)
            post_evidence = self.post_actions.collect(case.evidence, case.proposal)
            verification = self.verifier.verify(
                case.proposal,
                case.approval,
                execution,
                post_evidence,
            )
            stage = CaseStage.VERIFIED if verification.passed else CaseStage.FAILED
            updated = replace(
                case,
                execution=execution,
                post_action_evidence=post_evidence,
                verification=verification,
                stage=stage,
            )
            updated = self._record(
                updated,
                "execution.completed",
                execution.message,
            )
            updated = self._record(
                updated,
                "verification.completed",
                verification.message,
            )
            self._cases[case_id] = updated
            return updated

    def _record(self, case: CaseRecord, kind: str, message: str) -> CaseRecord:
        previous_hash = case.event_log[-1].event_hash if case.event_log else ""
        event = CaseEvent.create(
            case_id=case.case_id,
            sequence=len(case.event_log) + 1,
            kind=kind,
            message=message,
            previous_hash=previous_hash,
        )
        self.case_store.append(event)
        return replace(case, event_log=case.event_log + (event,))
