# Full-Windows Codex recovery workspace

## Decision

Use a supported two-stage recovery flow:

1. Boot the Codex Rescue WinPE image for offline inventory, evidence collection, and separately authorized BitLocker recovery.
2. Start Codex only after booting a maintained full-Windows environment, obtaining explicit network consent, and selecting the staged `CodexRescue` project.

Codex does not run inside the WinPE image. Microsoft describes WinPE as a deployment and recovery environment rather than a general-purpose operating system, and its current customization guidance says WinPE supports only legacy applications. The OpenAI Codex desktop app is a modern Store-packaged full-Windows application.

A single supported “Windows and Codex running entirely from the USB” image is not the release baseline. Microsoft removed Windows To Go in Windows 10 version 2004 and later because it could not support feature updates and depended on USB hardware no longer supported by many OEMs. Native-boot VHDX remains a possible lab research path, but it is not evidence of a supported portable Windows/Codex release and has its own BitLocker constraints.

## Current VM evidence

The full-Windows workspace was inspected on August 5, 2026 in the dedicated Proxmox Windows 11 build VM:

| Property | Verified value |
| --- | --- |
| VM | 4 vCPU, 10 GB fixed RAM, QEMU Guest Agent, standard-user auto-login, on-host auto-start, ordered startup/shutdown, deletion protection |
| Installed Codex package | `OpenAI.Codex` 26.730.8199.0, AppX status `Ok` |
| Installed ChatGPT package | `OpenAI.ChatGPT-Desktop` 1.2026.190.0 |
| Launch contract | Package manifest registers the `codex:` protocol; the desktop shortcut now invokes `explorer.exe codex:` |
| Account state | Codex desktop opened in an already signed-in standard-user session |
| Project state | `C:\Users\morlock\Documents\CodexRescue` selected as the visible project root |
| Voice UI | Microphone and Voice controls visible in the Codex project window |
| Audio runtime | No Windows sound device or audio-input endpoint exists in the Proxmox/noVNC VM; spoken Voice is not validated |
| Live launcher audit | Package/protocol/workspace present; network consent false; recovery material disallowed; automatic evidence import false |
| Network gate | Exact interface 6 changed from Up/1 Gbps to Disabled/0 bps, remained manageable through QEMU Guest Agent, and later returned from cold-boot `Not Present` to Up/1 Gbps with the matching enable token |
| Offline-at-startup | SYSTEM startup task completed with result 0 after the corrected cold-boot edge test; standard-user auto-logon and QEMU Guest Agent remained available while interface 6 settled at Disabled/0 bps |
| Redacted handoff | Real alpha.7 and alpha.9 package integrity verified; each aggregate summary contained one BitLocker status block and no raw network, disk, volume, user-path, or recovery material |

The real screenshot in the README is cropped only to remove unrelated thread names and the signed-in account name. It shows the actual `CodexRescue` project and current desktop controls. Its visible `Full access` state belongs to the trusted disposable build VM and is not the approved physical-recovery default.

## Guarded launcher

`scripts/Open-CodexRecoveryWorkspace.ps1` performs a non-secret readiness audit and starts the supported Windows app only after the operator types:

```text
START CODEX RECOVERY WORKSPACE
```

The launcher:

- refuses WinPE and a missing or incorrect project root;
- requires the installed `OpenAI.Codex` package and registered `codex:` protocol;
- reports the exact installed package version and audio-input state;
- performs an all-users package inventory only in audit-only mode;
- never searches for, imports, copies, logs, or transmits recovery material;
- never imports the evidence package automatically;
- warns that networked Codex and Voice require separate consent; and
- instructs the operator to press `Ctrl+O` and select the exact staged project after launch.

Audit without launching or granting network consent:

```powershell
.\scripts\Open-CodexRecoveryWorkspace.ps1 -AuditOnly
```

Interactive launch:

```powershell
.\scripts\Open-CodexRecoveryWorkspace.ps1
```

The double-click wrapper is `scripts\Open-CodexRecoveryWorkspace.cmd`.

## Explicit network gate

`scripts/Set-CodexRecoveryNetwork.ps1` audits hidden and visible hardware interfaces without changing them. This is necessary because Windows can report a cold-boot-disabled adapter as `Not Present` and omit it from `Get-NetAdapter -Physical`. Enable and Disable require administrator rights, one exact interface index, and an action-specific token. The command filters out virtual interfaces, never changes every adapter implicitly, and makes no network request itself.

Audit first:

```powershell
.\scripts\Set-CodexRecoveryNetwork.ps1 -Action Audit
```

For the verified VM, the audit identified one physical adapter at interface index 6. The exact offline and online transitions were:

```powershell
.\scripts\Set-CodexRecoveryNetwork.ps1 `
  -Action Disable `
  -InterfaceIndex 6 `
  -ConfirmationToken DISABLE-CODEX-RECOVERY-NETWORK-6

.\scripts\Set-CodexRecoveryNetwork.ps1 `
  -Action Enable `
  -InterfaceIndex 6 `
  -ConfirmationToken ENABLE-CODEX-RECOVERY-NETWORK-6
```

The disable result reported `Status: Disabled`, `NetworkEnabled: False`, and 0-bps link speed. QEMU Guest Agent remained available because it is an out-of-band virtual-machine control channel rather than the disabled guest network. The first enable process completed but Proxmox timed out while polling its status; an independent query found the exact adapter Up at 1 Gbps, and an idempotent rerun returned a clean `NetworkEnabled: True` result. This proves the explicit transition in the disposable VM, not an offline-at-boot policy on physical hardware.

## Offline-at-startup policy

Audit, then install the policy against the same exact interface:

```powershell
.\scripts\Set-CodexRecoveryOfflineStartup.ps1 -Action Audit
.\scripts\Set-CodexRecoveryOfflineStartup.ps1 `
  -Action Install `
  -InterfaceIndex 6 `
  -ConfirmationToken INSTALL-CODEX-RECOVERY-OFFLINE-BOOT-6
```

The installer registers `Codex Rescue Offline Startup` as a SYSTEM startup task and writes its single-adapter policy under a ProgramData directory whose ACL grants full control only to SYSTEM and Administrators and read/execute to Users. Installation itself does not change the live adapter.

The task first passed a manual Task Scheduler run with result 0 and changed interface 6 to Disabled/0 bps. A later cold start exposed that `Get-NetAdapter -Physical` omitted the already-disabled adapter and caused a result-1 policy run. The corrected policy enumerates hidden hardware interfaces and treats both `Disabled` and `Not Present` as offline. The final policy reboot independently verified the repaired startup behavior: Windows was running, the standard user auto-logged in, QEMU Guest Agent answered out of band, the task settled to Ready with result 0, and interface 6 was discoverable at Disabled/0 bps. The VM had 7.93 GiB visible memory and 5.19 GiB free at the then-current 8 GB allocation. A later sizing cycle rejected 12 GB because it left only about 2.8 GiB available on the shared Proxmox host. The accepted 10 GB cold boot left about 5.65 GiB host-available memory; Windows reported 9.93 GiB visible and 7.61 GiB free, and the offline task again settled to Ready with result 0. This proves the default-offline policy and current sizing in the dedicated VM, not on physical recovery hardware.

Rollback removes only the named task and generated policy file; it does not enable the adapter:

```powershell
.\scripts\Set-CodexRecoveryOfflineStartup.ps1 `
  -Action Remove `
  -InterfaceIndex 6 `
  -ConfirmationToken REMOVE-CODEX-RECOVERY-OFFLINE-BOOT-6
```

## Redacted evidence handoff

Create the summary outside the source package:

```powershell
.\scripts\New-CodexEvidenceSummary.ps1 `
  -EvidenceDirectory 'E:\CodexRescueEvidence' `
  -OutputPath "$env:USERPROFILE\Documents\CodexRescueSummary.md"
```

The generator accepts exactly the documented nine files, verifies the manifest and checksum list, refuses subdirectories and output inside the source package, and rejects `.bek` files or 48-digit recovery-password-shaped text. It emits only aggregate integrity and availability fields. Raw evidence is never copied and `AutomaticCodexImport` remains false.

The actual alpha.7 and alpha.9 evidence packages passed this gate: all package hashes were valid, the BitLocker command was available, one volume/status block was counted in each package, and privacy scans of both outputs found no private IP address, MAC address, volume letter, key-file suffix, or recovery-password pattern. The alpha.7 WinPE source clock differed from the independent host by four hours, which motivated the explicit alpha.9 manifest fields `ClockSource: WinPE system clock` and `ClockExternallyValidated: false`. The recorded source time must not be used as an incident timeline without an independent clock check.

## Operator workflow

1. Complete the offline WinPE stage first. Never give Codex a BitLocker recovery password or external recovery-key file.
2. Generate and review the aggregate summary offline. Never place the raw package in the full-Windows workspace by default.
3. Boot a maintained full-Windows environment and sign in as the standard recovery operator.
4. Stage this repository at `Documents\CodexRescue`.
5. Audit the offline-startup policy and network adapter. The normal pre-consent state is policy installed and adapter disabled.
6. Run the workspace launcher in audit-only mode. Resolve a missing package, project, protocol, or audio-input state before continuing.
7. When online assistance is needed, enable only the audited adapter with its exact token.
8. Run the interactive launcher and type the exact network-consent phrase.
9. In Codex, press `Ctrl+O` and select `Documents\CodexRescue`.
10. Review the app’s access setting. Use the least access needed. Do not use `Full access` against an unreviewed recovered drive.
11. If Voice is needed, confirm a trusted microphone endpoint, grant Windows microphone permission deliberately, and make sure no recovery material is visible or spoken.
12. Manually place only the reviewed summary in the workspace, then ask Codex to prepare a proposal. Any disk-changing action requires its own exact target, rollback, approval, and independent verification.

## Remaining acceptance gates

- Run one spoken Voice session through a trusted microphone endpoint without exposing recovery material.
- Perform one controlled, manual Codex review of the generated summary without raw-package import or recovery material.
- Configure and verify a least-privilege Codex access mode for the physical recovery workflow.
- Validate the workspace on disposable physical hardware.
- Decide whether a native-boot VHDX lab experiment is worth maintaining; do not label it a supported Windows To Go replacement.

## Current official references

- [Introducing the Codex app](https://openai.com/index/introducing-the-codex-app/) — OpenAI records Windows availability.
- [ChatGPT Work and Codex](https://help.openai.com/en/articles/20001275-chatgpt-work-and-codex) — OpenAI documents Codex and Voice in the Windows desktop app for eligible accounts.
- [WinPE: Create Apps](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-create-apps?view=windows-11) — Microsoft defines WinPE as a fixed-purpose deployment/recovery environment.
- [Customize Windows PE boot images](https://learn.microsoft.com/en-us/windows/deployment/customize-boot-image) — Microsoft states that WinPE supports legacy apps.
- [Windows To Go feature overview](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/deployment/windows-to-go/windows-to-go-overview) — Microsoft records removal in Windows 10 version 2004 and later.
- [Boot to a virtual hard disk](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/boot-to-vhd--native-boot--add-a-virtual-hard-disk-to-the-boot-menu?view=windows-11) — Microsoft documents native-boot VHDX as a separate full-Windows deployment technique.
