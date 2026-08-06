# Verification evidence

This record summarizes the strongest current evidence without collapsing source tests, VM runtime, physical hardware, and production readiness into one claim.

## Current source verification

Fresh local verification on August 6, 2026:

```text
python3 -W error::ResourceWarning -m unittest discover -s tests -v
Ran 121 tests
OK
```

The suite covers fixture validation, safety contracts, approval binding, receipts, audit chaining, WinPE source and ISO-verifier behavior, evidence destination gates, BitLocker target/secret handling, full-Windows diagnostics, WPF schema enforcement, Graph scope/query/output restrictions, build-VM scripts, toolchain plans, and physical-readiness no-write behavior.

Automated tests do not prove a physical USB or production recovery.

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

## Physical USB readiness evidence

The GUI’s live **zero eligible USB disks** path ran in offline Windows VM 111 against the hash-matched alpha.13 ISO. It displayed the expected refusal and kept validation, physical-identity confirmation, and plan-save controls disabled.

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
- [ ] Repair-engine design, rollback, independent post-action evidence, and hardware test
- [ ] Support, release, and production owner acceptance

Until those gates pass, the accurate label is **Enterprise Technical Preview — VM verified, physical validation open**.
