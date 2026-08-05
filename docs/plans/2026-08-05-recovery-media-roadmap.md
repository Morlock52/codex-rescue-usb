# Codex Rescue USB recovery-media roadmap

## Goal

Deliver a recovery medium that boots into a safe Windows recovery environment, collects authorized troubleshooting evidence, supports an owner-controlled BitLocker recovery flow, and then hands off to a full Windows Codex GUI and voice workspace for guided repair. The medium must never store or transmit recovery keys, and it must never make a drive-changing repair without a target-specific operator approval.

## Delivery principle

Each phase produces a testable artifact and its own evidence. A design mockup, a build script, or a GitHub commit is not proof that the medium works. The release record distinguishes fixture behavior, build output, VM boot evidence, hardware boot evidence, and owner approval.

## Phase 1 — Boot-verified WinPE evidence image

**Status:** Verified in a separate disposable Proxmox UEFI VM on August 5, 2026. The README records the exact ISO size, SHA-256 hash, VM settings, and real boot screenshot.

**Outcome:** a generated ISO boots in a separate Proxmox VM and opens the Codex Rescue Disk read-only prompt.

**Build work:** verify the current Microsoft ADK servicing patch, copy the checked-in WinPE assets into the Windows build VM, generate the ISO, and attach it to a dedicated test VM. Do not use the build VM itself as the boot test.

**Acceptance evidence:** the ISO file, its hash, the test VM boot configuration, and a screenshot of the WinPE startup banner.

**Figma screen:** `01 — WinPE Startup`. It shows the read-only boundary, no-key policy, no-network default, and the single evidence-collection action.

## Phase 2 — Read-only evidence collection

**Status:** VM-verified on August 5, 2026 across three exact evidence layers. Alpha.4 verified prepared-destination discovery, zero/multiple-destination refusal, no-overwrite behavior, seven diagnostic files, a JSON manifest, SHA-256 checksums, and a separate read-only Proxmox inspection, but its BitLocker file recorded that `manage-bde` was missing. The exact alpha.7 image added SecureStartup, reran the collector, produced a real BitLocker volume/status block, passed all eight listed hashes from a separate read-only mount, and contained no recovery-key file or recovery-password-shaped text. The exact alpha.9 image then booted, preserved no-overwrite, exported a new checksum-valid package, and explicitly marked the WinPE system clock as externally unvalidated.

**Outcome:** an operator can collect disk layout, BitLocker status, boot configuration, event-log names, driver inventory, and network configuration from a disposable test VM to an explicitly selected removable destination.

**Build work:** keep the marker-gated destination discovery stable, reject WinPE's RAM drive and the ordinary internal system drive, include a manifest and checksums, refuse overwrite, and keep diagnostic commands read-only.

**Acceptance evidence:** the disposable alpha.4 destination/no-overwrite/manifest package, the corrected alpha.7 integrated package, their exact artifact records, separate read-only checksum verification, and real screenshots of both export layers.

**Figma screen:** `02 — Evidence Collection`. It shows source information as read-only, a prominent destination confirmation, collection progress, and a redacted export summary.

## Phase 3 — Owner-mediated BitLocker recovery

**Status:** Partially VM-verified on August 5, 2026. The exact alpha.7 ISO completed the external `.bek` recovery-key sub-gate against one disposable encrypted data disk in an isolated Proxmox VM. The 48-digit recovery-password interface, operating-system-volume recovery, physical hardware, and production-data gates remain pending.

**Outcome:** the environment can show BitLocker state and guide an owner through Microsoft’s local recovery steps without retaining recovery material.

**Completed sub-gate:** `WinPE-SecureStartup` is injected after `WinPE-WMI`. A local command accepts one explicit non-system data-volume letter, requires exactly one separately prepared marker drive and one hidden `.bek` file, withholds the key filename and contents, and requires `UNLOCK <drive>:` before calling Microsoft's local BitLocker tool. It performs no decryption, protector change, repair, evidence export, or network operation.

**Remaining build work:** design and implement a local masked 48-digit recovery-password screen after its own security review; prohibit recovery-password logging, clipboard retention, audit export, and Codex context inclusion; validate operating-system-volume recovery only on a disposable Windows installation; and independently review every output boundary.

