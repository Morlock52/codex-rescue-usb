# Codex Rescue USB Design

Date: 2026-08-04
Status: Approved design baseline

## 1. Purpose

Codex Rescue USB is a modern, guided PC-repair environment inspired by classic bootable rescue utilities. Version one targets x86-64 Windows 10 and Windows 11 laptops and desktops using UEFI.

The USB must remain useful without internet access. Offline diagnostics provide an initial report, while an optional temporary Codex session can interpret evidence and propose a structured repair plan when connectivity is available.

The product is a guided technician, not an autonomous repair bot. It may inspect the machine read-only without approval, but it must explain and receive approval for every operation that changes a disk or Windows installation.

## 2. Goals

- Boot independently when installed Windows cannot start.
- Diagnose common boot, storage, hardware, file-recovery, and networking problems.
- Present a simple problem-first Rescue Console rather than requiring terminal knowledge.
- Keep provider AI, local evidence, proposed repairs, execution, verification, and user approval as separate facts.
- Preserve data and create rollback evidence before repair.
- Support legitimate BitLocker recovery without bypassing encryption or exposing keys.
- Operate in offline mode when internet or Codex is unavailable.
- Maintain an auditable case record that another technician can inspect.

## 3. Non-goals for version one

- Password bypass or account takeover
- BitLocker circumvention or key guessing
- Firmware flashing
- Drive wiping or secure erasure
- Partition resizing
- Automatic registry cleaning
- Unsupported malware removal
- Unattended destructive repairs
- Guaranteed repair of physically failing storage

## 4. Boot architecture

The USB uses a dual-mode UEFI boot menu:

1. **Rescue Console (default):** a small Linux live environment containing the UI, offline diagnostics, evidence collection, case store, Codex integration, safety broker, recovery tools, and cross-platform utilities.
2. **Windows Native Repair:** Windows PE for approved Windows-native DISM, SFC, BCD, registry, driver, and BitLocker operations.
3. **Memory Test:** an independent memory-diagnostic entry.
4. **Shutdown/Reboot:** explicit safe exit choices.

The build imports Windows PE from a locally installed Windows ADK. Proprietary WinPE binaries are not stored in the source repository.

A 64 GB USB is recommended. The planned layout is:

- FAT32 EFI boot partition
- Read-only Linux system image
- Windows PE image and handoff area
- Encrypted persistent case-data partition
- Recovery-backup area for rollback artifacts, subject to available capacity

Large source-disk images require separate external storage. The rescue USB must not imply that its backup area is large enough for whole-drive recovery.

## 5. Rescue Console interface

The default full-screen interface is organized by problems:

- PC won't boot
- Windows crashes or loops
- Recover my files
- Check disk and hardware
- Fix networking
- Scan and collect security evidence
- Advanced technician tools

Each workflow shows the current target, evidence gathered, confidence and uncertainty, proposed next action, risk level, rollback status, approval state, execution result, and independent verification result.

Codex chat appears beside the guided steps. It explains findings and asks focused questions, but it does not receive unrestricted shell or disk control.

An advanced terminal may be available behind a warning. Manual terminal activity is outside the guided safety contract unless the user explicitly imports its commands and results into the case record.

## 6. Components

1. **Boot Manager** selects Rescue Console, Windows Native Repair, memory testing, or exit.
2. **Rescue UI** presents problem categories, progress, evidence, Codex chat, approvals, and rollback state.
3. **Evidence Collector** runs read-only probes for hardware, SMART data, partitions, Windows installations, boot files, logs, and networking.
4. **Case Store** keeps timestamped evidence, proposals, approvals, results, hashes, and recovery artifacts in encrypted storage.
5. **Diagnostic Engine** provides deterministic offline rules for common failures.
6. **Codex Planner** interprets sanitized evidence and returns a structured diagnosis and repair plan.
7. **Safety Broker** validates actions against an allowlist, resolves exact targets, assigns risk, checks prerequisites, and blocks ambiguous or forbidden operations.
8. **Repair Runners** perform approved Linux or WinPE actions and return machine-readable results.
9. **Handoff Manager** signs and verifies the Linux-to-WinPE repair request and WinPE-to-Linux result.
10. **Artifact Manager** creates, verifies, exports, and restores rollback bundles.

## 7. Data flow

```text
Select problem
  -> collect read-only evidence
  -> run offline diagnosis
  -> optionally request Codex analysis
  -> present structured repair plan
  -> verify target and rollback prerequisites
  -> request user approval for one action
  -> execute the action
  -> verify the intended result independently
  -> continue, stop, or hand off to Windows PE
```

Actions are atomic. A broad task such as repairing Windows boot is split into identifying the Windows installation and EFI partition, backing up existing boot data, rebuilding only the required data, verifying the new configuration, and restarting for a boot test.

Command success is not repair success. Each action requires a separate verification result.

## 8. Codex and privacy boundary

Offline diagnostics always work without Codex. When internet access is available, the user starts a temporary authenticated Codex session. The implementation must use the currently supported OpenAI authentication method verified during implementation.

Credentials remain in volatile memory and are cleared at shutdown. They are not embedded in the image or stored on the USB by default.

Codex receives a minimized, sanitized evidence package. Raw personal documents, recovery keys, passwords, browser data, and unrelated files are excluded. The UI shows what will be transmitted before the request.

Codex returns structured proposals. It cannot directly run privileged commands. Only the Safety Broker can authorize a known Repair Runner operation after local validation and user approval.

## 9. BitLocker design

BitLocker is a hard security boundary. When an encrypted Windows volume is detected, Rescue Console reports it as locked and limits itself to hardware and partition-level diagnostics.

