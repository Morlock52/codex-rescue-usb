# Architecture

Codex Rescue USB uses two operating environments because offline recovery and an AI-assisted desktop have different compatibility, network, and trust requirements.

The new Codex Rescue Orchestrator is the standard-user control plane for both environments. It does not move Codex into WinPE and does not turn the Git checkout into privileged runtime code.

## System context

```text
Target Windows PC
  |
  | boots exact verified ISO
  v
WinPE recovery stage (offline, read-only first)
  |-- disk / volume / BCD / driver / event-index evidence
  |-- redacted offline-Windows inventory
  |-- local, guarded BitLocker operations on one explicit target
  |
  | writes only after exact destination confirmation
  v
Separate evidence drive
  |-- raw package retained by technician
  |-- manifest + SHA-256 list
  |
  | operator verifies and creates bounded summary
  v
Maintained full-Windows workspace (offline at startup)
  |-- local PowerShell diagnostics
  |-- native WPF dashboard
  |-- optional process-scoped read-only Graph sign-in
  |-- Codex desktop after explicit launch/network consent
  v
Reviewed recommendation or proposed action
  |
  v
Operator approval remains separate from execution
```

## Orchestrator process boundary

```text
Standard-user WPF application
  |-- local read-only audit (zero network by default)
  |-- versioned plan and workflow state
  |-- signed online/offline release verification
  |-- Figma-derived Guided and Expert interface
  |
  | one typed, unexpired, target-bound plan + UAC
  v
Per-action elevated Broker
  |-- derives package version and asset-catalog digest itself
  |-- validates packaged path, hash, Authenticode signer, and schema
  |-- maps operation to one fixed signed asset
  |-- provides typed arguments; no shell or arbitrary executable
  v
Built-in Windows tooling or fixed signed PowerShell asset
  |
  | normalized result and bounded before/after evidence
  v
ActionReceiptV1 + independent verification
```

There is no permanent privileged service. Release checks and the Proxmox connector run in the standard-user process during an explicit maintenance/session window. Credentials are not part of `ProxmoxProfileV1`; a token is session-only by default.

## Why WinPE is not the Codex desktop environment

Microsoft defines Windows PE as a fixed-purpose deployment and recovery environment with limited application compatibility. OpenAI supports the Codex desktop experience on full Windows. Microsoft also removed Windows To Go beginning with Windows 10 version 2004. The project therefore does not force a general desktop product into WinPE or label an unsupported Windows To Go image as its baseline.

WinPE supplies the minimal offline recovery layer. A separately maintained full-Windows workspace supplies the supported desktop, authentication, audio, and development-tool environment.

## Trust boundaries

### Recovery media

The ISO is treated as immutable after verification. Its identity is the source commit, byte size, SHA-256, boot payload, embedded-source hashes, and package list. Rebuilding creates a new artifact and requires a new verification record.

### Target computer

The target is untrusted input. Volume labels, drive letters, BCD output, event metadata, registry hives, and device state can be missing, corrupt, or misleading. Scripts length-bound and structure-check data, avoid evaluating target content, and fail closed on ambiguity.

### Recovery material

BitLocker recovery material belongs to the owner-controlled local recovery flow. It is never an evidence field, Codex prompt, Graph result, GitHub artifact, or project log. External-key and numerical-password paths are separate and require an explicit target.

### Evidence destination

The destination must be a separate, operator-prepared writable volume with an exact marker file. Discovery excludes ordinary `C:` and WinPE `X:`, requires exactly one candidate, rescans after confirmation, and refuses overwrite.

### Full-Windows workspace

The workspace starts offline and treats network enablement as a privileged transition. The project’s adapter gate binds the action to one audited hardware interface and an exact token. QEMU Guest Agent management and guest network state are separate controls.

### Codex

Codex receives only operator-selected context. The approved handoff is a reviewed sanitized report or integrity-checked aggregate summary, not raw evidence. App access mode and every proposed command remain subject to operator review.

