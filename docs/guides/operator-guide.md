# Operator guide

This guide describes the intended end-to-end technical-preview workflow. It separates offline evidence, authorized BitLocker handling, full-Windows diagnostics, Codex assistance, and optional cloud visibility. Complete only the stages that are necessary for the case.

## Before you begin

Use Codex Rescue USB only when you are authorized to inspect the target computer and its data. Maintain another recovery route for valuable systems. At this milestone:

- physical USB writing and boot are not yet acceptance-tested;
- production operating-system-volume recovery is not verified;
- the repair engine remains a fixture simulation;
- real-tenant Graph consent and data have not been acceptance-tested; and
- a spoken Voice session has not been verified in the project VM.

Never paste, photograph, record, commit, upload, or speak a BitLocker recovery password or external-key material into Codex, GitHub, a ticket, or this project’s evidence package.

## Workflow at a glance

1. Establish authorization and identify the target.
2. Boot WinPE offline.
3. Collect read-only evidence to a separate prepared destination.
4. Review evidence and select only the required recovery action.
5. If necessary, unlock one explicitly selected BitLocker volume locally.
6. Move to the maintained full-Windows workspace.
7. Run local read-only diagnostics and review the dashboard.
8. Generate and inspect a sanitized handoff artifact.
9. Start Codex with least privilege and explicit network consent.
10. Use optional Graph visibility only with an authorized technician identity.

## Stage 1: offline WinPE evidence

Boot the exact ISO that passed `scripts\Test-RescueIso.ps1`. Keep the test or target computer disconnected from the network. The startup banner must say that the image is read-only by default and that recovery keys must not be saved or given to Codex.

### Prepare a separate evidence drive

Do not use the rescue boot drive as the evidence destination. In normal Windows, inspect the intended second removable drive. Replace `E` only after matching its physical label and capacity:

```powershell
Get-Volume -DriveLetter E |
  Format-List DriveLetter, FileSystemLabel, DriveType, Size, SizeRemaining
```

Create an empty marker file without formatting or deleting the drive:

```powershell
New-Item -ItemType File -Path 'E:\CODEX_EVIDENCE.DEST' -Force
```

The WinPE collector accepts exactly one writable destination containing that marker. It excludes ordinary `C:` and WinPE `X:` from destination selection.

### Collect evidence

At the WinPE prompt:

```bat
X:\Rescue\Collect-RescueEvidence.cmd
```

The collector displays the selected volume label and serial. Type the exact displayed `COLLECT TO <drive>:` phrase only after physically checking the destination. It rescans immediately before writing and refuses:

- zero or multiple prepared destinations;
- a marker that is a directory instead of a file;
- a destination that changes after confirmation;
- an existing `CodexRescueEvidence` directory; or
- the internal system and WinPE RAM drives.

The ten-file package contains disk/volume inventory, BitLocker status, BCD enumeration, event-log index, DISM driver inventory, network configuration, redacted offline-Windows inventory, manifest, checksums, and a collection README. The raw text files can still contain device-specific information; keep the package under technician control.

### Verify the package

Before using the data, confirm:

1. `manifest.json` lists the expected schema and explicit unvalidated WinPE clock state.
2. `SHA256SUMS.txt` covers the diagnostic files and manifest.
3. Recomputed hashes match.
4. No unexpected file or subdirectory appears in the package.
5. The package contains no recovery-key file or recovery-password-shaped text.

Do not use the recorded WinPE time as trusted incident chronology until it has been independently validated.

## Optional authorized BitLocker handling

The current runtime proof covers disposable encrypted **data volumes** only. Do not generalize it to an operating-system volume or production data.

### External recovery key

Use only an owner-controlled, separately prepared key drive. Identify the encrypted target by volume label, capacity, and locked state—never by an assumed drive letter. For an explicitly verified `E:` target:

```bat
X:\Rescue\Unlock-BitLockerWithRecoveryKey.cmd E
```

