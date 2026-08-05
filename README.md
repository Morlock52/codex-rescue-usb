# Codex Rescue USB

> A safety-first recovery project with a fixture console and a VM-verified Windows PE evidence ISO.

Codex Rescue USB contains two deliberately separate deliverables: a host-runnable fixture console that demonstrates the approval model without touching a real PC, and a Windows PE image that has booted in a disposable UEFI VM and exported read-only troubleshooting evidence to a prepared test destination.

The verified Windows PE milestone is real VM evidence, but it is not yet proof of physical USB compatibility, BitLocker unlock, real repair, or a full-Windows Codex GUI/voice workspace. Those claims remain gated until their own tests exist.

## Verified WinPE milestone

On August 5, 2026, the current source was built with the serviced Windows ADK and booted in a separate disposable Proxmox UEFI VM using Windows UEFI CA 2023 keys. The exact tested artifact is:

| Property | Verified value |
| --- | --- |
| Artifact | `Codex-Rescue-ISO-v0.1.0-alpha.4.iso` |
| Size | 557,518,848 bytes |
| SHA-256 | `F7F6E3570F0DBF264D56CAAF8703C6FB6EAD99ABB53FDC420D9B4737C9584DFA` |
| Test VM | 2 vCPU, 2 GB RAM, UEFI, Secure Boot keys, empty disposable disks |
| Build VM | 4 vCPU, 8 GB RAM, Windows 11, ADK 10.1.26100.2454 plus KB5101684 |

The test verified all of the following:

- UEFI recognized the ISO as bootable media and WinPE reached the Codex Rescue command prompt.
- The startup banner accurately described the read-only default and recovery-key boundary.
- Export stopped without writing when no prepared destination existed.
- Export refused to overwrite an existing `CodexRescueEvidence` directory.
- With exactly one prepared test destination, export produced the expected evidence package.
- The image's supported WinPE PowerShell components generated `manifest.json` and `SHA256SUMS.txt` after revalidating the prepared destination.
- A separate Proxmox-side read-only mount verified all nine package files, all eight listed hashes, the seven-entry manifest schema, and the successful DISM driver inventory.

This milestone does **not** prove physical USB boot, authorized BitLocker unlock, repair of a real Windows installation, or a supported Codex desktop/voice workspace in recovery Windows. Those remain separately gated phases.

### Real VM-boot screenshot

![Codex Rescue Disk booted in a disposable Proxmox UEFI VM](docs/images/winpe-proxmox-boot.png)

Captured from the exact alpha.4 SHA-256 artifact above. This is real Proxmox VM evidence, not a Figma concept or fixture-console image.

### Real no-overwrite screenshot

![Codex Rescue evidence collector refusing to overwrite an existing package](docs/images/winpe-evidence-no-overwrite.png)

The final ISO found the prepared test destination and stopped because a prior package already existed.

### Real evidence-export screenshot

![Codex Rescue evidence collector completing export in the disposable VM](docs/images/winpe-evidence-export.png)

After only the disposable prior package was removed, the same final ISO exported a fresh package to the prepared test destination.

### Artifact availability and Microsoft licensing

The repository and GitHub pre-release publish the original Codex Rescue source, reproducible build instructions, screenshots, verified artifact size, and SHA-256—not the Microsoft-built ISO binary. The Windows ADK license installed on the verified build VM permits using WinPE to install and recover Windows, but prohibits publishing the Microsoft software for others to copy. Build the ISO locally from a properly licensed ADK installation and verify the resulting artifact in a disposable VM. The exact alpha.4 ISO identified above is retained privately on the Proxmox host for controlled validation.

## Building the bootable ISO (Windows build VM)

The checked-in source includes the first WinPE ISO build assets. Build it on a Windows 11 x64 VM or workstation with:

- Windows ADK **Deployment Tools**;
- the matching Windows PE add-on; and
- the current Microsoft ADK servicing patch for that ADK release.

