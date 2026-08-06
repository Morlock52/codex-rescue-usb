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

**Status:** Verified through alpha.13. The historical alpha.4, alpha.7, and alpha.9 evidence layers remain valid for their narrower gates. Alpha.13 adds the exact destination-approval token, full destination rescan, regular-file marker check, and ten-file package with privacy-preserving offline Windows, setup/repair-log, offline-BCD, Autopilot, and Intune/MDM inventory. Its public file contract passed the full-Windows VM against both a disposable mapped installation and the real Windows installation, and the exact verified alpha.13 ISO then booted disconnected in VM 114 and exported the package. A separate read-only Proxmox mount verified all nine checksum-list entries and the explicit false privacy flags. The checked-in redacted-summary generator reverified that same package, wrote its aggregate output outside the source directory, and passed independent scans for recovery-password patterns, private IPv4 addresses, MAC addresses, key-file suffixes, and the build VM's standard-user name.

**Outcome:** an operator can collect disk layout, BitLocker status, boot configuration, event-log names, driver inventory, network configuration, redacted offline Windows/log/profile metadata, bounded management-event aggregates, and sanitized offline-BCD signals to an explicitly selected removable destination.

**Completed build work:** the exact alpha.13 artifact confirmed destination approval and rescan in WinPE, exported and independently verified the ten-file package, and retained tolerant read-only probing for inaccessible candidate drives. Destination discovery rejects WinPE's RAM drive and the ordinary internal system drive; source discovery may probe mounted Windows installations read-only.

**Acceptance evidence:** the disposable alpha.4 destination/no-overwrite/manifest package, the corrected alpha.7 integrated package, the exact alpha.13 ISO and verifier JSON, the alpha.13 ten-file package, separate read-only checksum verification, the 1,663-byte redacted summary with SHA-256 `191CC0786EC8FB49FC2D973B0AF06A242A6DDB8216B36FD7B42233FA9D3013B7`, privacy scans, and real VM console evidence of the current boot, approval, and summary layers.

**Figma screen:** `02 — Evidence Collection`. It shows source information as read-only, a prominent destination confirmation, collection progress, and a redacted export summary.

## Phase 3 — Owner-mediated BitLocker recovery

**Status:** Partially VM-verified on August 5, 2026. The exact alpha.7 ISO completed the external `.bek` recovery-key sub-gate against one disposable encrypted data disk in an isolated Proxmox VM. The exact derived alpha.11 candidate (`558,899,200` bytes; SHA-256 `7EFB41B96A247FEB49E9B9037AD379F6528EC9184A105D19AF819532152513B0`) booted in dedicated no-data-disk VM 114 and verified the corrected launch command, wrong-token refusal, and blocked `C:`/`X:` targets. The boot-verified alpha.10 artifact then ran the exact checked-in helper through a confidential in-process input boundary against a disposable encrypted data disk: invalid format and a valid wrong password were rejected, the correct password unlocked only the selected volume, the known marker became accessible, captured output contained no recovery material, and a cold power cycle returned the volume to locked. The exact alpha.13 artifact (`558,282,752` bytes; SHA-256 `67E79C37021879BAE2BC405B4618B666D6FD11397227D95C111353020E64A794`) passed normalized source/payload/package verification, a separate disconnected UEFI boot, and a checksum-valid privacy-safe ten-file evidence export. Human masked entry remains open. Operating-system-volume recovery, physical hardware, and production-data gates also remain pending.

**Outcome:** the environment can show BitLocker state and guide an owner through Microsoft’s local recovery steps without retaining recovery material.

**Completed sub-gate:** `WinPE-SecureStartup` is injected after `WinPE-WMI`. A local command accepts one explicit non-system data-volume letter, requires exactly one separately prepared marker drive and one hidden `.bek` file, withholds the key filename and contents, and requires `UNLOCK <drive>:` before calling Microsoft's local BitLocker tool. It performs no decryption, protector change, repair, evidence export, or network operation.

