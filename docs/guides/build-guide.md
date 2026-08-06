# Build and validate the WinPE ISO

This guide creates the WinPE deliverable in a dedicated Windows build environment, verifies its contents, and boot-tests the exact artifact in a separate disposable VM. The primary output in a Proxmox build VM is an ISO, not direct USB media.

## Supported build pattern

Use three separate roles:

| Role | Purpose | Network state |
| --- | --- | --- |
| Windows build VM | ADK servicing, source staging, ISO creation | Online only for bounded maintenance; offline during normal builds |
| Disposable UEFI test VM | Boot and functional validation | Disconnected |
| Physical preparation workstation | Later USB identity check and writer operation | Not yet acceptance-verified |

Do not use the build VM as proof that the test VM boots, and do not use VM boot as proof of physical USB compatibility.

## Build VM sizing

Validated project recommendation:

- 4 vCPU
- 12 GB fixed RAM, ballooning disabled
- 128 GB system disk
- at least 30 GB free during repeated builds
- UEFI and TPM for the full-Windows workspace
- QEMU Guest Agent with automatic startup

Eight GB is the validated build-only floor for the existing alpha artifacts. Twelve GB is recommended when ADK, Codex, editors, Python, Node.js, PowerShell, and Git tools share the VM. Run one builder at a time on a memory-constrained Proxmox node.

The project’s Windows VM maintenance helper records non-secret OS, capacity, ADK, and tool-discovery evidence:

```text
scripts\Repair-BuildVm.cmd
```

It does not collect passwords, tokens, BitLocker material, browser data, or user documents.

## Install official Microsoft prerequisites

Install:

1. Windows ADK **Deployment Tools** for the intended x64 Windows recovery baseline.
2. The matching Windows PE add-on.
3. The latest applicable ADK servicing update.

Microsoft’s release and servicing guidance is time-sensitive. Check the official [ADK downloads](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) and [ADK servicing updates](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-servicing) immediately before building.

The alpha.13 evidence in this repository used ADK `10.1.26100.2454` with the later applicable `KB5101684` servicing package. Microsoft currently documents at least `KB5079391` for that ADK line. Historical validation identifies what was tested; it does not instruct an operator to skip a newer applicable security update.

The checked-in servicing helper downloads only from Microsoft-owned hosts, requires a valid Microsoft Authenticode signature, and writes package hashes and results under `C:\CodexRescueVmAudit\ADK-Servicing`:

```powershell
.\scripts\Install-AdkServicingUpdate.ps1 -Confirm:$false
```

## Stage repository source in Proxmox

When the checkout is mounted as a read-only virtual CD, open the disc and run:

```text
scripts\Stage-RescueSource.cmd
```

The launcher copies the source to `Documents\CodexRescue` and refuses to overwrite an existing destination. Compare the staged revision with the intended Git commit before building.

## Build the ISO

