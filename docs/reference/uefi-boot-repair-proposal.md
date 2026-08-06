# UEFI boot-repair proposal contract

This reference documents the source-verified, **inert** UEFI boot-repair proposal generator. It exists to make target selection, evidence integrity, rollback readiness, and the exact proposed command reviewable before a future live repair path is designed.

It does not discover disks, mount an EFI partition, request approval, unlock BitLocker, execute a command, or modify boot files. Fixture evidence is never promoted to live evidence or approval readiness.

## Current evidence level

| Claim | Status |
| --- | --- |
| Valid fixture contract produces a target-bound JSON plan | Source/runtime test verified |
| Recovery-material declaration is rejected | Source/runtime test verified |
| Windows and EFI volumes on different disk identities are rejected | Source/runtime test verified |
| Rollback backup without a tested restore is rejected | Source/runtime test verified |
| Existing proposal output is never overwritten | Source/runtime test verified |
| Generator has no repair-command execution path | Static contract verified |
| Live Windows discovery | Not implemented |
| Live approval and execution | Not implemented |
| Disposable-VM boot repair and rollback | Not yet validated |
| Physical-PC boot repair | Not accepted |

## Generate a proposal

From the repository root in PowerShell 7:

```powershell
.\scripts\New-CodexRescueUefiBootRepairPlan.ps1 `
  -ContractFixturePath '.\lab\uefi-discovery-contract.json' `
  -OutputPath '.\lab\uefi-boot-repair-plan.json'
```

Use `-AsJson` instead of `-OutputPath` to print JSON. The two options cannot be combined. Output files must use `.json`, their parent directory must already exist, and an existing file is refused rather than replaced.

## Complete lab input example

The fixture is intentionally explicit. Replace the illustrative hashes and identities only with values derived from a disposable lab contract; never add a recovery password, `.bek` content, access token, private key, or raw customer evidence.

```json
{
  "SchemaVersion": 1,
  "EvidenceSha256": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
  "EvidenceIntegrityVerified": true,
  "ContainsRecoveryMaterial": false,
  "ContainsSensitiveRawEvidence": false,
  "StorageHealth": "Healthy",
  "BitLockerState": "Unlocked",
  "FirmwareType": "UEFI",
  "WindowsDirectory": "D:\\Windows",
  "WindowsDirectoryVerified": true,
  "WindowsDiskUniqueId": "DISPOSABLE-DISK-001",
  "EfiSystemPartition": "S:",
  "EfiPartitionVerified": true,
  "EfiFileSystem": "FAT32",
  "EfiDiskUniqueId": "DISPOSABLE-DISK-001",
  "RollbackArtifactType": "EfiMicrosoftBootDirectoryBackup",
  "RollbackArtifactPath": "E:\\CodexRescueRollback\\EfiMicrosoftBoot.zip",
  "RollbackArtifactSha256": "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
  "RollbackArtifactVerified": true,
  "RollbackRestoreTested": true
}
```

The schema is allowlisted. Missing fields and unexpected fields both fail closed.

## Required gates

The generator rejects the fixture unless all of these statements are true:

1. the evidence digest is a 64-character SHA-256 value and integrity was independently verified;
2. the input declares no recovery material and no sensitive raw evidence;
3. storage health is exactly `Healthy`;
4. BitLocker is already `Unlocked`;
5. firmware is exactly `UEFI`;
6. the verified Windows directory is drive-rooted and not the WinPE `X:` drive;
7. the verified EFI System Partition has an explicit temporary letter, is not `C:` or `X:`, and uses FAT32;
8. Windows and EFI disk unique identities match exactly; and
9. the EFI Microsoft boot-directory backup has a SHA-256 digest, passed verification, and passed a restore test.

The raw JSON is also scanned for a Microsoft 48-digit recovery-password shape, `.bek` material, bearer tokens, and private-key markers before parsing.

## Output interpretation

The output includes:

- `EvidenceSha256` — binds the proposal to the reviewed evidence contract;
- `TargetFingerprint` — binds Windows directory, EFI partition, filesystem, and both disk identities;
- `ProposalDigest` — binds the operation, arguments, target, evidence, and rollback digest;
- `Rollback` — records the backup identity and restore-test gate;
- `StopConditions` — lists changes that invalidate the proposal; and
- `VerificationPlan` — lists the lab evidence still required.

Fixture output can never contain an approval token and always reports:

```json
{
  "PlanOnly": true,
  "LiveEvidence": false,
  "ReadyForApproval": false,
  "ApprovalRequired": true,
  "ApprovalRecorded": false,
  "ExecutionAvailable": false,
  "WritePerformed": false,
  "RequiredConfirmationToken": null
}
```

## Why the proposed arguments are constrained

The proposal records the following argument shape as data:

```text
bcdboot.exe D:\Windows /s S: /f UEFI /v
```

Microsoft documents the Windows directory as the source, `/s` as the exact system-partition selection, and `/f UEFI` as the UEFI firmware type. Microsoft also documents that on UEFI systems, using `/s` prevents BCDBoot from creating a firmware NVRAM entry and instead relies on the default firmware path. That behavior is why the proposal reports `FirmwareNvramWriteExpected: false`. See Microsoft’s [BCDBoot command-line options](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/bcdboot-command-line-options-techref-di?view=windows-11).

`/bootex` is excluded from the first contract because Secure Boot CA servicing is a separate version- and evidence-dependent decision. Importing an entire BCD store is also excluded: Microsoft documents that BCDEdit `/import` deletes existing entries before importing the backup. See Microsoft’s [BCDEdit command reference](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/bcdedit).

These links explain the proposal semantics; they do not authorize execution.

## Remaining implementation gates

The next phase must be completed on a disposable full-Windows/WinPE lab path before any execution feature is considered:

1. implement read-only live discovery with stable disk and partition identifiers;
2. create and independently restore-test the EFI Microsoft boot-directory backup;
3. generate a fresh live-evidence proposal and compare its target fingerprint after a rescan;
4. add an operator-attended, target-bound approval contract;
5. implement a narrow executor separately from this generator;
6. verify repaired boot and rollback in a disconnected disposable UEFI VM; and
7. retain console, artifact-hash, boot, rollback, and negative-path evidence.

Physical media and production systems remain outside this phase.
