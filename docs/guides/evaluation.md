# Evaluate Codex Rescue USB safely

This guide is the recommended first contact with the project. It runs the fixture-only Rescue Console on your current computer and demonstrates the diagnostic, approval, simulation, verification, and audit flow without touching a real disk.

## What this evaluation proves

The evaluation shows that the application can:

- load validated local fixture evidence;
- distinguish a repairable boot-loop simulation from a locked BitLocker or failing-drive stop condition;
- build a complete proposed-operation contract;
- bind an approval to the exact proposal and target digests;
- run one allowlisted fixture simulation;
- validate a typed receipt against separate post-action fixture evidence; and
- retain a timestamped, hash-chained local audit record.

It does **not** prove that a physical USB boots, that a real drive can be repaired, or that BitLocker recovery works on production data. Those acceptance gates are tracked in [verification evidence](../reference/verification-evidence.md).

## Requirements

- Python 3.11 or newer
- A browser
- No third-party Python packages

The web interface has no external runtime dependency and the server binds to loopback only.

## Start the fixture console

### macOS or Linux

```bash
git clone https://github.com/Morlock52/codex-rescue-usb.git
cd codex-rescue-usb
PYTHONPATH=src python3 -m codex_rescue --port 8080
```

### Windows PowerShell

```powershell
git clone https://github.com/Morlock52/codex-rescue-usb.git
Set-Location .\codex-rescue-usb
$env:PYTHONPATH = 'src'
python -m codex_rescue --port 8080
```

Expected startup output:

```text
Codex Rescue USB fixture console: http://127.0.0.1:8080
Fixture-only simulation. Host commands and disk writes are disabled.
Fixture audit logs: <your local case directory>
```

If port 8080 is in use, choose another loopback port, for example `--port 8090`. Open the printed URL in a browser.

## Walk through the three safety outcomes

### Boot loop: approval-bound simulation

1. Select **Boot loop** in Problem categories.
2. Review the observed evidence and likely cause.
3. Open the proposed BCD reconstruction and rollback evidence.
4. Select **Approve exact simulated plan**.
5. Select **Run safe simulation**.
6. Confirm the result says the independent post-action fixture passed.
7. Open the hash-chained audit record.

The console updates fixture state only. It does not call `bcdboot`, `bcdedit`, PowerShell, DiskPart, or another host command.

### Locked BitLocker: safe stop

1. Select **Locked BitLocker volume**.
2. Confirm the console reports the locked state.
3. Confirm there is no executable proposal and no field that accepts a recovery key.

This illustrates an important project rule: observing encrypted state does not authorize unlocking it, and recovery material never belongs in the fixture console or Codex context.

### Failing drive: preserve-first stop

1. Select **Failing drive**.
2. Confirm the diagnostic engine prioritizes media-health risk over boot repair.
3. Confirm the ordinary write path is blocked.

This is a simulation of a preserve-first decision. The project does not claim to image or recover a real failing disk at this milestone.

## Inspect local audit data

The default case directory is:

- macOS/Linux: `~/.codex-rescue/cases`
- Windows: `%USERPROFILE%\.codex-rescue\cases`

Each case is append-only JSON Lines. Events include timestamps, the prior event hash, and the new event hash. Do not treat these fixture records as forensic chain-of-custody evidence for a real incident.

To use a temporary evaluation location:

```bash
PYTHONPATH=src python3 -m codex_rescue --port 8080 --case-dir /tmp/codex-rescue-evaluation
```

In Windows PowerShell:

```powershell
$env:PYTHONPATH = 'src'
python -m codex_rescue --port 8080 --case-dir "$env:TEMP\codex-rescue-evaluation"
```

## Run the verification suite

```bash
python3 -W error::ResourceWarning -m unittest discover -s tests -v
python3 -m compileall -q src tests
node --check web/assets/app.js
```

The suite currently contains 121 tests. A passing suite establishes source-level contracts, not physical-media acceptance.

## Evaluation checklist

- [ ] Server prints a `127.0.0.1` URL.
- [ ] Browser loads without internet access.
- [ ] Boot-loop simulation requires an exact approval first.
- [ ] A single approval cannot execute twice.
- [ ] Locked BitLocker accepts no secret input.
- [ ] Failing-drive fixture blocks ordinary writes.
- [ ] Audit record opens and contains linked event hashes.
- [ ] All 121 tests pass in the evaluator’s checkout.

Next: read the [operator guide](operator-guide.md) before using the Windows diagnostic or WinPE stages.