Authorized unlock methods are:

- A 48-digit BitLocker recovery password
- A recovery-key file on separate media
- A key obtained by the owner from the appropriate Microsoft, work, or school account
- A key supplied through the organization's authorized IT process

The UI displays the recovery-key ID so the user can select the matching key. Microsoft documents personal and organizational recovery-key locations and states that Microsoft Support cannot retrieve or recreate a missing key: [Find your BitLocker recovery key](https://support.microsoft.com/en-us/windows/finding-your-bitlocker-recovery-key-in-windows-6b71ad27-0b89-ea08-f143-056f5ab347d6).

Windows PE performs the local unlock through supported BitLocker tooling. Microsoft documents unlocking a drive using a recovery password or recovery-key file: [BitLocker operations guide](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/operations-guide).

Recovery material:

- Is never sent to Codex
- Is never written to the case log
- Is never persisted on the rescue USB by default
- Is accepted through a local secret-entry path
- Is cleared from temporary memory after the unlock attempt as far as the runtime permits

After unlock, the volume is initially mounted read-only. Decrypting an entire drive, deleting protectors, forcing recovery mode, or silently suspending protection is blocked from ordinary guided plans.

If no valid recovery material exists, the workflow stops before modifying the encrypted disk and offers key-location guidance, hardware diagnostics, or organizational escalation. Formatting is never presented as a BitLocker repair.

## 10. Safety and risk model

Every write operation has one of three classifications:

- **Reversible:** has a tested, verified restore operation.
- **Conditionally reversible:** requires a verified backup or disk image.
- **Irreversible:** excluded from the guided MVP or requires a future emergency workflow with stronger controls.

Before execution, the Safety Broker resolves the target using disk serial number, partition GUID, filesystem identity, Windows installation path, and BitLocker key ID where applicable. Drive letters alone are never trusted because they change across environments.

The UI must show:

- Exact target
- Proposed change
- Reason for the change
- Risk classification
- Backup or rollback artifact
- Expected verification
- Conditions that will stop the action

## 11. Failure handling and rollback

If SMART data, read errors, or unstable connectivity indicate a failing drive, ordinary repair stops. Rescue Console switches to recovery mode and recommends imaging the source to separate storage before filesystem or boot repair.

Rollback bundles may contain original EFI and BCD files, affected registry hives, configuration files, tool output, metadata, and hashes. The bundle is verified before the related repair begins.

Stop conditions include:

- Inadequate laptop power for a long operation
- Backup storage disconnect
- Disk or partition identity change
- Unexpected BitLocker relock
- Evidence contradicting the selected repair
- Partial or ambiguous tool result
- Failed post-action verification
- Invalid or unsigned WinPE handoff

Internet or Codex failure returns the user to offline diagnostics. Failed repairs remain open cases with the last known safe state and recovery instructions. There is no automatic retry loop.

## 12. MVP repair catalog

- Read-only hardware, disk, partition, Windows, boot, and network inventory
- SMART health checks and failing-drive escalation
- File copying and recovery to separate storage
- EFI and BCD inspection, backup, and guided reconstruction
- Offline Windows system-file checks and supported DISM/SFC repairs
- Filesystem inspection with elevated safeguards before correction
- Windows event-log and crash-evidence collection
- Network adapter, DHCP, DNS, and connectivity diagnosis
- BitLocker detection and authorized local unlocking
- Independent memory-test boot option
- Encrypted case export for another technician

Each catalog entry must define its inputs, preconditions, risk, permitted commands, expected outputs, rollback requirements, stop conditions, and independent verification.

## 13. Testing strategy

Automated testing starts with disposable UEFI virtual machines containing Windows 10 and Windows 11. The matrix includes:

- Secure Boot enabled and disabled
- BitLocker locked and unlocked
- Multiple disks and changed drive letters
- Broken or missing EFI files
- Malformed BCD entries
- Missing network access
- Codex unavailable or returning malformed proposals
- Failing or disconnected backup targets
- Interrupted Linux-to-WinPE handoffs
- Simulated disk-health warnings

Physical validation uses representative laptops with NVMe and SATA storage, Wi-Fi and Ethernet, different display scaling, and common vendor UEFI implementations. No real user disk is used until disposable-image tests pass.

## 14. Release gates

- Diagnosis performs zero writes to internal disks.
- No repair begins without exact target confirmation and approval.
- BitLocker secrets do not appear in logs or network payloads.
- Every supported write operation has an independent passing verification test.
- Reversible repairs restore their pre-repair state in testing.
- Interrupted workflows resume safely or stop with clear recovery instructions.
- Linux and Windows PE environments boot with Secure Boot where supported.
- Offline diagnostics remain useful without Codex or internet access.
- The generated USB image and included open-source packages have a reproducible manifest and checksums.

## 15. Initial implementation sequence

1. Establish repository structure, schemas, and threat model.
2. Build a host-runnable Rescue Console prototype using fixture evidence only.
3. Implement the case store, proposal schema, Safety Broker, and simulated Repair Runners.
4. Add read-only Linux evidence collection in a disposable VM.
5. Build and verify signed Linux-to-WinPE handoffs.
6. Add one native Windows repair canary: read-only BitLocker status and authorized unlock simulation using disposable encrypted media.
7. Add BCD backup/inspection before BCD write support.
8. Assemble reproducible Linux and WinPE images.
9. Execute the VM matrix, then limited physical-hardware validation.

The first implementation milestone is not a bootable production USB. It is a host-runnable, fixture-driven Rescue Console proving the safety contract before real disk access is introduced.
