# Codex Rescue USB recovery-media roadmap

## Goal

Deliver a recovery medium that boots into a safe Windows recovery environment, collects authorized troubleshooting evidence, supports an owner-controlled BitLocker recovery flow, and then hands off to a full Windows Codex GUI and voice workspace for guided repair. The medium must never store or transmit recovery keys, and it must never make a drive-changing repair without a target-specific operator approval.

## Delivery principle

Each phase produces a testable artifact and its own evidence. A design mockup, a build script, or a GitHub commit is not proof that the medium works. The release record distinguishes fixture behavior, build output, VM boot evidence, hardware boot evidence, and owner approval.

## Phase 1 — Boot-verified WinPE evidence image

**Outcome:** a generated ISO boots in a separate Proxmox VM and opens the Codex Rescue Disk read-only prompt.

**Build work:** verify the current Microsoft ADK servicing patch, copy the checked-in WinPE assets into the Windows build VM, generate the ISO, and attach it to a dedicated test VM. Do not use the build VM itself as the boot test.

**Acceptance evidence:** the ISO file, its hash, the test VM boot configuration, and a screenshot of the WinPE startup banner.

**Figma screen:** `01 — WinPE Startup`. It shows the read-only boundary, no-key policy, no-network default, and the single evidence-collection action.

## Phase 2 — Read-only evidence collection

**Outcome:** an operator can collect disk layout, BitLocker status, boot configuration, event-log names, driver inventory, and network configuration from a disposable test VM to an explicitly selected removable destination.

**Build work:** validate that the destination prompt rejects the WinPE RAM drive and empty input; make output naming stable; include a manifest and checksum; keep source disks read-only.

**Acceptance evidence:** a disposable test VM result, the exported `CodexRescueEvidence` package, its manifest, and a screenshot of destination selection plus the resulting folder.

**Figma screen:** `02 — Evidence Collection`. It shows source information as read-only, a prominent destination confirmation, collection progress, and a redacted export summary.

## Phase 3 — Owner-mediated BitLocker recovery

**Outcome:** the environment can show BitLocker state and guide an owner through Microsoft’s local recovery steps without retaining recovery material.

**Build work:** add a local, masked entry screen only after threat modeling; prohibit recovery-key logging, clipboard retention, audit export, and Codex context inclusion; require the exact selected volume and an owner confirmation before passing material to the local BitLocker tool.

**Acceptance evidence:** a disposable encrypted test volume, successful owner-controlled unlock, proof that no recovery key appears in logs or exports, and an independent review of the audit boundary.

**Figma screen:** `03 — BitLocker Safety Gate`. It explains the local-only handoff, redacts all key material, and makes the selected volume and cancel path unmistakable.

## Phase 4 — Full Windows Codex recovery workspace

**Outcome:** after the offline stage, an operator can explicitly start a full Windows workspace that runs the supported Codex desktop GUI and voice experience for guided diagnosis and reviewed repair.

**Build work:** define the supported full-Windows workspace, network consent, Codex installation/sign-in boundary, evidence import, redaction rules, and repair approval model. Codex does not run inside minimal WinPE.

**Acceptance evidence:** a booted workspace, a visible network-consent state, a successful Codex session without recovery keys or sensitive evidence in context, and an approved dry-run repair proposal.

**Figma screens:** `04 — Workspace Handoff` and `05 — Guided Repair Review`. They distinguish offline evidence collection from online assistance and require review before any proposed repair.

## Phase 5 — Hardware validation and release

**Outcome:** a physical USB made from the verified ISO boots on disposable hardware, preserves the read-only default, and produces a complete, redacted release record.

**Build work:** create the USB only after VM verification; test UEFI boot, storage discovery, a BitLocker test volume, evidence export, and the recovery workspace handoff. Test repair actions only on disposable targets with a documented rollback.

**Acceptance evidence:** physical boot photos or screenshots, hardware inventory, export checksum, tested recovery scenarios, known limitations, and owner approval for release.

**Documentation:** replace planned screenshot rows in the README with real, redacted screenshots and captions. Publish a compatibility matrix and a plain-language quick-start alongside the detailed operator guide.

## Screenshot and documentation standard

The beginner path should answer: what to download, how to build or write the USB, how to boot it, what is safe to click, how to export evidence, and when to stop. The professional path should include prerequisites, tooling versions, command examples, VM settings, validation artifacts, redaction procedure, threat model, compatibility notes, and rollback limits. Every image receives a caption that states the environment and evidence level.

## Explicit non-goals until validated

- No claim of physical USB recovery before physical boot evidence exists.
- No automatic repair, formatting, partition changes, or boot-record changes.
- No storage, logging, or transmission of BitLocker recovery keys.
- No claim that Codex runs in WinPE.
