# BitLocker recovery-password safety contract

**Status:** Helper and WinPE command implemented; static tests pass. No alpha.10 ISO, runtime unlock, refusal-path, cold-lock, or output-boundary evidence is accepted yet.

## Scope

This contract covers one disposable 1-GiB virtual data disk with exactly one numerical recovery-password protector. It does not authorize an operating-system volume, an existing disk, physical hardware, production data, decryption, protector changes, repair, or network use.

## Secret boundary

- The generated 48-digit password is shown once by Microsoft's local `manage-bde` process in a separate interactive console.
- Fixture creation must refuse redirected input or output. Never launch it through Codex, QEMU guest-agent execution, a transcript, or a recorded screen.
- The operator may transcribe the disposable password locally. It must never enter a file, clipboard, screenshot, chat, shell history, evidence package, repository, release asset, or Codex context.
- The checked-in fixture helper never calls `GetKeyProtectorNumericalPassword` and never receives the generated password in its PowerShell process.
- WinPE accepts the password only through `Read-Host -AsSecureString`, converts it for the in-process Microsoft WMI call, and releases the unmanaged BSTR in `finally`.

## Target controls

1. Fixture creation requires one explicit disk number, exact confirmation token, administrator rights, a RAW partition style, a 0.9-1.1 GiB size, and a non-boot/non-system disk.
2. WinPE requires one explicit letter from `D:` through `W:`, `Y:`, or `Z:` plus the exact `UNLOCK <drive>:` token. Ordinary `C:` and WinPE `X:` are excluded.
3. The selected volume must exist exactly once in `Win32_EncryptableVolume` and report locked before the password prompt appears.
4. The command validates numerical-password format, calls `UnlockWithNumericalPassword` only on the selected instance, then independently requires unlocked status and an accessible root.
5. Neither helper changes protectors after fixture creation, decrypts, repairs, exports evidence, or enables networking.

## Runtime acceptance matrix

| Test | Required result |
| --- | --- |
| Wrong confirmation token | Stop before prompting |
| Target `C:` or `X:` | Parameter validation refusal |
| Missing or ambiguous target | Stop before prompting |
| Empty input | Stop without unlock |
| Invalid numerical format | Stop without unlock |
| Valid but wrong password | Microsoft authentication failure; remain locked |
| Correct disposable password | Only selected fixture unlocks and known non-secret file is readable |
| Cold restart | Fixture returns to locked |
| Output-boundary scan | No recovery-password pattern in logs, evidence, screenshots, source, Git history, or Codex context |

The exact ISO size and SHA-256, test-VM configuration, fixture audit, approved redacted screenshots, and independent leakage scan must be recorded before changing this status to VM-verified.
