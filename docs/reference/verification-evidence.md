# Verification evidence

This record summarizes the strongest current evidence without collapsing source tests, VM runtime, physical hardware, and production readiness into one claim.

## Current source verification

Fresh local verification on August 6, 2026:

```text
python3 -W error::ResourceWarning -m unittest discover -s tests -v
Ran 182 tests
OK
```

The original 129 tests remain. The added source contracts cover the .NET assemblies, wire contracts, WPF workflow, state machine, release verification, sealed checkpoints, telemetry policy, same-user named-pipe broker handoff, typed broker, signed asset catalog, sanitized support export, four-artifact media matrix, per-artifact hash/SBOM/provenance outputs, guarded USB writer, UEFI executor/rollback, `.bek` salvage, MSIX/release workflows, online/offline update boundaries, and Proxmox connector.

Windows CI run [31142547832](https://github.com/Morlock52/codex-rescue-usb/actions/runs/31142547832) for commit `a5a02c9` then produced a clean Windows build with 0 warnings, 21/21 passing MSTests, a passing PSScriptAnalyzer gate, and a self-contained x64 artifact explicitly labeled unsigned developer output. Automated tests do not prove a signed package, installation, UI accessibility, VM execution, physical USB, or production recovery.

## Orchestrator milestone evidence

| Area | Strongest current evidence | Open gate |
| --- | --- | --- |
| Figma workflow | Seven checked-in design exports | Windows runtime/accessibility comparison |
| .NET Orchestrator | 182 source/fixture tests, clean Windows build, and 21 MSTests | Runtime accessibility and integration matrix |
| Signed broker | Typed allowlist, fixed assets, Authenticode/hash source contracts | Azure-signed package tamper tests |
| Updates | Detached signature, stable publisher, chain/hash/path verification source | Signed clean-VM update and N-1 rollback |
| Four-ISO matrix | Exact x64 pair built and verified; Arm64 source profiles present | Arm64 build/emulation and hardware |
| Proxmox connector | Pinning, bounds, unique-label/no-NIC/delete source contracts | Live endpoint receipt |
| USB writer | Exact virtual target Plan/Apply, GPT/FAT32, 192-file readback, and separate no-NIC boot | Full refusal matrix and physical write/boot |
| UEFI repair | Backup/Apply/Verify/Rollback source contracts | Damaged disposable VM boot and rollback |
| `.bek` salvage | Distinct/blank/sized output and secret-control source contracts | Disposable encrypted virtual-disk run |

See the [Orchestrator roadmap](../plans/2026-08-06-orchestrator-roadmap.md) for the complete exit criteria.

## Current x64 media build and Proxmox boot

Commit `0b5c3d6d7830279abbdf0f3cadf0ec102b75a2b2` was cloned cleanly into Windows VM 111 and built using the serviced x64 ADK/WinPE toolchain. The typed matrix receipt SHA-256 is `88E65E46016A802C57B95FC2AF0A4ABE350F3329AA4419B6F996CF5056D82CFE`.

| Profile | ISO size | ISO SHA-256 | Strongest current evidence |
| --- | ---: | --- | --- |
| `x64-2023CA` | 558,465,024 bytes | `4FFAA638D3F046B132A42E4751317D3290D6167F40CCF0DE129043A4D808BFBA` | Verification JSON passed; SBOM/provenance bound the source revision; exact ISO reached WinPE in a separate no-NIC OVMF VM |
| `x64-2011CA` | 558,282,752 bytes | `A4F6F7AA5620A72627ECEDE5F33E2EE35209BA28A7D8CC5E5CA5DFAEE52CF2A3` | Verification JSON passed; SBOM/provenance bound the source revision; exact ISO reached WinPE in a separate no-NIC OVMF VM |

The [machine-readable boot and cleanup receipt](../evidence/2026-08-07-x64-proxmox-boot.json) records PVE `9.2.4`, q35/OVMF, zero configured virtual NICs, exact ISO and screenshot hashes, and deletion of only the two source-labeled disposable VMs after re-identification. The 2023-CA and 2011-CA screenshots are retained as VM-runtime evidence.

The current Proxmox pre-enrolled variable store reports `2023k` even for the compatibility-media test. The `x64-2011CA` result therefore proves that exact compatibility ISO booted under the current combined/default pre-enrolled set; it does **not** prove an old-only 2011-certificate firmware configuration. No physical USB, physical Secure Boot, repair, salvage, accessibility, or Arm64 claim follows from these VM boots.

## Current virtual USB write and boot

Commit `a5a02c98b5ddc8bbda8650428704ec85c2d4df5e` hardened the writer after a live disposable target exposed an unsafe assumption: a clear operation must be followed by an observed RAW state before initialization, and partition sizing must use Windows’ actual free extent. The regression contract, full 182-test suite, PSScriptAnalyzer, Windows 0-warning build, and 21 MSTests passed before the corrected script was applied.

The final target-bound [plan](../evidence/2026-08-07-virtual-usb-write-plan.json) selected virtual USB serial `CRU-A5A02C9-02`, bus `USB`, 2,147,483,648-byte capacity, and fingerprint `BB8991D325B6B3D9C6330A33A71CAFF50215E3D84A4B9B225B367B50E3E99579`. The [ActionReceiptV1 write receipt](../evidence/2026-08-07-virtual-usb-write-receipt.json) has SHA-256 `BAE527A8299FB1E9CB042CF5ADE5A5EC961E8EF8954A4130FEE0F652D1736BCB` and records:

- result `Succeeded` and normalized error `NONE`;
- exact ISO SHA-256 `4FFAA638D3F046B132A42E4751317D3290D6167F40CCF0DE129043A4D808BFBA`;
- GPT/FAT32 creation; and
- 192 source-file readback hashes before receipt issuance.

Independent post-action checks found a healthy FAT32 volume, `EFI\\BOOT\\BOOTX64.EFI`, 194 total target files including Windows-created metadata, and zero numerical-recovery-password, `.bek`, or key-package extension matches in the receipt. The 2 GiB raw backend SHA-256 is `9035B29DCAF3D2360AD8F2033FBE46B9DC0A4F7F9F116CBB9AD2EF77BD97C492`.

A separate q35/OVMF VM with zero configured NICs selected that exact USB serial and reached the WinPE recovery prompt with the backend attached read-only. The VM was re-identified by name and unique tag before deletion. The [lab receipt](../evidence/2026-08-07-virtual-usb-lab.json) binds the write, readback, screenshots, boot, cleanup, and earlier failed attempts without converting them into success claims.

This proves a positive **virtual USB** write/readback/boot path. It does not prove physical USB discovery, erase, write, removal, Secure Boot, or hardware boot.

## Exact WinPE milestones

| Milestone | Artifact | Size | SHA-256 | Strongest evidence |
| --- | --- | ---: | --- | --- |
| alpha.4 | `Codex-Rescue-ISO-v0.1.0-alpha.4.iso` | 557,518,848 bytes | `F7F6E3570F0DBF264D56CAAF8703C6FB6EAD99ABB53FDC420D9B4737C9584DFA` | VM boot, prepared destination, no-overwrite, nine-file export |
| alpha.7 | `Codex-Rescue-ISO-v0.1.0-alpha.7.iso` | 558,286,848 bytes | `A4FF89AD4FBF1BEB6BAECA4B92387F0153754B270BA3DF897DA11C99812DE947` | SecureStartup, guarded external-key unlock, known fixture file, cold relock |
| alpha.9 | `Codex-Rescue-ISO-v0.1.0-alpha.9.iso` | 558,243,840 bytes | `7080E6D51AFADDD6531390FA8A6EDECE8AFCF1AC419FECE36E0C4EE96C087D29` | disconnected boot, fresh evidence export, explicit unvalidated clock |
| alpha.10 | `Codex-Rescue-ISO-v0.1.0-alpha.10-94CE0A74.iso` | 558,180,352 bytes | `94CE0A744855FA777E54BC5B9CE2609D3BD7BE6D8A0121B30D09BE35CCCAD46C` | confidential disposable-volume runtime and cold-relock harness; banner later superseded |
| alpha.12 | `Codex-Rescue-ISO-v0.1.0-alpha.12-5E2E1F90.iso` | 557,871,104 bytes | `5E2E1F90765DF00BAA3F9EA66282DBB4A1C981B87FBCAD9C6533ABF66AC58089` | clean verifier and disconnected UEFI boot |
| **alpha.13** | `Codex-Rescue-ISO-v0.1.0-alpha.13-67E79C37.iso` | **558,282,752 bytes** | **`67E79C37021879BAE2BC405B4618B666D6FD11397227D95C111353020E64A794`** | normalized payload verification, disconnected UEFI boot, privacy-safe ten-file export |

The alpha.13 screenshot set was captured from the exact recorded artifact in disconnected UEFI VM 114. It proves that artifact’s VM boot and evidence path, not physical USB compatibility.

## BitLocker proof boundary

### External-key path

Verified in a disposable isolated VM using a 3-GiB encrypted data disk and separate 1-GiB key disk:

- explicit data-volume target;
- exactly one prepared key drive and key file;
- exact `UNLOCK <drive>:` confirmation;
- ordinary `C:` and WinPE `X:` blocked by source tests;
- selected volume reached unlocked state;
- known non-secret fixture file was readable;
- recovery material was not shown in recorded output; and
- cold restart returned the disposable volume to locked state.

### Numerical-password path

Verified through a confidential automated boundary on a disposable encrypted data volume:

- wrong token refused;
- invalid format refused;
- wrong password refused;
- correct password unlocked the selected volume;
- known fixture content became readable;
- cold restart relocked the volume; and
- captured-stream leakage scans were clean.

This does not prove human masked typing, operating-system-volume recovery, physical hardware, or production-data handling.

## Full-Windows workspace evidence

Windows VM 111 is a dedicated Proxmox recovery build and runtime environment with 4 vCPU and 12 GB fixed RAM. The validated environment includes:

- Windows ADK and WinPE add-on `10.1.26100.2454`, serviced with `KB5101684`;
- native Windows PowerShell 5.1 runtime for project harnesses;
- QEMU Guest Agent automatic startup;
- exact-interface offline-at-startup network policy;
- Git, GitHub CLI, PowerShell 7, Python, Node.js, editors, and Codex tooling; and
- the Codex desktop package opened on the staged project.

The project verified a disabled/0-bps selected network adapter after cold boot, a later exact-token enable, and a return to disabled state. This is VM policy evidence, not physical-network containment proof.

### Local diagnostic module

Native Windows runtime verification established:

- 14 exported read-only commands;
- ten required check groups;
- zero repairs and zero cloud requests by default;
- zero online network tests by default;
- validated local and sanitized report schemas; and
- prohibited-secret scans passing.

### WPF dashboard

Native runtime verification established:

- checked-in XAML loaded in Windows PowerShell STA mode;
- exactly ten diagnostic cards;
- validated assessment contract;
- no repair controls;
- cloud disabled; and
- detailed local report and sanitized ZIP controls enabled only for explicit existing artifacts.

### Graph module

Native Windows deterministic mock/runtime verification established:

- four exported commands;
- Microsoft Graph authentication prerequisite compatible;
- four fixed delegated read-only scopes;
- five bounded cloud checks and endpoint shapes;
- `GET` only and zero write requests;
- process-scoped authentication requirement;
- identifiers absent from returned assessment;
- recovery-key values neither requested nor collected; and
- permission, not-found, unavailable, and not-tested outcomes remain distinct.

No real tenant sign-in or result set is claimed.

### Codex handoff

The installed Windows desktop app opened on the exact staged project. A separately generated alpha.9 aggregate summary passed integrity and privacy validation, and one controlled read-only review ran in **Ask for approval** mode. The VM screenshot shows the available Voice control, but the VM had no audio input endpoint and no spoken session is claimed.

## UEFI boot-repair proposal evidence

The source tree now contains an inert schema-v1 proposal generator and four focused runtime/static tests. Current proof covers:

- a valid secret-free fixture producing a target-bound JSON proposal;
- a proposal digest and a separate Windows/EFI target fingerprint;
- rejection of recovery-material declarations, mismatched disk identities, and rollback artifacts without a restore test;
- no-overwrite output behavior; and
- a static contract with no command-execution or disk-mutation path.

Fixture proposals always record `LiveEvidence: false`, `ReadyForApproval: false`, `ExecutionAvailable: false`, and `WritePerformed: false`. This is source-contract evidence, not a live discovery, approval, repair, boot, or rollback result. See the [UEFI boot-repair proposal contract](uefi-boot-repair-proposal.md).

## Physical USB readiness evidence

The GUI’s live **zero eligible USB disks** path ran in offline Windows VM 111 against the hash-matched alpha.13 ISO. It displayed the expected refusal and kept validation, physical-identity confirmation, and plan-save controls disabled.

On August 6, 2026, the macOS readiness CLI’s live disk-discovery path ran on the project Mac with no external physical disk attached. `diskutil list -plist external physical` returned zero whole disks and the tool stopped with `found 0`. It did not require elevation, create a plan, touch a disk, or launch a writer. Four deterministic tests separately verify the positive exactly-one-disk contract, ISO mismatch and target-bound token behavior, internal-only no-overwrite plan storage, and the absence of disk mutation/writer commands. This is a second safe-refusal proof, not a positive physical-media result.

This is safe-refusal evidence only. It does not establish:

- positive exactly-one-USB selection;
- a saved positive readiness plan;
- USB erase or ISO write;
- UEFI boot on physical hardware;
- evidence export between two physical removable drives;
- BitLocker recovery on a physical disposable volume; or
- recovery of a real PC.

## Open acceptance gates

- [ ] Positive exactly-one-USB identity and plan path on a disposable physical drive
- [ ] Independent physical write with recorded ISO SHA
- [ ] UEFI/Secure Boot matrix on representative hardware
- [ ] Separate physical evidence-destination path and no-overwrite retest
- [ ] Human local masked numerical-password entry with no recording or redirection
- [ ] Disposable physical data-volume unlock and cold relock
- [ ] Authorized disposable OS-volume recovery design and test
- [ ] Full-Windows portable/workspace image completion under applicable Microsoft license terms
- [ ] Least-privilege physical Codex workflow
- [ ] Working microphone/audio endpoint and spoken Voice acceptance
- [ ] Real authorized tenant Graph consent and bounded result validation
- [ ] Live UEFI discovery and independently restore-tested EFI backup
- [ ] Target-bound UEFI approval/executor design and disposable-VM repair/rollback evidence
- [ ] Additional repair-engine designs, independent post-action evidence, and hardware tests
- [ ] Support, release, and production owner acceptance

Until those gates pass, the accurate label is **Enterprise Technical Preview — VM verified, physical validation open**.