**Collected acceptance evidence:** the 3-GiB data disk was 100% BitLocker-encrypted and locked before WinPE started; a separate 1-GiB key disk held one local external recovery key; alpha.7 required the exact `E:` target and `UNLOCK E:` confirmation; WinPE reported the selected volume unlocked; the known non-secret fixture file was readable; no key filename or contents appeared in the approved captures; and a cold restart returned the volume to `Lock Status: Locked`. The exact artifact is 558,286,848 bytes with SHA-256 `A4FF89AD4FBF1BEB6BAECA4B92387F0153754B270BA3DF897DA11C99812DE947`.

**Open acceptance evidence:** runtime refusal tests for missing, multiple, and ambiguous external-key inputs; a masked recovery-password UI and its refusal/failure paths; disposable operating-system-volume recovery; an independent repository/output review; and physical-hardware validation.

**Figma screen:** `03 — BitLocker Safety Gate`. It explains the local-only handoff, redacts all key material, and makes the selected volume and cancel path unmistakable. The current command-line guard validates the safety behavior; the polished screen remains an implementation gate, not a completed feature.

## Phase 4 — Full Windows Codex recovery workspace

**Status:** Partially VM-verified on August 5, 2026. The installed `OpenAI.Codex` 26.730.8199.0 package launched through its registered `codex:` protocol in the signed-in standard-user Windows session, and `C:\Users\morlock\Documents\CodexRescue` opened as the visible project. Microphone and Voice controls are visible, but the Proxmox/noVNC VM has no audio endpoint, so a spoken Voice session is not verified.

**Outcome:** after the offline stage, an operator can explicitly start a full Windows workspace that runs the supported Codex desktop GUI and voice experience for guided diagnosis and reviewed repair.

**Completed sub-gate:** the desktop shortcut now invokes the installed `codex:` protocol instead of searching for a nonexistent `codex.exe`. The guarded launcher verifies full Windows, project root, installed package, protocol registration, and audio-input state; requires the exact `START CODEX RECOVERY WORKSPACE` network-consent phrase; forbids recovery material; and disables automatic evidence import by design.

**Completed sub-gate:** the aggregate evidence-summary generator was run against the real alpha.7 and alpha.9 packages. It verified each manifest and all listed hashes, reported one BitLocker volume/status block in each package, excluded raw evidence and recovery material, refused automatic Codex import, and passed scans for private addresses, device identifiers, volume letters, key-file suffixes, and recovery-password patterns. The alpha.7 time discrepancy motivated alpha.9's explicit `ClockSource: WinPE system clock` and `ClockExternallyValidated: false` fields; recorded WinPE time remains untrusted without an independent clock check.

**Completed offline sub-gate:** the guarded network policy was installed as a SYSTEM startup task bound to interface 6 in the dedicated VM. A cold-start edge test exposed that `Get-NetAdapter -Physical` omitted the already-disabled adapter; the corrected scripts now enumerate hidden hardware interfaces, exclude virtual interfaces, and treat `Disabled` and `Not Present` as offline. The final reboot preserved standard-user auto-logon and QEMU Guest Agent access while the task completed with result 0 and the adapter settled at Disabled/0 bps. The matching token-bound enable command recovered the same interface from cold-boot `Not Present` to Up/1 Gbps.

**Remaining build work:** validate a trusted microphone/Voice path, perform a controlled manual Codex review of the redacted summary, configure least privilege for the physical recovery workflow, and validate the workspace on disposable hardware. Codex does not run inside WinPE. Windows To Go is removed, so a portable full-Windows VHDX is a separate experimental path rather than the supported release baseline.

**Collected acceptance evidence:** a booted full-Windows environment, installed package and protocol inventory, visible signed-in Codex GUI, exact `CodexRescue` project root, visible Voice control, source-CD audit with network consent false, explicit no-key/no-auto-import fields, an exact interface-6 transition from Up/1 Gbps to Disabled/0 bps and back to Up/1 Gbps, and a reboot-verified offline-at-startup task with result 0. The real screenshot is cropped to remove unrelated thread and account names.

**Open acceptance evidence:** a spoken Voice session, trusted microphone permission, controlled manual Codex review of the generated summary, least-privilege access state, and an approved dry-run repair proposal with no recovery keys or sensitive raw evidence in context.

**Figma screens:** `04 — Workspace Handoff` and `05 — Guided Repair Review`. They distinguish offline evidence collection from online assistance and require review before any proposed repair.

## Phase 5 — Hardware validation and release

**Status:** Pending. No physical USB or disposable physical test machine has been validated.

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
