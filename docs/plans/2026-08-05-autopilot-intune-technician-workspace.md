# Autopilot and Intune technician-workspace implementation plan

## Purpose

Evolve Codex Rescue USB from its verified WinPE emergency image and fixture console into a two-environment recovery workbench for authorized Windows 11, Windows Autopilot, Microsoft Intune, and Microsoft Entra troubleshooting. This plan records the implementation boundary as of August 5, 2026. A planned feature is not release evidence.

## Support boundary

The release architecture remains two-stage:

1. **WinPE emergency mode** is the supported offline recovery layer for disk inventory, guarded BitLocker recovery, offline Windows discovery, BCD inspection, DISM servicing, driver injection, file recovery, and Windows Setup.
2. **Full Windows 11 technician workspace** is the online assistance layer for normal Wi-Fi, captive portals, browser sign-in, Windows PowerShell 5.1, PowerShell 7, Codex, Microsoft Graph, Intune tooling, reporting, and the WPF dashboard.

Microsoft removed Windows To Go and documents limited application compatibility and general wireless constraints in WinPE. A bootable external Windows 11 VHDX or external-NVMe workspace therefore remains an experimental delivery option until licensing, update servicing, target-hardware compatibility, Secure Boot, driver coverage, activation, and physical boot are validated. The project must not relabel a booted build VM or WinPE image as that portable workspace.

Primary references:

- [Windows To Go overview and removal](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/deployment/windows-to-go/windows-to-go-overview)
- [WinPE optional components and wireless limitation](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-add-packages--optional-components-reference?view=windows-11)
- [Connect-MgGraph delegated authentication](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.authentication/connect-mggraph?view=graph-powershell-1.0)
- [Microsoft Graph PowerShell authentication commands](https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands?view=graph-powershell-1.0)
- [Codex app on Windows](https://openai.com/index/introducing-the-codex-app/)
- [Voice with Codex in the Windows desktop app](https://help.openai.com/en/articles/20001275-chatgpt-work-and-codex)

## Phase 1 — local read-only diagnostics

**Implementation status:** runtime-verified in Windows VM 111 on August 5, 2026 local time.

The `CodexRescue` module exposes 14 Phase 1 functions and ten diagnostic check groups. Defaults are intentionally strict:

- no repair commands;
- no cloud requests;
- no online connectivity tests;
- no raw Intune or Windows event-log export;
- no BitLocker recovery material;
- no credentials, tokens, certificate private material, or automatic Codex import;
- no overwrite of an existing evidence folder or ZIP.

The export has two privacy zones:

| Zone | Contents | Handling |
| --- | --- | --- |
| Detailed local folder | Device-specific JSON and HTML, manifest, optional consent-bound raw logs | Technician-controlled local review only |
| Sanitized escalation ZIP | Sanitized JSON, sanitized HTML, privacy declaration | Operator review before sharing or Codex use |

The sanitized ZIP is rejected if the structured result matches a BitLocker recovery-password, bearer-token, token assignment, private-key header, or `.bek` pattern. Privacy-sensitive fields are removed before the ZIP is created. These checks reduce risk but do not replace manual review.

### Verified evidence

- Windows PowerShell 5.1.26100.8875 imported 14 exported functions.
- The default assessment returned all ten required checks and passed its schema validator.
- It recorded zero repairs, zero cloud requests, zero online tests, zero raw management-log files, and no recovery or credential collection.
- The sanitized ZIP contained exactly three files and passed the independent harness pattern scan.
- The local suite passed 89 tests; every PowerShell file parsed; the module manifest validated.
- Two privacy-reviewed screenshots preserve the sanitized overview and all ten check cards from that real Windows report.

### Remaining Phase 1 work

- Exercise a disposable offline Windows installation fixture through the full-Windows module.
- Add optional raw-log runtime testing using synthetic or disposable management logs only.
- Sign the module and record publisher-chain verification in the enterprise phase.

## Phase 2 — technician dashboard and workspace image

### Verified WPF dashboard milestone

The native WPF dashboard is implemented with the same visual language as the Figma Rescue Console. Its checked-in script consumes only the module's structured assessment object and requires strict validation before rendering. It includes:

- overall health score and explicit `Not tested` states;
- local device and installed-Windows summary;
- Autopilot, Intune, Entra, certificate, BitLocker, TPM, update, network, driver, and event cards;
- a timeline and local audit trail;
- separate controls for the detailed local report and sanitized escalation ZIP;
- persistent offline/cloud state;
- no repair button until an allowlisted repair module and approval contract exist.

The implementation never scrapes formatted console text. WPF binds bounded display strings as text instead of interpreting them as XAML, and the separate HTML-report path retains its existing encode-every-value rule. Figma remains the interaction and layout specification, not runtime evidence.

The `CODEX_DASH_R2` source-transfer image was validated in Windows PowerShell 5.1 on VM 111. The harness passed with exactly ten cards, three local audit entries, no repair controls, no automatic Codex upload, cloud disabled, and separately enabled controls for existing local HTML and sanitized ZIP artifacts. The real WPF XAML loaded and two runtime screenshots were captured. This proves the dashboard milestone only; the transfer image is not bootable media.

### Remaining Phase 2 workspace-image gates

The workspace image must be validated independently from the existing build VM. Required gates are:

1. boots from a dedicated virtual disk or external-media representation;
2. preserves UEFI Secure Boot expectations;
3. detects Ethernet and Wi-Fi hardware without silently enabling a network;
4. allows explicit browser-based Codex sign-in without storing tokens in the published image;
5. runs PowerShell 5.1, PowerShell 7, the signed module, Codex, and the WPF dashboard;
6. detects a separate offline Windows installation;
7. survives reboot and an update-servicing cycle;
8. leaves the Proxmox guest agent and recovery access available.

### Clean image-build lab status

On August 5, 2026, the separate image-build lab was created and started with 4 vCPU, 12 GB fixed RAM, a new 128 GB virtual SSD, UEFI with Microsoft Windows UEFI CA 2023 keys, TPM 2.0, deletion protection, and its virtual network cable disconnected. The official Windows 11 Enterprise 25H2 evaluation ISO booted and reached Microsoft's license screen. Windows installation, Audit Mode, tool provisioning, generalization, capture, separate-VM boot, and external-media validation remain pending; none is implied by the VM's creation or ISO boot.

The source ISO is 7,092,807,680 bytes with SHA-256 `A61ADEAB895EF5A4DB436E0A7011C92A2FF17BB0357F58B13BBC4062E535E7B9`, matching Microsoft's published [Windows 11 hash PDF](https://aka.ms/Win11-Hash-PDF). Microsoft describes the image as a 90-day [Enterprise evaluation](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise), so production use remains an organization-licensing gate.

`scripts/Test-TechnicianWorkspacePrerequisite.ps1` now implements the first image-build gate as a bounded, read-only eleven-check audit. It requires 12 GiB RAM, 64 GiB free system-drive space, UEFI, Secure Boot, TPM 2.0, offline hardware adapters, and a running automatic QEMU Guest Agent in addition to the Windows platform checks. Its deterministic fixture path never counts as live readiness. Native execution in the new Windows VM remains pending OS installation and guest-agent setup.

## Phase 3 — delegated Microsoft Graph visibility

**Implementation status:** module contract and native Windows mock harness complete; live tenant authentication and tenant-side results pending.

`CodexRescue.Graph` implements read-only, opt-in Graph access with four exported functions. Its exact operator token opens delegated device-code or interactive browser authentication through `Connect-MgGraph -ContextScope Process`. It rejects app-only identity, missing or expanded scopes, write scopes, persistent context, Graph beta, non-GET methods, unapproved endpoint shapes, recovery-key item paths, and `select=key`. No app secret, certificate credential, supplied token, access token, or refresh token belongs in the repository, image, report, or escalation ZIP.

The first cloud functions may query only the signed-in technician's authorized view of:

- Microsoft Entra device registration and authentication state;
- Intune managed-device enrollment, compliance, sync, and policy summaries;
- Autopilot registration and profile assignment;
- group membership needed to explain assignment;
- BitLocker escrow **availability only**, not recovery-key material.

Every report distinguishes `Not tested`, `Permission denied`, `Not found`, `Unavailable`, and actual unhealthy state. The current result schema is stricter than the earlier plan: it includes no local or cloud identifier, raw response, or raw exception. The BitLocker list operation uses only its documented device filter; it discards the API's object identifiers and retains only bounded availability count, backup time, and volume type.

No delete, wipe, retire, Fresh Start, Autopilot Reset, group change, owner change, or recovery-key retrieval belongs in the read-only cloud phase.

### Verified implementation evidence

- Required delegated scopes are fixed to `Device.Read.All`, `DeviceManagementManagedDevices.Read.All`, `DeviceManagementServiceConfig.Read.All`, and `BitlockerKey.ReadBasic.All`.
- `CODEX_GRAPH_R3` is a 921,600-byte read-only source-transfer image with SHA-256 `0E51E093BE9FEB3B27C78504CF4A5CB6048DA543337153B134EAB337AE836E1B`; it is not bootable media.
- Windows VM 111 had Microsoft.Graph.Authentication 2.39.0 installed with a manifest-valid module and then returned to its disabled-network state.
- Windows PowerShell 5.1.26100.8875 passed the deterministic harness with four exports, five mocked GET requests, five checks, zero writes, no returned identifiers, no recovery-key material, a distinct permission-denied outcome, and key-value, unsupported-query, and unrelated-scope guards passing.
- The local suite passes 102 tests and every PowerShell file parses.

These results do not constitute a live Graph call. The next Phase 3 acceptance test requires an operator-attended sign-in to a disposable or expressly authorized tenant, review of the exact requested scopes, redacted result inspection, disconnect verification, and immediate return to the offline-default network state.

## Phase 4 — approval-bound repair engine

Repairs are separate exported functions with `SupportsShouldProcess`, `ConfirmImpact`, parameter validation, an allowlist, target fingerprint, rollback or recovery prerequisite, exact technician confirmation, before/after evidence, and a typed receipt. High-risk operations require additional gates from the goal specification. Codex may recommend or review a plan; it does not bypass the broker or execute an unrestricted shell.

Initial disposable-fixture candidates are:

- DNS, Winsock, time, and one-selected-adapter repair;
- Windows Update cache/service repair;
- Intune Management Extension service and installation repair;
- Company Portal package repair;
- offline BCD and DISM repair;
- driver injection into a disposable offline Windows image.

Microsoft Entra leave/rejoin, certificate deletion, TPM clear, BitLocker protector changes, re-enrollment, wipe, retire, Fresh Start, Autopilot Reset, partitioning, formatting, and reinstallation remain high-impact operations with their own acceptance tests and explicit owner approval.

## Phase 5 — Codex orchestration

Codex receives only an operator-selected sanitized package. The default prompt must request root-cause analysis, supporting evidence, safest repair sequence, risks, compatible commands, validation after each step, and the affected boundary. Each proposed action is shown in the dashboard and remains inert until the technician approves the exact target and parameters.

Success requires:

- deterministic diagnostic JSON schema;
- sanitized context manifest and hash;
- command allowlist and signer verification;
- one-time approval bound to a proposal digest;
- repair receipt plus independent post-action validation;
- final HTML report and escalation notes;
- no credential, token, or recovery-key persistence.

## Phase 6 — dual-boot packaging and physical validation

The final boot menu is planned to expose:

1. Windows 11 Technician Workspace
2. WinPE Emergency Repair
3. Windows 11 Setup
4. Hardware Diagnostics
5. Memory Test
6. Restart
7. Shut Down

Release evidence must include both VM boot paths, a disposable offline Windows target, network and authentication gates, report export, cold reboots, update servicing, USB identity and write-plan validation, physical UEFI boot on disposable hardware, driver compatibility, and owner approval. Microsoft binaries and licensed commercial tools are not redistributed through GitHub; the repository publishes source, reproducible instructions, hashes, redacted screenshots, and validation records.

## Immediate next acceptance gates

1. **Complete:** publish the Phase 1 module, harness, README instructions, and plan with verified VM evidence.
2. **Complete:** add the Figma technician dashboard design with explicit concept labeling.
3. **Complete:** implement and VM-validate the WPF read-only dashboard against structured module objects.
4. **Implementation complete; live acceptance pending:** delegated, process-scoped, read-only Graph authentication behind an explicit online-consent gate.
5. **In progress:** build and boot-test a separately maintained full-Windows workspace image before describing it as portable media. The clean VM and source-integrity gates pass; OS installation and every image/portable-media gate remain open.
6. Integrate and boot-test the two-environment menu in a disposable UEFI VM.
7. Perform the final physical USB workflow only on an explicitly selected blank device and disposable test PC.
