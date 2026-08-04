# Codex Rescue USB

Codex Rescue USB is a safety-first prototype for a future offline PC recovery environment. This milestone is a host-runnable Rescue Console that diagnoses strictly validated fixtures, creates complete repair proposals, binds approval to the full proposal and exact target, simulates one allowlisted repair, and verifies the result against separate post-action evidence.

> **Fixture-only:** This repository cannot repair a PC. It does not mount, unlock, write, format, or execute host commands. It does not contact Codex or any other model. Never enter a BitLocker recovery key, password, token, or credential into this prototype.

## Run the console

Python 3.11 or newer is required. No third-party packages or network connection are needed.

```sh
PYTHONPATH=src python3 -m codex_rescue --port 8080
```

Open `http://127.0.0.1:8080`. The server always binds to loopback. Hash-chained audit records are written with restricted permissions under `~/.codex-rescue/cases` by default; use `--case-dir PATH` to choose a separate directory.

The console presents the complete recovery taxonomy and marks workflows that are planned but unavailable. Three bundled fixtures are currently executable as demonstrations:

- a boot-loop fixture with an approvable BCD rebuild simulation;
- a locked BitLocker fixture that blocks repair without accepting recovery material;
- a failing-drive fixture that blocks ordinary repair and preserves read-only evidence.

## Safety contract

- Fixture IDs are resolved through a validated index; traversal and malformed or secret-bearing fixture data are rejected.
- Storage health, finding severity, operations, risk, BitLocker state, and case stages use bounded enums.
- The operation registry owns proposal creation, policy, execution, and verification for each allowlisted operation.
- Every proposal states its reason, inputs, preconditions, simulated change, zero-host-impact boundary, expected outputs, stop conditions, verification plan, and verified rollback artifact.
- Approval contains the proposal ID, complete proposal digest, and exact target digest. Any proposal or target change invalidates it.
- The safety broker scans proposal content for recovery passwords and other secret material without relying on a caller-provided flag.
- Execution produces a typed, digest-verifiable simulation receipt. Verification loads separate post-action fixture evidence rather than trusting the receipt alone.
- Case events are timestamped, hash chained, persisted as JSONL, and available from `/api/cases/{case_id}/audit`.
- Blocked and failed cases expose a stop reason, last safe state, and non-automatic recovery guidance.

These guarantees apply only to the fixture prototype. The future bootable USB architecture and every real disk or BitLocker operation remain separate, gated milestones.

## Test

```sh
python3 -W error::ResourceWarning -m unittest discover -s tests -v
node --check web/assets/app.js
python3 -m compileall -q src tests
git diff --check
```

## Project references

- [Product and safety design](docs/plans/2026-08-04-codex-rescue-usb-design.md)
- [Fixture console implementation plan](docs/plans/2026-08-04-fixture-rescue-console-implementation.md)
- [Editable Figma Rescue Console](https://www.figma.com/design/sW9ctJbQnpgzx0DqJqwnbo)
