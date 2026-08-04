from __future__ import annotations

from codex_rescue.models import CaseRecord


def case_to_dict(case: CaseRecord) -> dict[str, object]:
    proposal = None
    if case.proposal is not None:
        proposal = {
            "proposal_id": case.proposal.proposal_id,
            "operation": case.proposal.operation.value,
            "risk": case.proposal.risk.value,
            "summary": case.proposal.summary,
            "rollback_required": case.proposal.rollback_required,
            "rollback_artifact_ready": case.proposal.rollback_artifact_ready,
            "target_digest": case.proposal.target.digest(),
        }

    approval = None
    if case.approval is not None:
        approval = {
            "proposal_id": case.approval.proposal_id,
            "target_digest": case.approval.target_digest,
            "approved_by": case.approval.approved_by,
        }

    execution = None
    if case.execution is not None:
        execution = {
            "success": case.execution.success,
            "message": case.execution.message,
            "output": case.execution.output,
        }

    verification = None
    if case.verification is not None:
        verification = {
            "passed": case.verification.passed,
            "message": case.verification.message,
        }

    return {
        "case_id": case.case_id,
        "stage": case.stage.value,
        "fixture_only": True,
        "evidence": {
            "scenario_id": case.evidence.scenario_id,
            "title": case.evidence.title,
            "category": case.evidence.category,
            "smart_status": case.evidence.smart_status,
            "read_errors": case.evidence.read_errors,
            "bitlocker_state": case.evidence.bitlocker_state.value,
            "bcd_valid": case.evidence.bcd_valid,
            "boot_files_present": case.evidence.boot_files_present,
            "network_available": case.evidence.network_available,
            "target_digest": case.evidence.target.digest(),
            "notes": list(case.evidence.notes),
        },
        "findings": [
            {
                "code": finding.code,
                "severity": finding.severity,
                "title": finding.title,
                "summary": finding.summary,
                "blocks_writes": finding.blocks_writes,
                "confidence": finding.confidence,
                "uncertainty": finding.uncertainty,
            }
            for finding in case.findings
        ],
        "proposal": proposal,
        "approval": approval,
        "execution": execution,
        "verification": verification,
        "event_log": list(case.event_log),
    }