**Remaining build work:** perform the local human masked-entry check without recording or redirection; validate operating-system-volume recovery only on a disposable Windows installation; and independently review every output boundary.

**Collected acceptance evidence:** the 3-GiB external-key data disk was 100% BitLocker-encrypted and locked before WinPE started; alpha.7 required the exact `E:` target and `UNLOCK E:` confirmation, unlocked only that volume, exposed the known non-secret file, and cold-relocked without exposing key material. The separate numerical-password fixture passed invalid-format, wrong-password, correct-unlock, marker-access, output-leakage, and cold-relock checks through the exact alpha.10 helper. The approved captures contain state only and no recovery material.

**Open acceptance evidence:** runtime refusal tests for missing, multiple, and ambiguous external-key inputs; human entry through the masked recovery-password prompt; disposable operating-system-volume recovery; an independent repository/output review; and physical-hardware validation.

**Figma screen:** `03 — BitLocker Safety Gate`. It explains the local-only handoff, redacts all key material, and makes the selected volume and cancel path unmistakable. The current command-line guard validates the safety behavior; the polished screen remains an implementation gate, not a completed feature.

## Phase 4 — Full Windows Codex recovery workspace

**Status:** Partially VM-verified on August 5, 2026. The installed `OpenAI.Codex` 26.730.8199.0 package launched through its registered `codex:` protocol in the signed-in standard-user Windows session, and `C:\Users\morlock\Documents\CodexRescue` opened as the visible project. Microphone and Voice controls are visible, but the Proxmox/noVNC VM has no audio endpoint, so a spoken Voice session is not verified.

**Outcome:** after the offline stage, an operator can explicitly start a full Windows workspace that runs the supported Codex desktop GUI and voice experience for guided diagnosis and reviewed repair.

**Completed sub-gate:** the desktop shortcut now invokes the installed `codex:` protocol instead of searching for a nonexistent `codex.exe`. The guarded launcher verifies full Windows, project root, installed package, protocol registration, and audio-input state; requires the exact `START CODEX RECOVERY WORKSPACE` network-consent phrase; forbids recovery material; and disables automatic evidence import by design.

**Completed sub-gate:** the aggregate evidence-summary generator was run against the real alpha.7, alpha.9, and alpha.13 packages. It verified each manifest and every listed hash, excluded raw evidence and recovery material, refused automatic Codex import, and passed the applicable privacy scans. Alpha.13 additionally verified the current ten-file contract and offline-inventory privacy declarations, then wrote a new aggregate summary outside the package with operator review still required. The alpha.7 time discrepancy motivated alpha.9 and alpha.13's explicit `ClockSource: WinPE system clock` and `ClockExternallyValidated: false` fields; recorded WinPE time remains untrusted without an independent clock check.

**Completed offline sub-gate:** the guarded network policy was installed as a SYSTEM startup task bound to interface 6 in the dedicated VM. A cold-start edge test exposed that `Get-NetAdapter -Physical` omitted the already-disabled adapter; the corrected scripts now enumerate hidden hardware interfaces, exclude virtual interfaces, and treat `Disabled` and `Not Present` as offline. The final reboot preserved standard-user auto-logon and QEMU Guest Agent access while the task completed with result 0 and the adapter settled at Disabled/0 bps. The matching token-bound enable command recovered the same interface from cold-boot `Not Present` to Up/1 Gbps.

**Completed review sub-gate:** the real alpha.9 aggregate summary was staged without its raw package or any recovery material. Codex ran in **Ask for approval** mode and used one approved, exact, read-only file command. It verified schema v1 and eight checksum entries covering seven diagnostic files and 21,407 bytes; summarized the available diagnostic categories without revealing network details; preserved the untrusted-clock warning; and recommended keeping the package offline for operator review. The matching file hash was independently verified before and after staging. Networking was disabled again, and an out-of-band audit found the startup task Ready/result 0, interface 6 Disabled/0 bps, zero temporary automation tasks, and QEMU Guest Agent running.