Open an elevated Windows PowerShell session in the staged repository:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Build-RescueIso.ps1 -Force
```

Interactive alternatives:

- `scripts\Build-RescueIso.cmd` — visible completion prompt
- `scripts\Build-RescueIso-Unattended.cmd` — durable log and exit-code output for guest-agent automation

The builder:

1. creates a fresh amd64 WinPE workspace;
2. mounts `boot.wim`;
3. adds WinPE-WMI, SecureStartup, NetFx, Scripting, and PowerShell in dependency order;
4. injects the checked-in evidence, manifest, offline-inventory, and BitLocker scripts;
5. normalizes embedded batch files for Windows command processing;
6. creates a BIOS/UEFI ISO with Microsoft’s `/BOOTEX` path; and
7. runs `scripts\Test-RescueIso.ps1` automatically.

Expected outputs:

```text
dist\Codex-Rescue-ISO.iso
dist\Codex-Rescue-ISO.iso.verification.json
```

## Read the verification report

The report must identify:

- exact ISO path, byte size, and SHA-256;
- BIOS and UEFI boot payloads;
- required WinPE optional components;
- read-only `boot.wim` inspection result;
- each embedded project file and its checked-in source hash; and
- the expected normalized hash relationship for `.cmd` files.

A failed verifier removes an older success report for the same output path. Do not preserve or present stale JSON as proof for a rebuilt ISO.

## Boot-test the exact artifact

Create a disposable test VM with:

- 2 vCPU;
- 2 GB RAM;
- UEFI with Windows UEFI CA 2023 keys;
- networking disconnected at the virtual NIC;
- no production disks; and
- the exact verified ISO attached as virtual DVD.

Record the ISO SHA before attachment. Boot it and require the recovery banner and `X:\Windows\System32>` prompt. Confirm the banner states:

- read-only default;
- prepared-destination requirement;
- recovery keys must not be saved or given to Codex; and
- exact commands for evidence and authorized unlock flows.

This proves VM bootability for the recorded artifact only.

## Functional evidence test

Attach a separate disposable evidence disk containing an empty `CODEX_EVIDENCE.DEST` file. Run:

```bat
X:\Rescue\Collect-RescueEvidence.cmd
```

Require the expected destination identity and exact confirmation phrase. After collection:

1. detach the evidence disk;
2. inspect the ten-file package in a trusted environment;
3. validate manifest and checksum coverage;
4. confirm the clock is labeled unvalidated;
5. run secret-pattern checks; and
6. confirm a repeated collection refuses to overwrite the existing directory.

BitLocker functional testing requires the separate disposable-fixture procedure in the [operator guide](operator-guide.md). Never use customer data for build acceptance.

## Full-Windows workspace toolchain

The project keeps the supported Codex experience in a maintained full-Windows workspace. The bounded build-VM toolchain installer is:

```powershell
.\scripts\Install-BuildVmToolchain.ps1 -Confirm:$false
```

It installs or updates Git, GitHub CLI, PowerShell 7, and Python from signed WinGet sources. Existing Node.js, VS Code, Cursor, or Codex installations are audited rather than blindly replaced. The repository does not guess what an ambiguous `roc` or `rock` CLI name means.

For the clean portable-workspace image path, use the allowlisted plan and verification scripts:

```powershell
.\scripts\Test-TechnicianWorkspacePrerequisite.ps1
.\scripts\Install-TechnicianWorkspaceToolchain.ps1
.\scripts\Test-TechnicianWorkspaceToolchain.ps1
```

The installer has legal, offline, elevation, exact-confirmation, signed-package, and version gates. A deterministic fixture can test its contract but cannot establish live image readiness. Microsoft license acceptance and a clean full-Windows image remain operator-attended requirements.

## Physical USB remains a release gate

The Windows readiness GUI can validate one selected USB identity and save a plan that explicitly records `WritePerformed: false`. The macOS CLI provides the equivalent hash, exactly-one-external-USB, target-bound confirmation, internal-plan-destination, and no-overwrite gates:

```bash
python3 scripts/physical_usb_readiness_macos.py \
  --iso /path/to/Codex-Rescue-ISO-v0.1.0-alpha.13-67E79C37.iso
```

Run the audit once to obtain the live token. Saving a plan requires `--plan` on internal storage and `--confirmation-token` with that exact value. Both readiness paths are deliberately non-destructive. The repository does not contain an automatic raw writer, and neither readiness path launches one.

Before a physical release can be claimed, record all of the following for a dedicated, disposable device:

- verified ISO SHA and source commit;
- readiness-plan identity for exactly one removable target;
- independent writer selection and erase confirmation;
- UEFI boot on representative physical hardware;
- evidence collection to a separate removable destination;
- no-overwrite behavior;
- owner-attended masked BitLocker entry on a disposable hardware data volume;
- cold-relock behavior; and
- sanitized handoff and full-Windows Codex workflow with least privilege.

Until those records exist, use “VM-verified Technical Preview,” not “production-ready rescue USB.”
