"use strict";

const state = { categories: [], scenarios: [], case: null, pending: false };

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || `Request failed: ${response.status}`);
  return payload;
}

function exactTarget(target) {
  const keyId = target.bitlocker_key_id ? ` · BitLocker key ID ${target.bitlocker_key_id}` : "";
  return `${target.disk_serial} · partition ${target.partition_guid} · filesystem ${target.filesystem_uuid} · ${target.windows_path}${keyId}`;
}

function setText(id, value) {
  document.getElementById(id).textContent = value ?? "—";
}

function selectedScenario() {
  return state.scenarios.find((scenario) => scenario.id === state.case?.evidence.scenario_id);
}

function appendList(id, values) {
  const list = document.getElementById(id);
  list.replaceChildren();
  for (const value of values || []) {
    const item = document.createElement("li");
    item.textContent = value;
    list.appendChild(item);
  }
}

function renderScenarioRail() {
  const list = document.getElementById("scenario-list");
  list.replaceChildren();

  for (const category of state.categories) {
    const group = document.createElement("section");
    group.className = "category-group";
    group.dataset.status = category.status;

    const header = document.createElement("div");
    header.className = "category-header";
    const title = document.createElement("h3");
    title.textContent = category.label;
    const status = document.createElement("span");
    status.className = "category-status";
    status.textContent = category.status;
    header.append(title, status);

    const description = document.createElement("p");
    description.textContent = category.description;
    group.append(header, description);

    if (category.scenarios.length === 0) {
      const planned = document.createElement("span");
      planned.className = "planned-message";
      planned.textContent = "Workflow planned — unavailable in this milestone";
      group.appendChild(planned);
    }

    for (const scenario of category.scenarios) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "scenario-button";
      button.dataset.scenarioId = scenario.id;
      button.setAttribute("aria-current", String(state.case?.evidence.scenario_id === scenario.id));
      button.disabled = state.pending;
      const scenarioTitle = document.createElement("strong");
      scenarioTitle.textContent = scenario.label;
      const detail = document.createElement("span");
      detail.textContent = scenario.description;
      button.append(scenarioTitle, detail);
      button.addEventListener("click", () => loadCase(scenario.id));
      group.appendChild(button);
    }
    list.appendChild(group);
  }

  const available = state.scenarios.length;
  const planned = state.categories.filter((category) => category.status === "planned").length;
  setText("fixture-count", `${available} offline fixtures · ${planned} categories planned`);
}

function evidenceRows(evidence) {
  return [
    ["Storage health", evidence.smart_status],
    ["Read errors", String(evidence.read_errors)],
    ["BitLocker", evidence.bitlocker_state],
    ["Boot files", evidence.boot_files_present ? "present" : "missing"],
    ["BCD validation", evidence.bcd_valid ? "pass" : "failed"],
    ["Network", evidence.network_available ? "available" : "offline"],
  ];
}

function renderEvidence(evidence) {
  const list = document.getElementById("evidence-list");
  list.replaceChildren();
  for (const [label, value] of evidenceRows(evidence)) {
    const row = document.createElement("div");
    const term = document.createElement("dt");
    const detail = document.createElement("dd");
    term.textContent = label;
    detail.textContent = value;
    row.append(term, detail);
    list.appendChild(row);
  }
}

function renderTimeline(caseRecord) {
  const timeline = document.getElementById("timeline");
  timeline.replaceChildren();
  caseRecord.workflow.timeline.forEach((step, index) => {
    const item = document.createElement("li");
    item.dataset.state = step.state;
    const number = document.createElement("span");
    number.className = "step-number";
    number.textContent = String(index + 1);
    const copy = document.createElement("span");
    copy.textContent = step.label;
    const status = document.createElement("small");
    status.className = "step-state";
    status.textContent = step.state;
    copy.appendChild(status);
    item.append(number, copy);
    timeline.appendChild(item);
  });
}

function renderAction(caseRecord) {
  const button = document.getElementById("action-button");
  const hint = document.getElementById("action-hint");
  const workflowAction = caseRecord.workflow.action;
  button.disabled = true;
  button.onclick = null;
  button.textContent = state.pending ? "Working…" : workflowAction?.label || "No action available";
  hint.textContent = workflowAction?.hint || "No operation is available for this state.";

  if (!state.pending && caseRecord.workflow.allowed_actions.includes("approve")) {
    button.disabled = false;
    button.onclick = approveCase;
  } else if (!state.pending && caseRecord.workflow.allowed_actions.includes("execute")) {
    button.disabled = false;
    button.onclick = executeCase;
  }
}

