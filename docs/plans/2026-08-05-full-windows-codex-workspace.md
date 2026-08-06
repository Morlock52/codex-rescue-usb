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
| VM | 4 vCPU, 12 GB fixed RAM, QEMU Guest Agent, standard-user auto-login, on-host auto-start, ordered startup/shutdown, deletion protection |
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

## Clean workspace-image build lab

The existing VM evidence above proves the diagnostic workspace and guarded Codex handoff. It is not the source for a portable image because it contains an established device identity, installed-app state, test history, and signed-in user state. A clean, disposable image-build VM was therefore created on August 5, 2026 with this bounded contract:

| Property | Lab value |
| --- | --- |
| Role | Build and validate a clean full-Windows technician-workspace image; no customer data |
| Compute | 4 vCPU, 12 GB fixed RAM, ballooning disabled |
| Storage | New 128 GB virtual SSD; no recovery target or customer disk attached |
| Firmware | OVMF UEFI, Microsoft Windows UEFI CA 2023 keys, TPM 2.0 |
| Installation media | Windows 11 Enterprise 25H2 evaluation ISO plus the signed VirtIO driver/tools ISO |
| Network | Hypervisor link down before first boot |
| Persistence | Deletion protection enabled; automatic host boot remains disabled until Windows, guest-agent recovery, and offline-startup behavior pass |

The selected host retained about 17 GB available before the 12 GB VM was started. The other Proxmox node retained only about 4.4 GB available and had exhausted swap, so no second Windows builder was started there. This is an observed lab-capacity decision, not a universal Windows requirement. The VM booted the official ISO and reached the Microsoft license screen. License acceptance and installation remain pending and are not reported as completed.

### Source integrity

The lab source is `win11-enterprise-eval-25h2-en-us.iso`, 7,092,807,680 bytes, SHA-256:

```text
A61ADEAB895EF5A4DB436E0A7011C92A2FF17BB0357F58B13BBC4062E535E7B9
```

That exact value matches the English (United States), x64 Windows 11 Enterprise Evaluation 25H2 entry in Microsoft's published [Windows 11 hash PDF](https://aka.ms/Win11-Hash-PDF). The [Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise) describes the image as a 90-day evaluation for IT professionals. A production build must use organization-approved Windows installation media and licensing.

### Image-build acceptance contract

1. Install the clean evaluation OS with the virtual network cable disconnected.
2. Enter Windows Audit Mode without creating or embedding an operator password in source control.
3. Install the signed QEMU Guest Agent and prove automatic start plus restart recovery before relying on out-of-band commands.
4. Inventory the clean OS before adding tools; preserve the result as private lab evidence.
5. Enable the network only for exact, logged vendor or package-repository installations, then return it offline.
6. Install only approved technician tools and project source; never bake an organizational sign-in, Codex session, tenant token, BitLocker key, or customer evidence into the image.
7. Run local tests, PowerShell parser checks, privacy scans, dashboard smoke tests, and an offline reboot test.
8. Generalize with Sysprep from the supported interactive Audit Mode context, capture the image, and verify its hash.
9. Boot the captured image in a separate disposable VM with a new virtual identity; do not count a reboot of the build VM as independent boot evidence.
10. Exercise offline Windows detection, report/ZIP export, explicit networking, Codex sign-in, update servicing, and return-to-offline behavior before external-media research begins.

`scripts/Install-TechnicianWorkspaceGuestAgent.ps1` now implements the offline management bootstrap boundary for step 3. Audit searches only an exact media root or attached CD-ROM volumes, requires one 64-bit QEMU Guest Agent MSI, and validates its Authenticode status and Red Hat signer subject. Apply requires full Windows, elevation, the exact install phrase, a repeated signature check, `ShouldProcess`, `msiexec` with `/norestart`, and installed/running/automatic `QEMU-GA` verification. It makes no network request and cannot be authorized by fixture data. Native installation remains pending the Windows license and OS-install gates.

The first checked-in implementation for this contract is `scripts/Test-TechnicianWorkspacePrerequisite.ps1`. It is a read-only Windows baseline audit with eleven required checks and no network or installer path. Its fixture mode exists only for deterministic contract testing: even a fully passing fixture reports `LiveEvidence: false` and `ReadyForProvisioning: false`. A live result must pass all checks before provisioning begins; repository tests do not substitute for that VM result.