The workflow requires the exact `UNLOCK E:` token, looks for one external key locally, rejects `C:` and `X:`, and does not display the key identity or contents. After access is no longer required, cold-restart and confirm the disposable test volume returns to locked state.

### Numerical recovery password

For an explicitly verified disposable `E:` target:

```powershell
powershell -ExecutionPolicy Bypass -File X:\Rescue\Unlock-BitLockerWithRecoveryPassword.ps1 `
  -TargetDrive E `
  -ConfirmationToken 'UNLOCK E:'
```

Type the 48-digit value only into the local masked prompt. Do not use redirection, clipboard automation, a screen recording, guest-agent execution, or Codex. The script validates the format, uses the local BitLocker WMI path, and clears its in-process secret value. Human masked entry is still an open acceptance gate.

## Stage 2: full-Windows local assessment

Use the maintained technician workspace, initially offline. From an elevated Windows PowerShell session in the repository root:

```powershell
New-Item -ItemType Directory -Path 'C:\Temp\CodexRescue' -Force
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Invoke-CodexRescueReadOnlyAssessment.ps1 `
  -DestinationPath 'C:\Temp\CodexRescue\Assessment-001' `
  -Confirm:$false
```

Choose a new destination every time. The exporter refuses to overwrite an existing folder or ZIP.

The detailed local folder includes device-specific JSON, HTML, and collection metadata. The separate `Assessment-001-sanitized.zip` contains only the sanitized JSON report, sanitized HTML report, and privacy declaration. “Sanitized” does not mean “automatically safe to share”; review it.

### Optional local inputs

Allowlisted online connectivity tests require a separate exact phrase:

```powershell
.\scripts\Invoke-CodexRescueReadOnlyAssessment.ps1 `
  -DestinationPath 'C:\Temp\CodexRescue\Assessment-002' `
  -IncludeOnlineNetworkTests `
  -OnlineTestConfirmationToken 'RUN CODEX RESCUE ONLINE TESTS' `
  -Confirm:$false
```

Privacy-sensitive raw management logs remain local and require their own phrase:

```powershell
.\scripts\Invoke-CodexRescueReadOnlyAssessment.ps1 `
  -DestinationPath 'C:\Temp\CodexRescue\Assessment-003' `
  -IncludeRawManagementLogs `
  -RawLogConfirmationToken 'INCLUDE RAW WINDOWS MANAGEMENT LOGS' `
  -Confirm:$false
```

Raw logs are excluded from the sanitized ZIP.

## Review the native dashboard

For a fresh local-only assessment with no export:

```powershell
.\scripts\Open-CodexRescueDashboard.ps1
```

To open an existing validated assessment and enable bounded artifact controls:

```powershell
.\scripts\Open-CodexRescueDashboard.ps1 `
  -AssessmentPath 'C:\Temp\CodexRescue\Assessment-001\DeviceInfo\CodexRescueAssessment.local.json' `
  -DetailedReportPath 'C:\Temp\CodexRescue\Assessment-001\Reports\CodexRescueReport.local.html' `
  -SanitizedZipPath 'C:\Temp\CodexRescue\Assessment-001-sanitized.zip'
```

The dashboard validates the schema and safety fields before rendering. It has no repair control and no automatic Codex upload. A `Failed` or `Warning` card is a finding to investigate; it is not authorization to act.

## Create a bounded Codex handoff

For WinPE evidence, create the aggregate summary **outside** the raw package:

```powershell
.\scripts\New-CodexEvidenceSummary.ps1 `
  -EvidenceDirectory 'E:\CodexRescueEvidence' `
  -OutputPath "$env:USERPROFILE\Documents\CodexRescueSummary.md"
