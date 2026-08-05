# Codex Rescue USB

> A safety-first recovery project with a fixture console and a Windows PE ISO build path.

Codex Rescue USB is a host-runnable prototype for a future offline recovery environment. It diagnoses strictly validated demonstration fixtures, creates complete repair proposals, binds approval to the exact proposal and target, simulates one allowlisted repair, and verifies the result with separate post-action evidence.

The current milestone includes a local fixture console plus a Windows PE ISO build path. The fixture console does not touch a real PC. The ISO must be built and boot-tested in a VM before it is described as a usable recovery image or written to physical media.

## Building the bootable ISO (Windows build VM)

The checked-in source includes the first WinPE ISO build assets. Build it on a Windows 11 x64 VM or workstation with:

- Windows ADK **Deployment Tools**;
- the matching Windows PE add-on; and
- the current Microsoft ADK servicing patch for that ADK release.

Then run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Build-RescueIso.ps1 -Force
```

### Staging source from a Proxmox virtual CD

When the repository is mounted in the build VM as a read-only virtual CD, open the CD in File Explorer and double-click `scripts\Stage-RescueSource.cmd`. It creates `Documents\CodexRescue` and copies the source there without changing the CD. If that destination already exists, the launcher stops without overwriting it. Open PowerShell in the staged folder and run the build command above.

This produces `dist\Codex-Rescue-ISO.iso`. Attach that ISO to a separate Proxmox test VM and verify it reaches the WinPE command prompt before using physical hardware. The build VM is not the test VM.

To make a physical USB after VM verification, use a dedicated USB-writing tool on a separate Windows machine. Select the verified ISO, confirm the exact removable drive, and write it. This overwrites that USB. The image contains no recovery keys and starts in read-only evidence-collection mode. Evidence collection asks the operator to select a removable destination drive and then writes only to `CodexRescueEvidence` on that selected drive.

![Boot-loop diagnosis and proposed simulated repair](docs/images/rescue-console-overview.jpg)

## Fixture console features

- Runs locally on `127.0.0.1` with no network dependency.
- Diagnoses a boot loop, locked BitLocker volume, or failing drive fixture.
- Requires approval bound to the complete repair proposal and exact target.
- Simulates an allowlisted BCD reconstruction with zero host impact.
- Verifies separate post-action fixture evidence.
- Saves timestamped, hash-chained local audit records.

## Safety boundaries

- The Windows PE build assets are not proof that the ISO has booted; separate VM verification is required.
- The fixture console never touches a real disk, volume, boot file, or host command.
- A booted WinPE image can query the machine it was booted on for disk layout, BitLocker status, boot configuration, event-log names, driver inventory, and network state. Its checked-in evidence command does not unlock, repair, or write to those system components.
- The fixture console never requests BitLocker keys, passwords, tokens, or credentials. The future real recovery flow must keep any owner-entered recovery key local and out of logs and Codex context.
- The fixture console contacts no Codex, model, or network service. The WinPE evidence script reports network configuration only; it does not enable or use a network connection.

Do not use this prototype as a real recovery tool.

## Fixture console requirements

- Python 3.11 or newer
- A modern browser
- No third-party packages

## Install

```sh
git clone https://github.com/Morlock52/codex-rescue-usb.git
cd codex-rescue-usb
```

No package installation is needed; the console uses the Python standard library.

## Run

```sh
PYTHONPATH=src python3 -m codex_rescue --port 8080
```

Open [http://127.0.0.1:8080](http://127.0.0.1:8080). The service always binds to loopback, so it is not exposed to the local network.

Audit records are written to `~/.codex-rescue/cases` by default. Choose a different local directory when needed:

```sh
PYTHONPATH=src python3 -m codex_rescue --port 8080 --case-dir ./local-cases
```

Stop the server with `Ctrl+C`.

## Use the console

1. Start the server and open the local address.
2. Review the default **Boot loop** case or select **BitLocker locked** or **Failing drive**.
3. Inspect the evidence, likely cause, proposal, workflow facts, and safety boundary.
4. For the boot-loop fixture, review the simulated BCD reconstruction and rollback artifact.
5. Select **Approve exact simulated plan** after reviewing the proposal and target fingerprints.
6. Select **Run safe simulation**. This affects fixture state only.
7. Confirm independent verification, then open the hash-chained audit record if desired.

The BitLocker and failing-drive cases are expected safe stops: they intentionally do not offer an executable action.

![Approved one-time simulated repair plan](docs/images/rescue-console-approved.jpg)

## Documentation screenshots and evidence

The two screenshots above show the **fixture console** only. They do not prove that an ISO booted or that a physical PC was recovered. As each real-media phase is verified, the README will add a labeled screenshot for the following evidence:

| Screenshot | What it must show | Evidence status required |
| --- | --- | --- |
| Build prerequisites | Windows ADK Deployment Tools, matching WinPE add-on, and servicing patch selected on the build VM. | Build-host verification |
| ISO build completion | The completed build output and generated ISO file. | Build artifact verification |
| Proxmox test VM | A separate test VM configured to boot the generated ISO. | VM configuration verification |
| WinPE first boot | The Codex Rescue Disk read-only startup banner at the WinPE command prompt. | VM-boot verification |
| Storage and BitLocker inventory | Read-only status output from a disposable test VM. | Test-fixture evidence only |
| Evidence destination prompt | The operator selecting a removable destination drive. | Workflow verification |
| Evidence package | The resulting `CodexRescueEvidence` folder on that selected removable drive. | Export verification |
| Codex recovery workspace | The full Windows GUI and voice workspace, visibly labeled as a later staged environment. | Workspace verification |
| Physical USB boot | UEFI boot and evidence collection on a disposable physical test machine. | Hardware verification |

Every screenshot will state what was tested, which environment produced it, and whether it is a fixture, VM, or physical-hardware result. Screens that could expose recovery keys, device identifiers, account data, or customer files are redacted before publication.

## Feature guide

### Problem categories and fixtures

Use the left-side **Problem categories** panel to select a bundled fixture. The interface labels each category as available or planned. Available fixtures load only validated local data; planned categories intentionally cannot run an action in this milestone.

### Read-only diagnosis

The center panel reports the selected fixture's observed evidence, likely cause, proposed repair when one is safe, and workflow facts. Treat this panel as a demonstration of the decision model, not evidence about a physical computer.

### Safety Interlock

The right-side **Safety Interlock** shows the immutable boundaries, proposal digest, target digest, and one-time approval state. Read the proposed operation, target, rollback status, and expected evidence before approving anything. A proposal or target change invalidates its approval.

### Simulated BCD recovery

The boot-loop fixture is the only workflow that can proceed. Select **Approve exact simulated plan**, then select **Run safe simulation**. This updates only fixture state and produces a typed receipt; it never changes a host disk or boot configuration.

### BitLocker safe stop

Select **BitLocker locked** to review the blocked condition. The console deliberately does not ask for or accept a recovery key. This demonstrates that encrypted media remains protected until an owner uses an approved recovery environment.

### Failing-drive safe stop

Select **Failing drive** to see storage-health evidence take precedence over ordinary repair. The console blocks writes and retains read-only evidence, modeling the correct response to a possible hardware failure.

### Audit records

Use **Open hash-chained audit record** after loading a case. The audit record shows the timestamped case history. It is stored locally in the case directory; review it when checking what the fixture workflow did and what it intentionally did not do.

## Demonstration fixtures

| Fixture | Purpose | Action available |
| --- | --- | --- |
| Boot loop | Diagnosis, approval, simulated BCD rebuild, and independent verification. | Simulation only |
| BitLocker locked | Blocked workflow without accepting recovery material. | No |
| Failing drive | Protected stop for storage-health risk. | No |

## Safety model

Each executable workflow validates fixture and rollback evidence, builds a complete proposal, binds one approval to its proposal and target digests, runs the allowlisted simulation once, and then checks independent post-action evidence. The safety broker rejects malformed, secret-bearing, mismatched, ambiguous, unapproved, or unsupported operations.

## Test

```sh
python3 -W error::ResourceWarning -m unittest discover -s tests -v
node --check web/assets/app.js
python3 -m compileall -q src tests
git diff --check
```

## Project layout

```text
src/codex_rescue/  Service, safety broker, fixture handling, and simulation
web/               Static browser console
fixtures/          Demonstration cases plus rollback and post-action evidence
tests/             Unit and HTTP integration tests
```

## Current scope

This release proves the safety and workflow model with deterministic fixtures and supplies an unverified WinPE ISO build path. It is not yet a VM-boot-verified recovery image, a physical USB recovery disk, or a full Windows Codex workspace. Those later stages require threat modeling, separate VM and hardware testing, and explicit approval for every real disk or encryption operation.

## Planned real recovery USB

The next build is designed as a two-stage Windows recovery medium:

1. **Windows PE recovery stage:** boots a PC, inventories storage and BitLocker state, collects read-only troubleshooting evidence, and hands an owner-entered recovery key to the local Windows BitLocker recovery flow without retaining the key.
2. **Full Windows recovery workspace:** starts only when the operator selects it, then provides the supported Codex desktop GUI and voice experience for guided diagnosis and reviewed repair.

Planned safeguards include an offline-by-default recovery workspace, explicit network enablement for Codex, no recovery-key logging or storage, target-specific confirmation before any write, rollback requirements, and independent post-action verification.

These are planned capabilities, not features of the current fixture console. The build requires a Windows ADK host and a disposable USB drive for hardware validation.

## Recovery-media delivery roadmap

The detailed phase plan, acceptance evidence, safety gates, and planned Figma screens are in [the recovery-media roadmap](docs/plans/2026-08-05-recovery-media-roadmap.md). No phase is presented as complete until its listed evidence is captured and reviewed.

## References

- [Product and safety design](docs/plans/2026-08-04-codex-rescue-usb-design.md)
- [Fixture console implementation plan](docs/plans/2026-08-04-fixture-rescue-console-implementation.md)
- [Windows PE and Codex recovery architecture](docs/plans/windows-pe-codex-recovery-architecture.md)
- [Recovery-media delivery roadmap](docs/plans/2026-08-05-recovery-media-roadmap.md)
- [Editable Figma Rescue Console](https://www.figma.com/design/sW9ctJbQnpgzx0DqJqwnbo)