function renderProposal(proposal) {
  const proposalCard = document.getElementById("proposal-card");
  proposalCard.hidden = !proposal;
  if (!proposal) {
    setText("proposal-id", "—");
    setText("proposal-digest", "—");
    setText("target-digest", "—");
    setText("fingerprint-digest", "—");
    return;
  }

  setText("proposal-title", "Simulated BCD reconstruction");
  setText("proposal-summary", proposal.summary);
  setText("proposal-reason", proposal.reason);
  setText("operation", proposal.operation);
  setText("simulated-change", proposal.simulated_change);
  setText("host-impact", proposal.host_impact);
  setText(
    "rollback-artifact",
    `${proposal.rollback_artifact.artifact_id} · restore tested ${proposal.rollback_artifact.verified_at}`,
  );
  appendList("proposal-preconditions", proposal.preconditions);
  appendList("proposal-outputs", proposal.expected_outputs);
  appendList("proposal-stops", proposal.stop_conditions);
  appendList("proposal-verification", proposal.verification_plan);
  setText("proposal-id", proposal.proposal_id);
  setText("proposal-digest", proposal.proposal_digest);
  setText("target-digest", proposal.approval_fingerprint.target_digest);
  setText("fingerprint-digest", proposal.approval_fingerprint_digest);
}

function renderRecovery(workflow) {
  const card = document.getElementById("recovery-card");
  card.hidden = !workflow.stop_reason && !workflow.recovery_action;
  setText("stop-reason", workflow.stop_reason || "Operation stopped");
  setText("recovery-action", workflow.recovery_action || "No recovery action is required.");
}

function renderCase() {
  const caseRecord = state.case;
  if (!caseRecord) return;
  const evidence = caseRecord.evidence;
  const finding = caseRecord.findings[0];
  const proposal = caseRecord.proposal;
  const scenario = selectedScenario();

  renderScenarioRail();
  setText("case-label", `Case ${caseRecord.case_id.slice(0, 8)} · ${scenario?.label || evidence.title}`);
  setText("timeline-case", `Case ${caseRecord.case_id.slice(0, 8)}`);
  setText("diagnosis-title", evidence.title);
  renderEvidence(evidence);

  setText("finding-title", finding.title);
  setText("finding-summary", finding.summary);
  document.getElementById("finding-card").dataset.blocked = String(finding.blocks_writes);
  renderProposal(proposal);

  setText("workflow-target", exactTarget(evidence.target));
  setText("workflow-confidence", `${Math.round(finding.confidence * 100)}%`);
  setText("workflow-uncertainty", finding.uncertainty);
  setText("workflow-next-action", caseRecord.workflow.action?.hint || "No supported action.");
  setText("workflow-risk", proposal ? proposal.risk : "No action proposed");
  setText(
    "workflow-rollback",
    proposal ? `Restore-tested · ${proposal.rollback_artifact.content_digest}` : "Not applicable",
  );
  setText("workflow-approval", caseRecord.approval ? "Bound to complete proposal · one execution" : "Not approved");
  setText("workflow-execution", caseRecord.execution ? caseRecord.execution.message : "Not executed");
  setText("workflow-verification", caseRecord.verification ? caseRecord.verification.message : "Not verified");
  setText("workflow-last-safe", caseRecord.workflow.last_safe_state);
  setText("interlock-state", caseRecord.workflow.interlock);
  renderRecovery(caseRecord.workflow);
  renderAction(caseRecord);
  renderTimeline(caseRecord);

  const auditLink = document.getElementById("audit-link");
  auditLink.href = `/api/cases/${caseRecord.case_id}/audit`;
  auditLink.hidden = false;
}

async function transition(request) {
  state.pending = true;
  renderCase();
  try {
    hideError();
    state.case = await request();
  } catch (error) {
    showError(error);
  } finally {
    state.pending = false;
    renderCase();
  }
}

async function loadCase(scenarioId) {
  await transition(() => api("/api/cases", {
    method: "POST",
    body: JSON.stringify({ scenario_id: scenarioId }),
  }));
}

async function approveCase() {
  const proposal = state.case.proposal;
  await transition(() => api(`/api/cases/${state.case.case_id}/approve`, {
    method: "POST",
    body: JSON.stringify({ fingerprint: proposal.approval_fingerprint }),
  }));
}

async function executeCase() {
  await transition(() => api(`/api/cases/${state.case.case_id}/execute`, {
    method: "POST",
    body: "{}",
  }));
}

function showError(error) {
  const message = document.getElementById("error-message");
  message.textContent = error instanceof Error ? error.message : String(error);
  message.hidden = false;
}

function hideError() {
  document.getElementById("error-message").hidden = true;
}

async function start() {
  try {
    const payload = await api("/api/scenarios");
    state.categories = payload.categories;
    state.scenarios = payload.scenarios;
    renderScenarioRail();
    if (state.scenarios.length > 0) await loadCase(state.scenarios[0].id);
  } catch (error) {
    showError(error);
  }
}

start();