### Microsoft Graph

The Graph module is a separate optional component. It uses delegated interactive authentication, process-scoped context, four fixed read-only scopes, five allowed v1.0 query shapes, and `GET` only. It returns bounded outcomes without raw responses, identifiers, tokens, or recovery-key values.

## Core components

| Component | Location | Responsibility |
| --- | --- | --- |
| Fixture console | `src/codex_rescue`, `web`, `fixtures` | Demonstrate diagnosis, approval, typed receipts, verification, and audit without host actions |
| WinPE payload | `winpe` | Offline evidence, destination gate, manifest, redacted inventory, guarded BitLocker helpers |
| ISO pipeline | `scripts/Build-RescueIso.ps1`, `scripts/Test-RescueIso.ps1` | Build, inject, hash, and verify the exact ISO |
| Local diagnostic module | `PowerShell/Modules/CodexRescue` | Ten read-only Windows check groups and validated exports |
| Native dashboard | `PowerShell/Dashboard`, `scripts/Open-CodexRescueDashboard.ps1` | Validate and render local findings and bounded artifacts |
| Graph module | `PowerShell/Modules/CodexRescue.Graph` | Optional authorized read-only cloud visibility |
| Codex handoff | `scripts/New-CodexEvidenceSummary.ps1`, workspace/network scripts | Validate evidence, create bounded summary, launch offline-first workspace |
| Physical readiness | `scripts/Open-PhysicalUsbReadinessGui.ps1` | Verify ISO/USB identity and save a no-write plan |
| Versioned contracts | `orchestrator/src/CodexRescue.Contracts` | Plans, receipts, checkpoints, releases, Proxmox profiles, telemetry |
| Orchestrator UI | `orchestrator/src/CodexRescue.Orchestrator` | Standard-user WPF state machine, audit, updates, connector, receipts |
| Elevated broker | `orchestrator/src/CodexRescue.Broker` | Typed allowlist and packaged signed-asset enforcement |
| Media matrix | `config/media-build-matrix.json`, `scripts/Build-CodexRescueMediaMatrix.ps1` | Four architecture/trust-path builds with servicing receipts |
| Guarded USB writer | `scripts/Write-CodexRescueUsb.ps1` | Target-bound GPT/FAT32 write and complete readback |
| UEFI repair | `scripts/Invoke-CodexRescueUefiRepair.ps1` | Backup, minimal BCDBoot, verify, and rollback |
| BitLocker salvage | `scripts/Invoke-CodexRescueBitLockerSalvage.ps1` | Owner-supplied `.bek` salvage to a separate disposable output |
| Signed packaging | `orchestrator/packaging`, `.github/workflows/orchestrator-release.yml` | MSIX/App Installer, Azure signing, SBOM, manifest, provenance |

## Evidence states

The project uses seven non-interchangeable evidence labels:

1. **Figma design** — intended state and visual behavior; no runtime claim.
2. **Fixture verified** — deterministic simulated data and no host effects.
3. **Source/test verified** — static contracts and automated tests pass.
4. **Package verified** — exact signed installer and update path pass on a clean Windows VM.
5. **VM runtime verified** — exact source or artifact ran in a named disposable VM.
6. **Physical hardware verified** — exact artifact ran on recorded disposable hardware.
7. **Production accepted** — documented support, operational, security, and owner acceptance criteria pass.

Moving to a later label requires new evidence. A successful test cannot promote itself across these boundaries.

## Design principles

- Collect only what the current decision requires.
- Keep raw and sanitized artifacts separate.
- Make state-changing authority explicit, narrow, and one-use.
- Recheck targets immediately before effects.
- Preserve rollback or cold-relock evidence where applicable.
- Never infer cloud truth from local absence.
- Never infer physical compatibility from VM success.
- Treat AI analysis as advice, not authorization.
