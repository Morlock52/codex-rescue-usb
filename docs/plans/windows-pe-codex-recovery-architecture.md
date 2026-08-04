# Windows PE and Codex Recovery Architecture

## Goal

Evolve Codex Rescue USB into a two-stage recovery medium for owner-authorized Windows repair:

1. Windows PE performs offline discovery, evidence collection, and an explicit BitLocker recovery-key unlock flow.
2. A full Windows recovery workspace runs the signed-in Codex desktop app with its GUI and voice capability to guide reviewed troubleshooting and repair.

## Why two stages

Windows PE is appropriate for offline boot and Windows recovery tools, but it is not a supported target for the Codex desktop application. The full recovery workspace supplies the normal Windows services, authentication, audio, network controls, and desktop environment that Codex requires.

## USB layout

- **Boot partition:** Windows PE image and a read-only recovery launcher.
- **Recovery workspace:** a separately built, full Windows environment with the Codex desktop app installed through its supported installer.
- **Evidence partition:** encrypted, owner-controlled collection of logs and diagnostic exports. It is never used to retain BitLocker recovery keys.

## Safety gates

- No recovery key is stored, logged, or sent to Codex. The owner enters it only into the Windows BitLocker recovery flow.
- The launcher begins read-only: inventory, SMART and event evidence, Windows Recovery Environment data, and BitLocker state.
- Unlock and every write action require the operator to review the exact target and confirm the action locally.
- Codex can explain evidence and propose steps, but it does not receive recovery keys and cannot bypass local confirmation.
- The recovery workspace defaults to network-off. Enabling network access for Codex is a separate, visible operator choice.

## Build prerequisites

- A Windows build host with the Windows ADK and Windows PE add-on.
- A disposable USB drive for boot and hardware testing.
- A supported Windows installation medium for the full recovery workspace.
- A supported Codex desktop-app installer and a user sign-in at first use.

## Acceptance evidence

1. The USB boots a test PC into Windows PE.
2. The launcher inventories disks and BitLocker state without changing data.
3. An owner can unlock a test BitLocker volume with a valid recovery key, and no key appears in logs or the collected evidence.
4. The full workspace starts only after explicit operator selection.
5. Codex GUI and voice work in the full Windows workspace after sign-in and approved network access.
6. Every repair action has target, rollback, operator-approval, and post-action verification evidence.

## Implementation order

1. Build the Windows PE image and read-only launcher.
2. Add BitLocker-state discovery and the local, no-key-retention unlock handoff.
3. Build and harden the full Windows recovery workspace.
4. Install and validate Codex GUI, voice, sign-in, and network controls in that workspace.
5. Test the end-to-end flow on a disposable BitLocker-protected drive before any production use.
