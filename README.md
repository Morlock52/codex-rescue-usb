# Codex Rescue USB

Codex Rescue USB is a safety-first prototype for a future offline PC recovery environment. This milestone is a host-runnable Rescue Console that diagnoses bundled fixtures, creates structured repair proposals, requires explicit approval, simulates an allowlisted repair, and independently verifies the simulation.

> **Fixture-only:** This repository cannot repair a PC. It does not mount, unlock, write, format, or execute host commands. Never enter a BitLocker recovery key into this prototype.

## Run the console

Python 3.11 or newer is required. No third-party packages or network connection are needed.

```sh
PYTHONPATH=src python3 -m codex_rescue --port 8080
```

Open `http://127.0.0.1:8080`. The server always binds to loopback.

The three bundled scenarios demonstrate:

- a boot-loop fixture with an approvable BCD rebuild simulation;
- a locked BitLocker fixture that blocks repair without accepting recovery material;
- a failing-drive fixture that blocks ordinary repair and recommends imaging to separate storage.

## Test

```sh
python3 -m unittest discover -s tests -v
node --check web/assets/app.js
python3 -m compileall -q src tests
```

## Design and safety contract

- [Product and safety design](docs/plans/2026-08-04-codex-rescue-usb-design.md)
- [Fixture console implementation plan](docs/plans/2026-08-04-fixture-rescue-console-implementation.md)
- [Editable Figma Rescue Console](https://www.figma.com/design/sW9ctJbQnpgzx0DqJqwnbo)

The future bootable USB architecture remains a separate, gated milestone. Real disk and BitLocker operations are intentionally absent here.
