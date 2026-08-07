# Codex Rescue Orchestrator operator guide

This guide is the full operating runbook for the Enterprise Technical Preview. The [README](../../README.md) is the product overview and quick reference; this document focuses on repeatable preparation, execution, expected results, and failure handling.

## 1. Before you begin

### Audience

- Enterprise desktop support technicians
- MSP escalation engineers
- Field recovery engineers
- Windows deployment and endpoint-management specialists

The destructive workflows are not intended for an unsupervised end user. A technician needs authority over the device and data, a separate backup destination, and disposable lab hardware before using Apply.

### Workstation recommendation

Use a dedicated Windows 11 x64 build VM or workstation with:

- 4 or more vCPU;
- 12 GB fixed RAM recommended, 8 GB minimum for build-only validation;
- 60 GB free system-drive space recommended for two ADKs, working images, build outputs, symbols, and N-1 packages;
- .NET 8 SDK for source builds;
- current Windows SDK/MakeAppx for packaging;
- the exact ADK and matching WinPE add-on for the selected architecture;
- PowerShell 7 for development and Windows PowerShell 5.1 for signed broker execution; and
- an operator-controlled evidence drive separate from every repair target.

Do not configure automatic logon. Do not put recovery keys, API tokens, tenant exports, customer files, or raw evidence in the repository or golden VM image.

### Roles and approvals

| Role | Responsibility |
| --- | --- |
| Operator | Reviews targets, agreements, plan, confirmation phrase, and receipt |
| Administrator | Defines credential-storage and telemetry policies; grants local elevation |
| Release owner | Controls protected tags, Azure signing identity, and release evidence |
| Device/data owner | Authorizes access, unlock, salvage, overwrite, and evidence handling |

One person may hold multiple roles in a lab. The receipts still record the separate decisions.

## 2. Install or run from source

### Signed package

Use the signed package only when the release includes an App Installer file, signed MSIX bundle, detached signed manifest, hashes, SBOM, rollback metadata, and provenance. Download the `.appinstaller` file and double-click it. Confirm the publisher before selecting Install.

If the package is absent, a certificate is untrusted, the publisher differs, or a hash does not match, stop. Do not import a self-signed certificate into an enterprise endpoint as a convenience workaround.

### Source build

```powershell
git clone https://github.com/Morlock52/codex-rescue-usb.git
Set-Location .\codex-rescue-usb
git status --short --branch
git log -1 --oneline

dotnet restore .\orchestrator\CodexRescue.Orchestrator.sln
dotnet build .\orchestrator\CodexRescue.Orchestrator.sln -c Release --no-restore
dotnet test .\orchestrator\CodexRescue.Orchestrator.sln -c Release --no-build
```

Expected result: restore, build, and all MSTest projects pass. A source run remains unsigned and is for development only.

## 3. First-run audit

1. Launch as a standard user.
2. Confirm the header says **STANDARD USER** and **OFFLINE BY DEFAULT**.
3. Select **Run audit**.
4. Review each result:
   - **Installed** means locally detected and version-readable.
   - **Outdated** means detected but not at the allowlisted approved version.
   - **Missing** means no approved local installation was found.
   - **Blocked** means the prerequisite or policy prevents safe use.
   - **Unverified** means a component exists but its signer, version, or evidence is insufficient.
5. Export or record the audit before Apply.

Expected result: no network request, elevation prompt, configuration change, package agreement, or sign-in.

If the audit changes the machine, treat that as a defect and stop.

## 4. Toolchain maintenance

### Plan

Review exact package IDs, approved versions, installed state, disk space, pending reboot, and package agreements. Plan must not elevate or install.

### Apply

1. Approve the applicable WinGet source and package agreements.
2. Select Apply.
3. Approve UAC for that action only.
4. The broker validates the plan version, expiry, package version, target fingerprints, manifest digest, signed asset catalog, script Authenticode signature, and script hash.
5. The broker runs the fixed script using Windows PowerShell, `AllSigned`, and a typed argument list.

Expected result: only exact allowlisted components change. No Codex, Graph, GitHub, Proxmox, or Microsoft sign-in occurs.

### Reboot and resume

If a component requires restart, save the non-secret checkpoint, restart through your normal enterprise process, then relaunch. An HMAC failure, state tamper, unsupported schema, or secret-like state invalidates resume and requires a fresh audit.

## 5. Signed updates

### Online

1. Open a 30-minute maintenance window with network consent.
2. Check the signed public GitHub release.
3. Review version, publisher, architecture, minimum OS, hashes, and rollback package.
4. Open the local verified `.appinstaller` file.
5. Approve the visible Windows installation.
6. Close the maintenance window.

Expected result: no GitHub account or token is used. The release cache contains at most the current and N-1 version.