The build script adds Microsoft's WinPE-WMI, WinPE-NetFx, WinPE-Scripting, and WinPE-PowerShell optional components in their documented dependency order. Those components provide the supported local hashing path used for the evidence manifest; no third-party executable is embedded.

Microsoft currently lists ADK 10.1.26100.2454 for general x64 Windows 10/11 recovery work and requires that release to be serviced with KB5079391 or later. The verified build used KB5101684. Check the [current ADK download page](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) and [ADK servicing updates](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-servicing) immediately before building; the update named in this repository was current on August 5, 2026.

The helper below downloads only from Microsoft-owned hosts, rejects an MSP unless Windows reports a valid Microsoft Authenticode signature, installs applicable patches, and records package hashes and installer results under `C:\CodexRescueVmAudit\ADK-Servicing`:

```powershell
.\scripts\Install-AdkServicingUpdate.ps1 -Confirm:$false
```

Then run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Build-RescueIso.ps1 -Force
```

For the same build with a visible completion prompt, double-click `scripts\Build-RescueIso.cmd`.

For Proxmox guest-agent automation, run `scripts\Build-RescueIso-Unattended.cmd`. It writes the complete console output and numeric exit code into `dist` so a timed-out management session does not lose the build result.

### Staging source from a Proxmox virtual CD

When the repository is mounted in the build VM as a read-only virtual CD, open the CD in File Explorer and double-click `scripts\Stage-RescueSource.cmd`. It creates `Documents\CodexRescue` and copies the source there without changing the CD. If that destination already exists, the launcher stops without overwriting it. Open PowerShell in the staged folder and run the build command above.

This produces `dist\Codex-Rescue-ISO.iso` using Microsoft's `/bootex` option and Windows UEFI CA 2023-signed boot files. Attach that ISO to a separate Proxmox test VM and verify it reaches the WinPE command prompt before using physical hardware. The build VM is not the test VM. A legacy Windows UEFI 2011 CA build is a separate compatibility choice and must be matched to the target device's Secure Boot revocation state.

### Repairing and auditing the Proxmox build VM

The repository includes `scripts\Repair-BuildVm.cmd` for the dedicated Windows build VM. Run it from the mounted source disc or a staged source folder. It requests administrator approval, installs or starts the QEMU Guest Agent from an attached VirtIO tools disc, sets that service to automatic startup, and writes a non-secret inventory to `C:\CodexRescueVmAudit`.

The audit records Windows and build versions, CPU and memory capacity, free system-drive space, page-file use, ADK command availability, relevant installed software, and whether common development commands are discoverable. It explicitly checks `codex`, `roc`, and `rock` command names without assuming which similarly named CLI the operator intended. It does not collect passwords, BitLocker recovery material, tokens, user documents, or browser data.

After the audit, install the supported repository-maintenance baseline from the signed WinGet sources:

```powershell
.\scripts\Install-BuildVmToolchain.ps1 -Confirm:$false
```

This installs or updates Git, GitHub CLI, PowerShell 7, and Python 3.14, then records command discovery under `C:\CodexRescueVmAudit\Toolchain`. It does not reinstall Node.js, VS Code, Cursor, or Codex when they are already present. The audit reports `roc` and `rock` but the installer deliberately does not guess which similarly named product an operator means.

The validated Proxmox build VM uses four logical processors and 8 GB assigned RAM. The fresh Windows audit reported 7.93 GiB visible, 2.42 GiB free immediately after the serviced ISO build, 21.54 GiB free on the system drive, QEMU Guest Agent running with automatic startup, and all ADK build commands present. Eight GB is the recommended baseline for running the ADK, editors, and Codex together; the earlier 6 GB assignment was saturated. Use 12 GB only when the Proxmox host has comfortable headroom. Reserve about 30 GB of free system-drive space for repeated workspaces, logs, and versioned ISOs.

| Validated build tool | Version or state |
| --- | --- |
| Windows ADK + WinPE add-on | 10.1.26100.2454, serviced with KB5101684 |
| Git | 2.55.0.windows.3 |
| GitHub CLI | 2.97.0 |
| PowerShell | 7.6.4 |
| Python | 3.14.6 |
| Node.js | 24.17.0 |
| Codex CLI | 0.142.0 |
| VS Code and Cursor | Present and command-discoverable |

![Verified Proxmox build VM capacity, toolchain, artifact, and evidence status](docs/images/build-vm-verified-audit.png)

This cropped, redacted console view was generated from the fresh machine audit after alpha.4 completed. It deliberately omits unrelated desktop content and keeps each unverified phase labeled **OPEN**.

To make a physical USB after VM verification, use a dedicated USB-writing tool on a separate Windows machine. Select the verified ISO, confirm the exact removable drive, and write it. This overwrites that USB. The image contains no recovery keys and starts in read-only evidence-collection mode. Evidence export requires exactly one separate operator-prepared destination whose root contains an empty `CODEX_EVIDENCE.DEST` marker file. It never scans the internal `C:` volume or WinPE's `X:` RAM drive, refuses zero or multiple prepared destinations, and refuses an existing `CodexRescueEvidence` directory; it never silently overwrites an earlier package.

### Preparing the separate evidence destination

Use a second removable drive for evidence; do not use the bootable rescue drive. In normal Windows, first inspect the intended drive. Replace `E` only after confirming the displayed capacity, label, and drive type match the physical evidence drive:

```powershell
Get-Volume -DriveLetter E | Format-List DriveLetter, FileSystemLabel, DriveType, Size, SizeRemaining
```

Create the marker without formatting or deleting anything:

```powershell
New-Item -ItemType File -Path 'E:\CODEX_EVIDENCE.DEST' -Force
```

Boot Codex Rescue Disk and run:

```bat
X:\Rescue\Collect-RescueEvidence.cmd
```

The collector searches drive letters `D:` through `W:` plus `Y:` and `Z:`. It intentionally excludes a normal internal `C:` volume and WinPE's `X:` RAM drive. Exactly one scanned drive must contain the marker.

The resulting `CodexRescueEvidence` directory contains:

| File | Purpose |
| --- | --- |
| `README.txt` | Collection mode and chosen destination |
| `diskpart.txt` | Disk and volume inventory |
| `bitlocker-status.txt` | Read-only `manage-bde -status` output |
| `bcd.txt` | Current BCD enumeration output |
| `event-log-index.txt` | Event-log names visible to WinPE |
| `drivers.txt` | DISM third-party driver-store inventory |
| `network.txt` | Current network-interface configuration |
| `manifest.json` | UTC collection time, schema version, sizes, and SHA-256 hashes for the seven diagnostic files |
| `SHA256SUMS.txt` | SHA-256 verification list for the seven diagnostic files plus `manifest.json` |

The package may contain device identifiers, network addresses, and machine-specific troubleshooting data. Review and redact it before sharing or publishing. It never intentionally collects BitLocker recovery keys, passwords, browser data, or user documents.

![Boot-loop diagnosis and proposed simulated repair](docs/images/rescue-console-overview.jpg)

## Fixture console features

- Runs locally on `127.0.0.1` with no network dependency.
- Diagnoses a boot loop, locked BitLocker volume, or failing drive fixture.
- Requires approval bound to the complete repair proposal and exact target.
- Simulates an allowlisted BCD reconstruction with zero host impact.
- Verifies separate post-action fixture evidence.
- Saves timestamped, hash-chained local audit records.

## Safety boundaries

- Checked-in Windows PE source alone is not boot evidence. The verified milestone above identifies the exact VM-tested artifact and hash; every later build requires its own separate boot test.
- The fixture console never touches a real disk, volume, boot file, or host command.
- A booted WinPE image can query the machine it was booted on for disk layout, BitLocker status, boot configuration, event-log names, driver inventory, and network state. Its checked-in evidence command does not unlock, repair, or write to those system components.
- The fixture console never requests BitLocker keys, passwords, tokens, or credentials. The future real recovery flow must keep any owner-entered recovery key local and out of logs and Codex context.
- The fixture console contacts no Codex, model, or network service. The WinPE evidence script reports network configuration only; it does not enable or use a network connection.

Do not use this pre-release image on production or customer hardware. Use disposable test systems until the physical-USB, BitLocker, repair, and full-Windows workspace gates are independently verified.

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

The two screenshots in the fixture-console sections show the **fixture console** only. The verified sections contain one real build-VM audit screenshot and three real disposable-VM screenshots. None proves that a physical PC was recovered. Each image is labeled by its evidence boundary.

| Screenshot | What it must show | Evidence status required |
| --- | --- | --- |
| Build prerequisites | Windows ADK Deployment Tools, matching WinPE add-on, and servicing patch selected on the build VM. | **Verified by the build-VM audit above** |
| ISO build completion | The completed build output and generated ISO file. | Artifact and hash verified; screenshot pending |
| Proxmox test VM | A separate test VM configured to boot the generated ISO. | Configuration verified; screenshot pending |
| WinPE first boot | The Codex Rescue Disk read-only startup banner at the WinPE command prompt. | **Verified above** |
| Storage and BitLocker inventory | Read-only status output from a disposable test VM. | Output verified; publishable redacted screenshot pending |
| Evidence no-overwrite gate | Refusal to replace a prior `CodexRescueEvidence` package. | **Verified above** |
| Evidence package | The resulting `CodexRescueEvidence` folder on the prepared test destination. | Export verified above; folder screenshot pending |
| Codex recovery workspace | The full Windows GUI and voice workspace, visibly labeled as a later staged environment. | Pending |
| Physical USB boot | UEFI boot and evidence collection on a disposable physical test machine. | Pending |

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

This release proves the fixture safety model and a VM-boot-verified, read-only WinPE evidence path. The verified ISO can boot a disposable UEFI VM, enforce its prepared-destination and no-overwrite gates, and export the nine-file package documented above. It is not yet a physical USB-validated recovery disk, an authorized BitLocker unlock tool, a repair engine for a real Windows installation, or a full Windows Codex workspace. Those stages require separate hardware fixtures, threat modeling, and explicit approval for every real disk or encryption operation.

## Planned real recovery USB

The next build is designed as a two-stage Windows recovery medium:

1. **Windows PE recovery stage:** boots a PC, inventories storage and BitLocker state, collects read-only troubleshooting evidence, and hands an owner-entered recovery key to the local Windows BitLocker recovery flow without retaining the key.
2. **Full Windows recovery workspace:** starts only when the operator selects it, then provides the supported Codex desktop GUI and voice experience for guided diagnosis and reviewed repair.

Planned safeguards include an offline-by-default recovery workspace, explicit network enablement for Codex, no recovery-key logging or storage, target-specific confirmation before any write, rollback requirements, and independent post-action verification.

The two-stage architecture is planned beyond the verified read-only WinPE milestone. A physical USB and disposable hardware machine are still required for hardware validation.

## Recovery-media delivery roadmap

The detailed phase plan, acceptance evidence, safety gates, and planned Figma screens are in [the recovery-media roadmap](docs/plans/2026-08-05-recovery-media-roadmap.md). Phases 1 and 2 are VM-verified. Physical USB, BitLocker, repair, and Codex workspace gates remain open.

## References

- [Product and safety design](docs/plans/2026-08-04-codex-rescue-usb-design.md)
- [Fixture console implementation plan](docs/plans/2026-08-04-fixture-rescue-console-implementation.md)
- [Windows PE and Codex recovery architecture](docs/plans/windows-pe-codex-recovery-architecture.md)
- [Recovery-media delivery roadmap](docs/plans/2026-08-05-recovery-media-roadmap.md)
- [Editable Figma Rescue Console](https://www.figma.com/design/sW9ctJbQnpgzx0DqJqwnbo)
