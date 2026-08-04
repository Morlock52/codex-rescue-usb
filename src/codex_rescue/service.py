from __future__ import annotations

from dataclasses import replace
from threading import RLock
from uuid import uuid4

from codex_rescue.diagnostics import analyze
from codex_rescue.fixtures import FixtureRepository
from codex_rescue.models import (
    Approval,
    CaseStage,
    CaseRecord,
    EvidenceSnapshot,
    Operation,
    RepairProposal,
    RiskLevel,
)
from codex_rescue.runner import (
    FixturePostActionProbe,
    SimulatedRepairRunner,
    SimulatedVerifier,
)
from codex_rescue.safety import SafetyBroker


class PolicyBlocked(RuntimeError):
    def __init__(self, reasons: tuple[str, ...]) -> None:
        super().__init__("; ".join(reasons))
        self.reasons = reasons


class CaseNotFound(KeyError):
    pass


class CaseService:
    def __init__(self, fixtures: FixtureRepository) -> None:
        self.fixtures = fixtures
        self.broker = SafetyBroker()
        self.runner = SimulatedRepairRunner()
        self.post_action_probe = FixturePostActionProbe()
        self.verifier = SimulatedVerifier()
        self._cases: dict[str, CaseRecord] = {}
        self._lock = RLock()

    def list_scenarios(self) -> list[dict[str, str]]:
        return self.fixtures.list()

    def create_case(self, scenario_id: str) -> CaseRecord:
        with self._lock:
            evidence = self.fixtures.load(scenario_id)
            findings = analyze(evidence)
            proposal = self._proposal_for(findings[0].suggested_operation, evidence)
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
                event_log=("Fixture evidence loaded", "Offline diagnosis completed"),
            )
            if proposal is not None:
                case = replace(
                    case,
                    event_log=case.event_log + ("Structured simulated proposal created",),
                )
            self._cases[case.case_id] = case
            return case

    def get_case(self, case_id: str) -> CaseRecord:
        with self._lock:
            try:
                return self._cases[case_id]
            except KeyError as error:
                raise CaseNotFound(case_id) from error

    def approve(
        self,
        case_id: str,
        proposal_id: str,
        target_digest: str,
    ) -> CaseRecord:
        with self._lock:
            case = self.get_case(case_id)
            if case.proposal is None:
                raise PolicyBlocked(("case has no executable proposal",))
            if case.stage != CaseStage.PROPOSED:
                raise PolicyBlocked(("case is not awaiting approval",))
            if proposal_id != case.proposal.proposal_id:
                raise PolicyBlocked(("proposal id does not match",))
            if target_digest != case.proposal.target.digest():
                raise PolicyBlocked(("target digest does not match",))
            approval = Approval(
                proposal_id=proposal_id,
                target_digest=target_digest,
                approved_by="local-user",
            )
            updated = replace(
                case,
                approval=approval,
                stage=CaseStage.APPROVED,
                event_log=case.event_log + ("Local user approved one simulated action",),
            )
            self._cases[case_id] = updated
            return updated

    def execute(self, case_id: str) -> CaseRecord:
        with self._lock:
            case = self.get_case(case_id)
            if case.proposal is None:
                raise PolicyBlocked(("case has no executable proposal",))
            if case.stage != CaseStage.APPROVED:
                raise PolicyBlocked(("approval permits one execution only",))

            decision = self.broker.evaluate(
                case.proposal,
                case.evidence,
                case.approval,
            )
            if not decision.allowed:
                raise PolicyBlocked(decision.reasons)

            execution = self.runner.execute(case.proposal)
            post_evidence = self.post_action_probe.collect(case.proposal)
            verification = self.verifier.verify(
                case.proposal,
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
                event_log=case.event_log + (execution.message, verification.message),
            )
            self._cases[case_id] = updated
            return updated

    @staticmethod
    def _proposal_for(
        operation: Operation | None,
        evidence: EvidenceSnapshot,
    ) -> RepairProposal | None:
        if operation != Operation.SIMULATE_BCD_REBUILD:
            return None
        target = evidence.target
        return RepairProposal(
            proposal_id=uuid4().hex,
            operation=operation,
            target=target,
            risk=RiskLevel.REVERSIBLE,
            summary=(
                "Back up the fixture BCD state, simulate rebuilding it, then "
                "verify the simulated result independently."
            ),
            rollback_required=True,
            rollback_artifact_ready=True,
        )
