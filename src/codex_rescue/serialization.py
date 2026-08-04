from __future__ import annotations

from dataclasses import asdict

from codex_rescue.models import CaseEvent, CaseRecord, CaseStage


def event_to_dict(event: CaseEvent) -> dict[str, object]:
    payload = asdict(event)
    payload.pop("payload_json")
    payload["payload"] = event.payload()
    return payload


def _timeline(case: CaseRecord) -> list[dict[str, str]]:
    steps = (
        ("loaded", "Fixture loaded"),
        ("diagnosed", "Diagnosis"),
        ("approved", "Approval"),
        ("verified", "Receipt"),
    )
    stage_index = {
        CaseStage.BLOCKED: 1,
        CaseStage.DIAGNOSED: 1,
        CaseStage.PROPOSED: 2,
        CaseStage.APPROVED: 3,
        CaseStage.VERIFIED: 3,
        CaseStage.FAILED: 3,
    }[case.stage]
    states: list[dict[str, str]] = []
    for index, (key, label) in enumerate(steps):
        if index < stage_index or (
            case.stage == CaseStage.VERIFIED and index == stage_index
        ):
            state = "complete"
        elif index == stage_index:
            state = "current"
        else:
            state = "pending"
        states.append({"key": key, "label": label, "state": state})
    return states


def _workflow(case: CaseRecord) -> dict[str, object]:
    action = None
    allowed_actions: list[str] = []
    interlock = "No action"
    if case.stage == CaseStage.PROPOSED:
        allowed_actions = ["approve"]
        interlock = "Simulation armed"
        action = {
            "id": "approve",
            "label": "Approve exact simulated plan",
            "hint": "Binds approval to the full proposal and exact target.",
        }
    elif case.stage == CaseStage.APPROVED:
        allowed_actions = ["execute"]
        interlock = "Approved once"
        action = {
            "id": "execute",
            "label": "Run safe simulation",
            "hint": "Creates a typed receipt with zero host impact.",
        }
    elif case.stage == CaseStage.BLOCKED:
        interlock = "Blocked"
        action = {
            "id": "blocked",
            "label": "Repair blocked",
            "hint": "Follow the recovery guidance; no operation is available.",
        }
    elif case.stage == CaseStage.VERIFIED:
        interlock = "Verified"
        action = {
            "id": "complete",
            "label": "Simulation verified",
            "hint": case.verification.message if case.verification else "Verified",
        }
    elif case.stage == CaseStage.FAILED:
        interlock = "Verification failed"
        action = {
            "id": "failed",
            "label": "Stop — verification failed",
            "hint": "Do not retry automatically; retain the last safe state.",
        }

    stop_reason = None
    recovery_action = None
    last_safe_state = "Read-only fixture evidence retained"
    if case.stage == CaseStage.BLOCKED:
        stop_reason = case.findings[0].summary
        recovery_action = (
            "Escalate through the separate authorized recovery workflow. "
            "Do not enter recovery material in this prototype."
        )
    elif case.stage == CaseStage.FAILED:
        stop_reason = (
            case.verification.message
            if case.verification is not None
            else "Post-action verification did not pass"
        )
        recovery_action = (
            "Keep the verified rollback artifact, inspect the receipt and independent "
            "evidence, then open a new case only after the contradiction is resolved."
        )
    elif case.stage == CaseStage.VERIFIED:
        last_safe_state = "Verified fixture post-action state retained"
    elif case.proposal is not None:
        last_safe_state = "Read-only evidence and verified rollback artifact retained"

    return {
        "stage": case.stage.value,
        "interlock": interlock,
        "allowed_actions": allowed_actions,
        "action": action,
        "timeline": _timeline(case),
        "last_safe_state": last_safe_state,
        "stop_reason": stop_reason,
        "recovery_action": recovery_action,
    }


def case_to_dict(case: CaseRecord) -> dict[str, object]:
    proposal = None
    if case.proposal is not None:
        fingerprint = case.proposal.approval_fingerprint()
        proposal = {
            **asdict(case.proposal),
            "operation": case.proposal.operation.value,
            "risk": case.proposal.risk.value,
            "target": case.proposal.target.canonical(),
            "proposal_digest": case.proposal.digest(),
            "approval_fingerprint": asdict(fingerprint),
            "approval_fingerprint_digest": fingerprint.digest(),
        }

    approval = None
    if case.approval is not None:
        approval = {
            "fingerprint": asdict(case.approval.fingerprint),
            "fingerprint_digest": case.approval.fingerprint.digest(),
            "approved_by": case.approval.approved_by,
            "approved_at": case.approval.approved_at,
        }

    execution = None
    if case.execution is not None:
        execution = {
            "success": case.execution.success,
            "message": case.execution.message,
            "receipt": (
                asdict(case.execution.receipt)
                if case.execution.receipt is not None
                else None
            ),
        }

    return {
        "case_id": case.case_id,
        "stage": case.stage.value,
        "fixture_only": True,
        "codex_contacted": False,
        "evidence": {
            "scenario_id": case.evidence.scenario_id,
            "title": case.evidence.title,
            "category": case.evidence.category,
            "smart_status": case.evidence.smart_status.value,
            "read_errors": case.evidence.read_errors,
            "bitlocker_state": case.evidence.bitlocker_state.value,
            "bcd_valid": case.evidence.bcd_valid,
            "boot_files_present": case.evidence.boot_files_present,
            "network_available": case.evidence.network_available,
            "target_digest": case.evidence.target.digest(),
            "target": case.evidence.target.canonical(),
            "notes": list(case.evidence.notes),
        },
        "findings": [
            {
                "code": finding.code,
                "severity": finding.severity.value,
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
        "post_action_evidence": (
            asdict(case.post_action_evidence)
            if case.post_action_evidence is not None
            else None
        ),
        "verification": (
            asdict(case.verification) if case.verification is not None else None
        ),
        "workflow": _workflow(case),
        "event_log": [event_to_dict(event) for event in case.event_log],
    }
