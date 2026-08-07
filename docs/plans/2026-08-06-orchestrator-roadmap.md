# Codex Rescue Orchestrator roadmap

**Product:** Codex Rescue USB

**Application:** Codex Rescue Orchestrator

**Lifecycle:** Enterprise Technical Preview

**Research cutoff:** August 5, 2026

**Baseline:** `24e80fb` with 129 existing tests
**Rule:** an implemented source path is not accepted until its evidence gate passes.

## Product outcome

Deliver one signed, self-contained .NET 8 WPF application that guides enterprise IT technicians, MSPs, and field engineers through:

1. read-only host audit;
2. exact toolchain and project update planning;
3. separately approved Apply and Verify;
4. four independently identified WinPE ISO builds;
5. isolated x64 Proxmox tests;
6. guarded removable-media creation;
7. rollback-backed UEFI repair;
8. advanced owner-authorized `.bek` BitLocker salvage; and
9. privacy-declared receipts and support export.

Codex runs in maintained full Windows. WinPE remains a narrow offline recovery stage. Nothing in this roadmap authorizes automatic sign-in, automatic network enablement, secret retrieval, target guessing, or bypass of UAC and destructive confirmations.

## Evidence tiers

| Tier | Meaning | It does not prove |
| --- | --- | --- |
| Figma design | Intended interface and interaction state | WPF behavior, accessibility, or runtime fidelity |
| Source contract | Checked-in code contains a bounded design and automated source checks pass | Compilation, execution, device safety, or package trust |
| Windows unit/integration | .NET and PowerShell behavior passes on Windows fixtures | VM boot, destructive target behavior, or hardware compatibility |
| Package | Signed install, launch, update, rollback, and uninstall pass on a clean VM | Media boot or repair behavior |
| VM runtime | Exact artifact operates on a disposable virtual target | Physical hardware, firmware diversity, or production data |
| Emulation | Architecture-specific boot path reaches a bounded state | Real Arm64 hardware compatibility |
| Physical hardware | Exact signed artifact passes a documented representative device test | Universal compatibility or production acceptance |
| Owner acceptance | Named owner approves the evidence and remaining risk | Future versions or different artifacts |

## Phase 1 — design system and contracts

### Scope

- Figma tokens: Atkinson Hyperlegible, IBM Plex Mono, neutral surfaces, green verification, amber caution, and red destructive actions.
- Reusable navigation, status, evidence, destructive-confirmation, and receipt components.
- Setup, Build Matrix, Proxmox, USB, UEFI, BitLocker, and Receipts screens.
- Guided and Expert descriptions of the same state machine.
- Keyboard focus, screen-reader names, 125–200% scaling, offline, error, UAC-cancel, reboot, and resume states.
- Versioned `ActionPlanV1`, `ActionReceiptV1`, `CheckpointV1`, `ReleaseManifestV1`, `ProxmoxProfileV1`, and `TelemetryEnvelopeV1`.

### Current evidence

- Seven Figma frames exported and checked in as labeled design images.
- Shared WPF brushes, typography, card styles, and seven workflow pages checked in.
- Contract records and source checks checked in.

### Open exit gates

- Windows runtime screenshots at 100%, 125%, 150%, 175%, and 200%.
- Automated accessibility scan.
- Keyboard-only and high-contrast walkthrough.
- Screen-reader labels and error announcements verified in runtime.
- Pixel/structural comparison to the approved Figma frames.

## Phase 2 — standard-user Orchestrator

### Scope

- Local, zero-network host audit.
- Audit → Plan → Approval → Apply → Restart/Resume → Verify → Receipt state machine.
- Maintenance windows requiring network consent and expiring after 30 minutes.
- Signed public GitHub release checks against a fixed repository.
- Signed offline ZIP import with path-traversal rejection.
- Trusted code-signing chain, stable publisher identity, detached signature, size, path, and SHA-256 verification.
- N-1 verified package cache and downgrade refusal.
- Machine-protected HMAC checkpoints containing no credentials or recovery material.
- Operator-visible local `.appinstaller` launch.

### Current evidence

- Source and tests are checked in.
- 173 cross-platform source/fixture contracts pass locally.

### Open exit gates

- .NET restore/build/MSTest on `windows-2025`.
- Fresh install, current update, duplicate refusal, downgrade refusal, N-1 rollback, offline import, changed signature/hash, no network, partial install, UAC cancel, reboot, and resume integration tests.
- Confirm zero network requests with maintenance and telemetry disabled.

## Phase 3 — signed broker and release

### Scope

- Standard-user WPF process.
- Short-lived, per-action elevation of `CodexRescue.Broker`.
- No permanent privileged service.
- Fixed typed operations and fixed signed asset paths.
- Authenticode and SHA-256 verification of packaged scripts.
- Rejection of loose scripts, checkout scripts, unexpected assets, unsupported schemas, or changed signers.
- Protected-tag GitHub Actions release using Azure OIDC and Azure Artifact Signing.
- Timestamped scripts, PE files, MSIX bundle, and detached release manifest.
- Hashes, SPDX SBOM, rollback metadata, and GitHub build provenance.

### Current evidence

- Broker, catalog, runner, packager, App Installer template, and release workflows are checked in.
- Unsigned CI output is explicitly labeled developer-only.

### Open exit gates

- Azure publisher identity validation.
- `production-signing` GitHub environment and OIDC federation.
- Artifact Signing role and account/profile configuration.
- First protected tag build.
- Clean Windows 11 signed install, launch, update from N-1, rollback, and uninstall.
- Tampered script, loose script, wrong signer, changed catalog, and unsupported schema package tests.

## Phase 4 — multi-architecture media and Proxmox lab

### Scope