### Offline

1. Obtain the complete signed ZIP through an approved connected workstation.
2. Verify its transport hash under local policy.
3. Import it in Setup & Updates.
4. Review the verified publisher and contents.
5. Open the verified local App Installer file.

Expected result: no file escapes staging, no bundle content executes during import, and nothing is promoted before detached signature and artifact verification complete.

### Rollback

Use rollback only for a documented compatibility or support reason. In Setup & Updates, select **Open verified N-1 rollback**. The app re-verifies the cached signed release, generates a unique local App Installer descriptor for that exact bundle, requires `ROLL BACK TO <version>`, and leaves Windows App Installer visible. The descriptor uses Microsoft’s `ForceUpdateFromAnyVersion` setting because Windows otherwise blocks a lower package version; the normal update descriptor remains upgrade-only. Do not alter either descriptor or package version.

## 6. Prepare the media build host

Install the exact supported ADK and matching WinPE add-on from Microsoft. Apply the current patch for that ADK. Preserve the installer signature and hash evidence in the servicing receipt.

| Build host pass | ADK | Patch | Profiles produced |
| --- | --- | --- | --- |
| x64 pass | `10.1.26100.2454` | `KB5101684` | `x64-2023CA`, `x64-2011CA` |
| Arm64 pass | `10.1.28000.1` | `KB5101681` | `arm64-2023CA`, `arm64-2011CA` |

Arm64 output is Experimental until real Arm64 hardware passes.

## 7. Build and verify media

```powershell
$sourceRevision = (git rev-parse HEAD).Trim()
.\scripts\Build-CodexRescueMediaMatrix.ps1 `
  -ServicingReceiptPath 'C:\CodexRescue\receipts\adk-servicing.json' `
  -OutputDirectory 'C:\CodexRescue\dist\media' `
  -SourceRevision $sourceRevision