The second checked-in input is `config/technician-workspace-tools.json`, an allowlist rather than an installed-state claim. As of August 5, 2026 it pins Codex CLI `0.146.1` and its npm integrity, Microsoft Graph modules `2.39.0`, Microsoft.WinGet.Client `1.29.280`, WindowsAutoPilotIntune `5.7`, and PowerShellGet `2.2.5`. WinGet package versions are resolved only inside an approved maintenance window and must be written into the private build receipt. The generalized image contains no Codex or Microsoft sign-in state.

`scripts/Install-TechnicianWorkspaceToolchain.ps1` consumes that allowlist. Its default `Plan` mode is cross-platform, makes no changes and no network requests, and emits the exact bounded install plan. `Apply` requires full Windows, elevation, a passing live prerequisite result, the exact token `INSTALL CODEX RESCUE TOOLCHAIN`, explicit package-agreement approval, and PowerShell `ShouldProcess`. It verifies the pinned Codex npm integrity before installation, installs no cloud-write function, never runs a login command, and writes only a non-secret build receipt. This is checked-in contract evidence; native Apply and post-install verification remain pending.

`scripts/Test-TechnicianWorkspaceToolchain.ps1` is the corresponding read-only post-install gate. It audits the offline network and startup policy, staged project payload, required package IDs, exact module versions, exact Codex CLI version, authentication-artifact counts, sensitive credential environment variables, and receipt integrity/privacy. It makes no network request and no change. Only a passing live Windows result can set `ReadyForGeneralization`; deterministic fixtures cannot. Native execution remains pending installation and provisioning in the clean VM.

Microsoft documents that Sysprep `/generalize` removes machine-specific information before an image is moved to another computer. The capture and portable-media experiments therefore follow the current [Sysprep](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-command-line-options?view=windows-11), [capture/apply](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/capture-and-apply-windows-using-a-single-wim?view=windows-11), [native-boot VHDX](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/boot-to-vhd--native-boot--add-a-virtual-hard-disk-to-the-boot-menu?view=windows-11), and [BCDBoot](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/bcdboot-command-line-options-techref-di?view=windows-11) procedures. Passing those lab gates still does not make Windows To Go a supported product or prove a physical Codex Rescue USB.

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

The task first passed a manual Task Scheduler run with result 0 and changed interface 6 to Disabled/0 bps. A later cold start exposed that `Get-NetAdapter -Physical` omitted the already-disabled adapter and caused a result-1 policy run. The corrected policy enumerates hidden hardware interfaces and treats both `Disabled` and `Not Present` as offline. The final policy reboot independently verified the repaired startup behavior: Windows was running, the standard user auto-logged in, QEMU Guest Agent answered out of band, the task settled to Ready with result 0, and interface 6 was discoverable at Disabled/0 bps. The VM had 7.93 GiB visible memory and 5.19 GiB free at the then-current 8 GB allocation. An early 12 GB trial under heavier concurrent host load was rejected. After VM 115 was stopped and host headroom was rechecked, VM 111 was accepted at 12 GB fixed RAM: Windows reported 12,220 MB usable and about 9.5 GB free after startup, while the host retained roughly 4-6 GiB available during the measured alpha.13 build intervals with no sustained swap movement. This proves the default-offline policy and current sizing in the dedicated VM, not on physical recovery hardware.

### Clone-specific offline-policy gate

A cloned build VM must be treated as a new network-policy target. VM 115 received a new virtual NIC identity and initially booted online even though its inherited scheduled-task history still showed result 0 from VM 111. The validated clone procedure is:

1. Audit the clone's current hidden hardware interfaces out of band.
2. Disable the exact clone adapter before staging source.
3. Reinstall the offline-at-startup task for the clone's audited interface index.
4. Cold boot the clone.
5. Require a fresh task result 0, `Disabled` or `Not Present`, 0 bps, and QEMU Guest Agent availability before proceeding.

The 25-GiB Proxmox node does not have comfortable headroom for two 12-GB builders under load, so only VM 111 or its isolated clone may run at one time.

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

The real alpha.9 summary then passed a bounded manual Codex review in the standard-user VM. Its SHA-256 matched before and after staging; no raw evidence or recovery material was copied into the workspace; Codex was changed to **Ask for approval**; and exactly one literal-path, read-only file command was approved. Codex reported verified integrity, schema v1, eight checksum entries covering seven diagnostic files and 21,407 bytes, the available diagnostic categories with network details withheld, the untrusted-clock caveat, and the next safe offline operator-review action. Networking was disabled after the review. A final QEMU Guest Agent audit verified 9.93 GiB visible RAM with 5.01 GiB free under the live Codex workload, interface 6 Disabled/0 bps, the startup task Ready with result 0, zero temporary automation tasks, the hash-matched summary, one Codex process, and QEMU Guest Agent running.

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
