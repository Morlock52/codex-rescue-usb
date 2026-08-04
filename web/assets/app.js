"use strict";

const state = { scenarios: [], case: null };

const scenarioOrder = ["boot-loop", "bitlocker-locked", "failing-drive"];

const descriptions = {
  "boot-loop": "Startup Repair repeats",
  "bitlocker-locked": "Locked volume detected",
  "failing-drive": "Drive health warning",
};

const labels = {
  "boot-loop": "Boot loop",
  "bitlocker-locked": "BitLocker",
  "failing-drive": "Storage",
};

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || `Request failed: ${response.status}`);
  return payload;
}

function shortDigest(value) {
  if (!value) return "—";
  return `${value.slice(0, 6)}…${value.slice(-4)}`;
}

function setText(id, value) {
  document.getElementById(id).textContent = value;
}

function renderScenarioRail() {
  const list = document.getElementById("scenario-list");
  list.replaceChildren();
  for (const scenario of state.scenarios) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "scenario-button";
    button.dataset.scenarioId = scenario.id;
    button.setAttribute("aria-current", String(state.case?.evidence.scenario_id === scenario.id));
    const title = document.createElement("strong");
    title.textContent = labels[scenario.id] || scenario.title;
    const detail = document.createElement("span");
    detail.textContent = descriptions[scenario.id] || scenario.category;
    button.append(title, detail);
    button.addEventListener("click", () => loadCase(scenario.id));
    list.appendChild(button);
  }
  setText("fixture-count", `${state.scenarios.length} offline fixtures available`);
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

function timelineState(stage, step) {
  const order = ["loaded", "diagnosed", "approved", "verified"];
  const stageIndex = { proposed: 1, blocked: 1, approved: 2, verified: 3, failed: 3 }[stage] ?? 0;
  const index = order.indexOf(step);
  if (index < stageIndex || (stage === "verified" && index === stageIndex)) return "complete";
  if (index === stageIndex) return "current";
  return "pending";
}

function renderTimeline(caseRecord) {
  const steps = [
    ["loaded", "Fixture loaded"],
    ["diagnosed", "Diagnosis"],
    ["approved", "Approval"],
    ["verified", "Receipt"],
  ];
  const timeline = document.getElementById("timeline");
  timeline.replaceChildren();
  steps.forEach(([key, label], index) => {
    const item = document.createElement("li");
    const itemState = timelineState(caseRecord.stage, key);
    item.dataset.state = itemState;
    const number = document.createElement("span");
    number.className = "step-number";
    number.textContent = String(index + 1);
    const copy = document.createElement("span");
    copy.textContent = label;
    const status = document.createElement("small");
    status.className = "step-state";
    status.textContent = itemState;
    copy.appendChild(status);
    item.append(number, copy);
    timeline.appendChild(item);
  });
}

function renderAction(caseRecord) {
  const button = document.getElementById("action-button");
  const hint = document.getElementById("action-hint");
  button.disabled = true;
  button.onclick = null;

  if (caseRecord.stage === "proposed") {
    button.disabled = false;
    button.textContent = "Approve simulated repair";
    hint.textContent = "Approves this proposal and exact target digest.";
    button.onclick = approveCase;
  } else if (caseRecord.stage === "approved") {
    button.disabled = false;
    button.textContent = "Run safe simulation";
    hint.textContent = "Creates a receipt. Makes no system change.";
    button.onclick = executeCase;
  } else if (caseRecord.stage === "verified") {
    button.textContent = "Simulation verified";
    hint.textContent = caseRecord.verification.message;
  } else if (caseRecord.stage === "blocked") {
    button.textContent = "Repair blocked";
    hint.textContent = "Resolve the safety blocker outside this fixture prototype.";
  } else {
    button.textContent = "No action available";
    hint.textContent = "This diagnosis has no supported simulated repair.";
  }
}

function renderCase() {
  const caseRecord = state.case;
  if (!caseRecord) return;
  const evidence = caseRecord.evidence;
  const finding = caseRecord.findings[0];
  const proposal = caseRecord.proposal;

  renderScenarioRail();
  setText("case-label", `Case ${caseRecord.case_id.slice(0, 8)} · ${labels[evidence.scenario_id]}`);
  setText("timeline-case", `Case ${caseRecord.case_id.slice(0, 8)}`);
  setText("diagnosis-title", evidence.title);
  renderEvidence(evidence);

  setText("finding-title", finding.title);
  setText("finding-summary", finding.summary);
  document.getElementById("finding-card").dataset.blocked = String(finding.blocks_writes);

  const proposalCard = document.getElementById("proposal-card");
  proposalCard.hidden = !proposal;
  if (proposal) {
    setText("proposal-title", "Simulate rebuilding Windows boot configuration");
    setText("proposal-summary", proposal.summary);
    setText("operation", proposal.operation);
    setText("proposal-digest", shortDigest(proposal.proposal_id));
    setText("target-digest", shortDigest(proposal.target_digest));
  } else {
    setText("proposal-digest", "—");
    setText("target-digest", "—");
  }

  const interlock = caseRecord.stage === "blocked" ? "Blocked" : caseRecord.stage === "verified" ? "Verified" : "Simulation armed";
  setText("interlock-state", interlock);
  renderAction(caseRecord);
  renderTimeline(caseRecord);
}

async function loadCase(scenarioId) {
  try {
    hideError();
    state.case = await api("/api/cases", {
      method: "POST",
      body: JSON.stringify({ scenario_id: scenarioId }),
    });
    renderCase();
  } catch (error) {
    showError(error);
  }
}

async function approveCase() {
  try {
    hideError();
    const proposal = state.case.proposal;
    state.case = await api(`/api/cases/${state.case.case_id}/approve`, {
      method: "POST",
      body: JSON.stringify({
        proposal_id: proposal.proposal_id,
        target_digest: proposal.target_digest,
      }),
    });
    renderCase();
  } catch (error) {
    showError(error);
  }
}

async function executeCase() {
  try {
    hideError();
    state.case = await api(`/api/cases/${state.case.case_id}/execute`, {
      method: "POST",
      body: "{}",
    });
    renderCase();
  } catch (error) {
    showError(error);
  }
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
    state.scenarios = payload.scenarios.sort(
      (left, right) => scenarioOrder.indexOf(left.id) - scenarioOrder.indexOf(right.id),
    );
    renderScenarioRail();
    await loadCase("boot-loop");
  } catch (error) {
    showError(error);
  }
}

start();