```

Expected per artifact:

- one uniquely named ISO;
- one verification JSON;
- exact architecture and CA trust path;
- exact ADK and servicing update;
- ISO SHA-256;
- injected-source hash inventory;
- required-package checks;
- no recovery material;
- SPDX SBOM and provenance JSON (an unsigned build record until externally attested); and
- `PhysicalHardwareVerified: false` until a separate hardware run.

If a receipt does not match the selected ADK, a patch signature is not Valid, or an output misses its verification file, stop. Do not rename one architecture or trust path to resemble another.

## 8. Test x64 media in Proxmox

### Profile

Record:

- HTTPS API endpoint;
- independently verified SHA-256 certificate fingerprint;
- node and storage;
- CPU, memory, disk, and maximum run time;
- `SessionOnly` credential policy unless administrator policy permits Windows Credential Manager; and
- operator-supplied API token for the current session.

### Create and boot

1. Select one verified x64 ISO.
2. Upload it through the connector.
3. Review the generated `codex-rescue-<session>` label.
4. Create the x64 q35/OVMF VM.
5. Verify the configuration contains no virtual NIC.
6. Boot and collect bounded status and screen evidence.

Expected result: the VM carries the unique label, uses the bounded resources, boots disconnected, and cannot be confused with an existing VM.

### Cleanup

1. Review VM ID and label.
2. Type `DELETE VM <id> <label>`.
3. The connector re-reads the VM tags.
4. Delete only if the session tracks the VM and the label still matches.

An API response alone is not boot proof. Record the exact ISO hash and a bounded runtime screenshot or console result.

## 9. Write a disposable USB

### Plan

Run `Write-CodexRescueUsb.ps1 -Mode Plan` with the ISO, verification JSON, and exact disk number. Physically compare the displayed model, serial, capacity, and bus with the intended device.

Expected refusal cases:

- zero or multiple selected disks;
- missing stable serial/unique ID;
- boot, system, or page-file disk;
- fixed or virtual disk;
- offline or read-only disk;
- non-USB bus;
- ISO hash mismatch;
- recovery material detected; or
- FAT32-incompatible payload.

### Apply

Store the receipt on another disk. Enter the displayed phrase exactly. The script re-scans before clearing, creates GPT/FAT32 media, copies from the verified ISO, and reads every file back.

Expected result: receipt reports the same target fingerprint, ISO hash, copied inventory, readback success, and no recovery material.

Never use customer media for the first positive test.

## 10. Repair UEFI boot in a disposable VM

### Lab preparation

- Create a disposable UEFI Windows VM.
- Attach a separate virtual disk for rollback evidence.
- Snapshot the VM under the hypervisor’s normal lab policy.
- Intentionally damage only the documented Microsoft boot files.
- Record the pre-damage boot evidence.

### Prepare

Run `Invoke-CodexRescueUefiRepair.ps1 -Mode Prepare`. Review the single Windows/EFI pair, disk fingerprint, backup location, manifest, archive hash, expand/read proof, and approval phrase.

### Apply and verify

Run Apply with the exact phrase. The action may execute only BCDBoot against that Windows/EFI pair. Verify BCD and boot files, then reboot the disposable VM.

### Roll back

Run Rollback with its separate phrase. Restore the backed-up Microsoft boot subtree, verify it, and reboot again.

Acceptance requires both successful boots and complete receipts. A command exit code without reboot proof is insufficient.

## 11. Run `.bek` BitLocker salvage in a disposable lab

### Lab preparation

- Source disk: disposable, BitLocker-encrypted data fixture with a known non-secret marker.
- Output disk: separate, blank, disposable, at least the source size.
- Evidence disk: separate from both.
- Recovery directory: exactly one owner-authorized `.bek`; optional matching `.kpg`.

### Plan

Run Plan and verify both disk identities, output blank state, output capacity, marker path/hash, key-file count, and overwrite phrase. Original recovery-material filenames must not appear in the plan.

### Apply

Run Apply with the exact phrase and a receipt on evidence storage. The script re-scans both disks, stages generic protected filenames, invokes `repair-bde -rk` with optional `-kp`, removes staging, and verifies the marker and filesystem.

### Negative tests

- wrong `.bek`;
- missing `.bek`;
- more than one `.bek` or `.kpg`;
- same source/output disk;
- nonblank output;
- undersized output;
- system disk;
- identity change; and
- wrong marker hash.

Afterward, scan Windows event logs, Sysmon if installed, application logs, temp paths, receipts, and support output for key contents and original key names.

## 12. Receipts and support

Before exporting support data:

1. select only relevant receipts;
2. review the privacy declaration;
3. verify target identifiers are appropriately minimized for your support channel;
4. confirm no raw customer evidence or recovery material is included;
5. inspect the generated archive manually; and
6. transfer it under your organization’s incident and retention policy.

In a GitHub issue include the app version, source commit, workflow stage, normalized error category, architecture, evidence tier, and reproducible non-secret steps. Do not paste raw process output if it can contain customer or recovery data.

## 13. Telemetry

Leave telemetry disabled unless administrator policy and the operator both approve it.

Before enabling:

1. enter the organization-controlled HTTPS OTLP endpoint;
2. inspect the exact envelope preview;
3. run Test Endpoint with a synthetic allowlisted event;
4. confirm the queue contains no forbidden fields; and
5. enable only for the required maintenance interval.

Use Clear Queue before handing the build VM to another customer context. Disabling consent must stop transmission immediately.

## 14. Troubleshooting decisions

| Symptom | Safe response |
| --- | --- |
| UAC cancelled | Return to Plan Ready; audit again if the host may have changed |
| Maintenance expired | Close it, review need, and obtain new consent |
| Release signer/hash invalid | Quarantine the bundle; do not retry with verification disabled |
| ADK receipt mismatch | Install/patch the matching ADK; do not override the matrix |
| Proxmox certificate changed | Stop and verify fingerprint out of band |
| Proxmox VM lost its label | Refuse cleanup and escalate to the hypervisor owner |
| USB identity changed | Invalidate approval and create a new plan |
| Multiple Windows/EFI candidates | Stop; identify the target manually outside Apply |
| UEFI backup cannot be expanded | Stop; create a new backup on healthy non-target storage |
| BitLocker output not blank | Stop; choose a disposable output and audit it again |
| `.bek` salvage fails | Preserve source, remove ephemeral staging, record normalized result, and do not try a recovery password through this path |
| Reboot does not recover | Use the proved rollback package and preserve evidence |

## 15. Acceptance checklist

- [ ] Exact source commit recorded
- [ ] All source, .NET, PowerShell, UI, and integration tests pass
- [ ] Package signatures, timestamp, publisher, manifest, hashes, SBOM, and provenance verified
- [x] x64 2023-CA and 2011-CA exact ISOs boot in disconnected disposable VMs; current 2011 result is not old-only certificate-firmware proof
- [ ] Arm64 evidence is labeled Experimental unless real hardware passed
- [x] USB writer passes a target-bound positive virtual write, full readback, and separate no-NIC boot
- [ ] USB writer passes the complete refusal/changed-identity matrix and physical write/boot
- [ ] UEFI repair and rollback both boot the disposable VM
- [ ] `.bek` salvage recovers the marker and wrong key refuses without secret leakage
- [ ] Default network and telemetry are zero
- [ ] WPF accessibility and Figma comparison pass
- [ ] README evidence ledger is updated with artifact-specific receipts
- [ ] Product owner accepts the remaining limitations

Unchecked items stay open; they are not implied by a completed source phase.
