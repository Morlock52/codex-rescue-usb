# Fixture Rescue Console Implementation Plan

Date: 2026-08-04

## Objective

Build the first host-runnable Codex Rescue USB milestone without real disk access. The prototype must demonstrate the safety contract using bundled fixture evidence, deterministic offline diagnostics, structured repair proposals, explicit approval, a simulated runner, and independent verification.

## Constraints

- No shelling out to disk, filesystem, boot, BitLocker, or Windows repair tools.
- No privileged operations.
- No OpenAI credentials or network calls.
- No arbitrary commands in repair proposals.
- Python standard library only for the backend and tests.
- Vanilla HTML, CSS, and JavaScript for the local Rescue Console.
- Every state-changing workflow is simulated and covered by tests.

## Deliverables

1. Python package with immutable domain models for evidence, targets, findings, proposals, approvals, execution results, and case state.
2. Deterministic offline diagnostic engine for:
   - damaged boot configuration fixture
   - locked BitLocker fixture
   - failing-drive fixture
3. Safety Broker that rejects:
   - unknown operations
   - ambiguous or mismatched targets
   - unapproved actions
   - missing rollback prerequisites
   - attempts to include secrets
4. Simulated Repair Runner with independent post-action verification.
5. Local HTTP server exposing fixture-only JSON endpoints and static UI assets.
6. Rescue Console UI with problem categories, evidence, findings, repair proposal, approval, simulated execution, and verification state.
7. Unit and HTTP integration tests.
8. README with run and test instructions and an explicit fixture-only warning.

## Test-first sequence

1. Write domain and Safety Broker tests; confirm failure.
2. Implement the minimum domain and policy code required to pass.
3. Write diagnostic rule tests; confirm failure.
4. Implement deterministic diagnostics.
5. Write simulated execution and verification tests; confirm failure.
6. Implement the simulated runner and case workflow.
7. Write HTTP endpoint tests; confirm failure.
8. Implement the local server.
9. Implement the UI against the tested endpoints.
10. Run unit tests, integration tests, compile checks, JavaScript syntax checks, and a manual local smoke test.

## Success criteria

- `python3 -m unittest discover -s tests -v` passes.
- The server binds to loopback only by default.
- The UI can load each fixture and display a deterministic finding.
- A proposal cannot execute before approval.
- A target mismatch is blocked.
- BitLocker recovery material is neither accepted nor represented by the fixture API.
- The failing-drive case blocks ordinary repair and recommends imaging to separate storage.
- The prototype contains no real repair command runner.