**Remaining build work:** validate a trusted microphone/Voice path, configure least privilege for the physical recovery workflow, and validate the workspace on disposable hardware. Codex does not run inside WinPE. Windows To Go is removed, so a portable full-Windows VHDX is a separate experimental path rather than the supported release baseline.

**Collected acceptance evidence:** a booted full-Windows environment, installed package and protocol inventory, visible signed-in Codex GUI, exact `CodexRescue` project root, visible Voice control, source-CD audit with network consent false, explicit no-key/no-auto-import fields, an exact interface-6 transition from Up/1 Gbps to Disabled/0 bps and back to Up/1 Gbps, a reboot-verified offline-at-startup task with result 0, and a bounded manual review of the hash-matched alpha.9 aggregate summary with no raw evidence or recovery material in the workspace. The published GUI screenshot is cropped to remove unrelated thread and account names; the manual-review transcript remains private because the live app frame also contained unrelated account and thread metadata.

**Open acceptance evidence:** a spoken Voice session, trusted microphone permission, a physical-workflow least-privilege access state, and an approved dry-run repair proposal with no recovery keys or sensitive raw evidence in context.

**Figma screens:** `04 — Workspace Handoff` and `05 — Guided Repair Review`. They distinguish offline evidence collection from online assistance and require review before any proposed repair.

## Phase 5 — Hardware validation and release

**Status:** Pending. No physical USB or disposable physical test machine has been validated.

**Outcome:** a physical USB made from the verified ISO boots on disposable hardware, preserves the read-only default, and produces a complete, redacted release record.

**Readiness sub-gate:** the repository includes a Windows Forms readiness GUI that validates the selected ISO against the expected SHA-256, requires exactly one online writable non-system USB disk, shows its stable identity fields for physical confirmation, and emits a fresh JSON plan with `WritePerformed: false` to local non-USB storage only. Static safety tests forbid target-disk mutation and external-writer launch operations. A live negative-path run used the exact commit `DDF0F58` GUI and alpha.13 ISO in offline VM 111: `Get-Disk` reported zero USB disks, the GUI displayed `found 0`, and Validate, physical confirmation, and Save Plan remained disabled. The temporary interactive task and GUI process were removed afterward.

The macOS readiness CLI adds the same no-write gate for the available physical-writer host. It requires the default alpha.13 SHA-256, exactly one external physical writable USB whole disk, a token bound to the live disk identifier/size and ISO hash, a second immediate identity recheck, and an internal non-target no-overwrite JSON destination. On August 6, 2026, its live discovery path found zero external physical disks on the Mac and safely refused without elevation, plan creation, disk modification, or writer launch. Four new tests cover the positive selection contract and destructive-command absence. Both live results prove zero-device safety only; neither creates or validates physical media.

**Build work:** run a positive readiness path on the selected physical writer host with exactly one intended blank USB disk; independently re-check the resulting ISO and target identity in a dedicated USB-writing tool; create the USB only after VM verification; test UEFI boot, storage discovery, a BitLocker test volume, evidence export, and the recovery workspace handoff. Test repair actions only on disposable targets with a documented rollback.

**Acceptance evidence:** physical boot photos or screenshots, hardware inventory, export checksum, tested recovery scenarios, known limitations, and owner approval for release.

**Documentation:** replace planned screenshot rows in the README with real, redacted screenshots and captions. Publish a compatibility matrix and a plain-language quick-start alongside the detailed operator guide.

## Screenshot and documentation standard

The beginner path should answer: what to download, how to build or write the USB, how to boot it, what is safe to click, how to export evidence, and when to stop. The professional path should include prerequisites, tooling versions, command examples, VM settings, validation artifacts, redaction procedure, threat model, compatibility notes, and rollback limits. Every image receives a caption that states the environment and evidence level.

## Explicit non-goals until validated

- No claim of physical USB recovery before physical boot evidence exists.
- No automatic repair, formatting, partition changes, or boot-record changes.
- No storage, logging, or transmission of BitLocker recovery keys.
- No claim that Codex runs in WinPE.