```

The command verifies the package and excludes raw disk, network, BCD, driver, event, offline-Windows, and BitLocker text. It rejects external-key files, numerical-password patterns, subdirectories, and invalid privacy declarations. Review the output manually before use.

Audit the Codex workspace without opening the app:

```powershell
.\scripts\Open-CodexRecoveryWorkspace.ps1 -AuditOnly
```

Start the app interactively:

```powershell
.\scripts\Open-CodexRecoveryWorkspace.ps1
```

Type `START CODEX RECOVERY WORKSPACE` when prompted. Confirm the project root, installed package, registered protocol, audio state, and app access mode. Use the least access required. Open only the reviewed summary or sanitized report.

## Network consent

Audit first:

```powershell
.\scripts\Set-CodexRecoveryNetwork.ps1 -Action Audit
```

Replace `6` below only with the exact physical adapter index from the audit:

```powershell
.\scripts\Set-CodexRecoveryNetwork.ps1 `
  -Action Enable `
  -InterfaceIndex 6 `
  -ConfirmationToken ENABLE-CODEX-RECOVERY-NETWORK-6

.\scripts\Set-CodexRecoveryNetwork.ps1 `
  -Action Disable `
  -InterfaceIndex 6 `
  -ConfirmationToken DISABLE-CODEX-RECOVERY-NETWORK-6
```

The command does not guess the interface and does not select virtual adapters. Disable network access again after the bounded task.

## Optional read-only Microsoft Graph view

Graph access runs only in full Windows and uses a separate PowerShell process-scoped sign-in. It is not WinPE functionality and does not share an authentication token with Codex.

```powershell
Import-Module .\PowerShell\Modules\CodexRescue.Graph\CodexRescue.Graph.psd1 -Force
Test-CodexRescueGraphPrerequisite | Format-List

$connection = Connect-CodexRescueGraphReadOnly `
  -ConfirmationToken 'CONNECT CODEX RESCUE READ ONLY GRAPH'

$cloud = Get-CodexRescueCloudDeviceHealth
$cloud.Checks | Format-Table CheckName, Status, Outcome, Summary -AutoSize

Disconnect-CodexRescueGraphReadOnly
```

The module requests four delegated read-only scopes, allows five Microsoft Graph v1.0 endpoint shapes, uses `GET` only, and blocks BitLocker recovery-key value retrieval. Real tenant acceptance is pending; use only an appropriately authorized technician identity and review the consent screen.

## Physical-media handoff

### Windows readiness GUI

On a separate Windows computer intended to prepare a drive, connect only the intended blank USB and run:

```text
scripts\Open-PhysicalUsbReadinessGui.cmd
```

The GUI verifies the ISO hash and accepts exactly one online writable USB disk that Windows identifies as USB and not boot/system. It can save a no-write JSON plan after rechecking identity. It does **not** erase or write the device. The zero-device refusal path is VM-verified; the positive physical path remains open.

### macOS readiness CLI

On macOS, first run the audit without a plan path:

```bash
python3 scripts/physical_usb_readiness_macos.py \
  --iso /path/to/Codex-Rescue-ISO-v0.1.0-alpha.13-67E79C37.iso
```

The tool requires the verified alpha.13 SHA-256 by default and exactly one external, physical, writable USB whole disk. It displays the device identifier, model, optional serial, byte size, USB protocol, ISO identity, and a confirmation token bound to the device identifier, exact size, and ISO hash prefix. Physically match those fields before proceeding.

To save the no-write plan, rerun with a new JSON path on internal storage and the exact token printed by the first audit:

```bash
python3 scripts/physical_usb_readiness_macos.py \
  --iso /path/to/Codex-Rescue-ISO-v0.1.0-alpha.13-67E79C37.iso \
  --plan "$HOME/Documents/codex-rescue-physical-alpha.json" \
  --confirmation-token 'PLAN disk7 64023257088 67E79C370218'
```

The token above is an example only. Use the live value printed for the attached disk. Immediately before saving, the tool re-hashes the ISO, rediscovers exactly one eligible USB, rechecks the token, and verifies that the plan destination is on internal non-target storage. It opens the JSON path exclusively and refuses overwrite. The only write is that JSON plan; the USB is untouched and no writer is launched.

Writing a USB is destructive to the selected removable drive. Until the physical acceptance plan is complete, use this repository for lab evaluation only and keep the verified ISO in a separate disconnected test VM.
