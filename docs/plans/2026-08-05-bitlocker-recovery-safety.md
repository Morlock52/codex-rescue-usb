# BitLocker recovery-key safety contract

**External-key sub-gate status:** VM-verified on August 5, 2026 against the exact alpha.7 artifact. Recovery-password, operating-system-volume, physical-hardware, and production-use gates remain open.

## Scope

This contract covers the disposable Proxmox test for unlocking one BitLocker-protected data volume with one external `.bek` recovery-key file. It does not authorize operating-system-volume repair, decryption, protector removal, key rotation, customer-data access, or physical-hardware use.

## Trust boundaries and assets

- The encrypted data disk, key disk, WinPE RAM drive, evidence destination, Codex context, screenshots, and GitHub are separate boundaries.
- The `.bek` file and any recovery password are secret recovery material. They must remain on an operator-controlled key drive and must never enter Codex context, command transcripts, screenshots, evidence exports, source control, or release assets.
- The selected volume letter is integrity-critical. A correct key must never be tried against an ambiguous or implicit target.

## Enforced controls

1. WinPE includes Microsoft's `WinPE-SecureStartup` component after its required `WinPE-WMI` dependency.
2. `Unlock-BitLockerWithRecoveryKey.cmd` accepts exactly one explicit data-volume letter and blocks `C:` and WinPE's `X:` RAM drive.
3. Exactly one different drive must contain the `CODEX_BITLOCKER.KEY` marker.
4. That prepared key drive must contain exactly one `.bek` file. The command does not display its name or contents.
5. The operator must type `UNLOCK <drive>:` to authorize the exact selected volume.
6. The key is passed only to the local Microsoft `manage-bde` process. No file, transcript, history, manifest, or network request records it.
7. The command performs no formatting, decryption, protector change, repair, or evidence export. It verifies volume status after the unlock attempt.

## Abuse paths and mitigations

| Abuse path | Impact | Mitigation |
| --- | --- | --- |
| Wrong volume selected | Unauthorized data access | Explicit allowlisted letter plus exact typed confirmation |
| Wrong or attacker-supplied key drive | Key confusion or failed unlock | Unique root marker and exactly-one-drive gate |
| Multiple `.bek` files | Ambiguous key selection | Refuse the operation before calling BitLocker |
| Key leaks into diagnostics or Codex | Credential disclosure | Separate marker, no key output, no logging, no network use, evidence collector ignores the key marker |
| Unlock success is assumed | False recovery claim | Require successful `manage-bde` return and a separate status query |
| Test fixture is mistaken for production proof | Unsafe deployment | Keep VM, physical USB, recovery-password, and repair evidence boundaries separate in the README |

## Acceptance requirements

- A newly created disposable virtual data disk is encrypted with BitLocker and locked before WinPE starts.
- A separate disposable virtual disk contains only the marker and the matching external recovery-key file.
- The exact rebuilt ISO refuses missing, multiple, and ambiguous key inputs.
- The matching key unlocks only the selected test volume, and a known non-secret fixture file can be read afterward.
- No recovery material appears in console captures, build logs, evidence packages, repository history, or GitHub.

## Alpha.7 verification record

| Property | Verified value |
| --- | --- |
| ISO | `Codex-Rescue-ISO-v0.1.0-alpha.7.iso` |
| Size | 558,286,848 bytes |
| SHA-256 | `A4FF89AD4FBF1BEB6BAECA4B92387F0153754B270BA3DF897DA11C99812DE947` |
| Environment | Isolated 2-vCPU, 2-GB Proxmox UEFI VM with network link down |
| Data fixture | 3-GiB `CODEX-BL-TEST`, XTS-AES 128, 100% encrypted, locked before boot |
| Key fixture | Separate 1-GiB `CODEX-BL-KEY`, fully decrypted, one hidden `.bek` file |
| Authorization | Exact target `E:` plus typed `UNLOCK E:` |
| Unlock result | BitLocker reported unlocked, protection on; root access succeeded |
| Content check | Known non-secret `RECOVERY-TEST.txt` was readable |
| End state | Cold restart returned the data fixture to `Lock Status: Locked`; VM stopped |

The alpha.6 candidate was rejected because the native `manage-bde` success text disclosed the external-key filename even though it did not disclose the key contents. That capture was deleted and was never added to the repository or GitHub. Alpha.7 suppresses the native unlock output, and its three approved screenshots were visually checked before publication.

Minimal WinPE returned `0x80073bc3` (“The requested system device cannot be found”) around status and in-session lock operations because the disposable VM had no installed Windows system device. The script treats the pre- and post-unlock status display as informational and separately requires both a successful unlock result and accessible selected-volume root. The test did not claim that the in-session relock command succeeded; it used a cold restart and re-ran the guard to verify `Lock Status: Locked`.

The external `.bek` sub-gate is verified for this disposable VM fixture. Phase 3 as a whole remains open until the 48-digit recovery-password UI, refusal paths, disposable operating-system-volume recovery, and independent output-boundary review are complete.
