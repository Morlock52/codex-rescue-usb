from __future__ import annotations

from uuid import uuid4

from codex_rescue.diagnostics import analyze
from codex_rescue.fixtures import FixtureRepository
from codex_rescue.models import (
    Approval,
    CaseRecord,
    RepairProposal,
    RiskLevel,
)
from codex_rescue.runner import SimulatedRepairRunner
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
        self._cases: dict[str, CaseRecord] = {}

    def list_scenarios(self) -> list[dict[str, str]]:
        return self.fixtures.list()

    def create_case(self, scenario_id: str) -> CaseRecord:
        evidence = self.fixtures.load(scenario_id)
        findings = analyze(evidence)
        proposal = self._proposal_for(findings[0].suggested_operation, evidence)
        if any(finding.blocks_writes for finding in findings):
            stage = "blocked"
        elif proposal is not None:
            stage = "proposed"
        else:
            stage = "diagnosed"

        case = CaseRecord(
            case_id=uuid4().hex,
            evidence=evidence,
            findings=findings,
            stage=stage,
            proposal=proposal,
            event_log=["Fixture evidence loaded", "Offline diagnosis completed"],
        )
        if proposal is not None:
            case.event_log.append("Structured simulated proposal created")
        self._cases[case.case_id] = case
        return case

    def get_case(self, case_id: str) -> CaseRecord:
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
        case = self.get_case(case_id)
        if case.proposal is None:
            raise PolicyBlocked(("case has no executable proposal",))
        if proposal_id != case.proposal.proposal_id:
            raise PolicyBlocked(("proposal id does not match",))
        if target_digest != case.proposal.target.digest():
            raise PolicyBlocked(("target digest does not match",))
        case.approval = Approval(
            proposal_id=proposal_id,
            target_digest=target_digest,
            approved_by="local-user",
        )
        case.stage = "approved"
        case.event_log.append("Local user approved the simulated proposal")
        return case

    def execute(self, case_id: str) -> CaseRecord:
        case = self.get_case(case_id)
        if case.proposal is None:
            raise PolicyBlocked(("case has no executable proposal",))

        decision = self.broker.evaluate(
            case.proposal,
            case.evidence,
            case.approval,
        )
        if not decision.allowed:
            raise PolicyBlocked(decision.reasons)

        case.execution = self.runner.execute(case.proposal)
        case.event_log.append(case.execution.message)
        case.verification = self.runner.verify(case.proposal, case.execution)
        case.event_log.append(case.verification.message)
        case.stage = "verified" if case.verification.passed else "failed"
        return case

    @staticmethod
    def _proposal_for(operation: str | None, evidence: object) -> RepairProposal | None:
        if operation != "simulate.bcd.rebuild":
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