- `x64-2023CA` and `x64-2011CA` using ADK `10.1.26100.2454` with `KB5101684`.
- `arm64-2023CA` and `arm64-2011CA` using ADK `10.1.28000.1` with `KB5101681`.
- `/bootex` only for Windows UEFI 2023 CA media.
- Per-artifact ISO, verification JSON, SHA-256, toolchain versions, source inventory, required-package checks, SBOM, provenance, and evidence tier.
- Proxmox connector with pinned HTTPS certificate, session token, bounded resources, unique labels, disconnected OVMF x64 VM, and label-rechecked deletion.

### Current evidence

- Four-entry matrix, servicing receipt gates, parameterized builders, ISO verifier, and connector source are checked in.
- Existing alpha.13 x64 VM evidence is preserved but does not validate the new four-artifact output.

### Open exit gates

- Build both x64 artifacts with current serviced ADK.
- Boot both x64 trust paths in separate disconnected disposable VMs.
- Record exact ISO hashes, VM configuration, prompt evidence, and cleanup receipts.
- Build Arm64 artifacts and collect clearly labeled emulation evidence.
- Keep Arm64 **Experimental** until exact artifacts pass real Arm64 hardware.

## Phase 5 — guarded USB creation

### Scope

- Exactly one explicit removable USB disk.
- Reject boot, system, page-file, fixed, virtual, ambiguous, offline, read-only, small, or identity-changing media.
- Display model, serial, bus, capacity, number, ISO trust path, and ISO hash.
- Re-scan immediately before destructive execution.
- Require `ERASE USB DISK <number> <fingerprint-suffix>`.
- Create GPT/FAT32 UEFI media with built-in Windows tooling.
- Reject files larger than the FAT32 per-file limit.
- Read back copied payload hashes before receipt.

### Current evidence

- Plan/Apply source and source contracts are checked in.

### Open exit gates

- Zero, one, and multiple virtual/removable target tests.
- Offline, read-only, fixed, boot/system, page-file, ambiguous, and changed-identity refusal tests.
- Positive disposable virtual USB write and full readback.
- Physical disposable USB write, 2023-CA and 2011-CA representative boot, evidence export, and receipt.

## Phase 6 — UEFI repair and rollback

### Scope

- Read-only discovery of exactly one Windows and one FAT32 EFI partition on the same healthy disk.
- EFI tree and BCD evidence backup to non-target storage.
- Per-file manifest, archive hash, expand, and read proof.
- Target-bound plan and fresh Apply phrase.
- Minimal BCDBoot operation only.
- Post-repair BCD and boot-file verification.
- Separate rollback approval and Microsoft boot-subtree restore.

### Current evidence

- Prepare/Apply/Rollback source and source contracts are checked in.
- The earlier inert plan contract remains documented separately.

### Open exit gates

- Disposable UEFI VM with intentionally damaged boot files.
- Refusal for multiple Windows or EFI candidates.
- Backup on separate virtual disk and restore-read proof.
- Repair, reboot to Windows, rollback, and second successful reboot.
- Receipt and secret scan.

## Phase 7 — advanced BitLocker salvage

### Scope

- Advanced operator only.
- Distinct stable source/output disk identities.
- Blank, disposable output at least as large as source.
- Owner-supplied `.bek` and optional matching `.kpg` only.
- No `repair-bde -rp` numerical recovery password path.
- No recovery material in logs, filenames, receipts, process output, or support bundles.
- Known non-secret marker and read-only filesystem verification.

### Current evidence

- Plan/Apply source, generic protected staging, output overwrite warning, and source contracts are checked in.

### Open exit gates

- Two disposable virtual disks with a known encrypted fixture.
- Correct `.bek`, wrong `.bek`, optional key-package, undersized output, nonblank output, same-disk, and changed-identity tests.
- Known marker recovery and filesystem read checks.
- Event, Sysmon, application log, receipt, temp, and support-bundle secret scans.

## Phase 8 — receipts, telemetry, documentation, and release candidate

### Scope

- Versioned receipts and normalized error categories.
- Sanitized support bundle.
- Telemetry disabled by default.
- Administrator policy plus operator consent before HTTPS OTLP.
- Exact outgoing-field preview, Disable, Clear Queue, and Test Endpoint.
- Product-focused README with direct install/update/offline/rollback/uninstall and beginner/Expert feature examples.
- Every screenshot labeled Figma, source, VM, emulation, virtual target, or physical hardware.

### Current evidence

- Receipt and telemetry contracts, filtering policy, redesigned README, screenshots, and evidence ledger are checked in.

### Open exit gates

- Runtime receipt browser and support export.
- Empty/default telemetry queue, endpoint test, disable, clear, consent revocation, and network capture.
- Real WPF screenshots replacing or complementing each Figma design.
- First signed release only after source, package, x64 VM, virtual target, update, design, documentation, and privacy gates pass.

## Release decision

The first signed Enterprise Technical Preview may be published only when all of these are independently verified:

- all existing and new source tests pass;
- Windows .NET build and unit tests pass;
- PSScriptAnalyzer passes;
- Azure signatures and timestamps validate;
- clean-VM install, update, rollback, and uninstall pass;
- both x64 trust-path ISOs boot in disconnected disposable VMs;
- virtual USB write/readback passes;
- UEFI repair and rollback pass on a damaged disposable VM;
- `.bek` salvage and wrong-key refusal pass without secret leakage;
- default network and telemetry are zero;
- accessibility and Figma runtime comparison pass;
- documentation evidence labels match the artifacts; and
- the product owner accepts the remaining physical/Arm64 limitations.

Physical x64 USB boot and real Arm64 hardware remain separate gates. They are never inferred from source, VM, or emulation results.
