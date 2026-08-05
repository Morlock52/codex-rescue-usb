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
| VM | 4 vCPU, 8 GB RAM, QEMU Guest Agent, standard-user auto-login |
| Installed Codex package | `OpenAI.Codex` 26.730.8199.0, AppX status `Ok` |
| Installed ChatGPT package | `OpenAI.ChatGPT-Desktop` 1.2026.190.0 |
| Launch contract | Package manifest registers the `codex:` protocol; the desktop shortcut now invokes `explorer.exe codex:` |
| Account state | Codex desktop opened in an already signed-in standard-user session |
| Project state | `C:\Users\morlock\Documents\CodexRescue` selected as the visible project root |
| Voice UI | Microphone and Voice controls visible in the Codex project window |
| Audio runtime | No Windows sound device or audio-input endpoint exists in the Proxmox/noVNC VM; spoken Voice is not validated |
| Live launcher audit | Package/protocol/workspace present; network consent false; recovery material disallowed; automatic evidence import false |

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

## Operator workflow

1. Complete the offline WinPE stage first. Never give Codex a BitLocker recovery password or external recovery-key file.
2. Review the evidence package offline. Copy only an operator-redacted summary into the full-Windows workspace; do not attach the raw package by default.
3. Boot a maintained full-Windows environment and sign in as the standard recovery operator.
4. Stage this repository at `Documents\CodexRescue`.
5. Run the launcher in audit-only mode. Resolve a missing package, project, protocol, or audio-input state before continuing.
6. Run the interactive launcher and type the exact network-consent phrase.
7. In Codex, press `Ctrl+O` and select `Documents\CodexRescue`.
8. Review the app’s access setting. Use the least access needed. Do not use `Full access` against an unreviewed recovered drive.
9. If Voice is needed, confirm a trusted microphone endpoint, grant Windows microphone permission deliberately, and make sure no recovery material is visible or spoken.
10. Use Codex to analyze redacted evidence and prepare a proposal. Any disk-changing action requires its own exact target, rollback, approval, and independent verification.

## Remaining acceptance gates

- Run one spoken Voice session through a trusted microphone endpoint without exposing recovery material.
- Prove explicit network-disable and network-enable transitions in the full-Windows recovery environment.
- Add a redacted evidence-summary handoff that never imports the raw package automatically.
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
