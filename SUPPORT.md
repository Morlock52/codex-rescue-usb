# Support

Codex Rescue USB is an independent open-source **Enterprise Technical Preview**. Community support is best effort. There is no service-level agreement, production warranty, emergency response commitment, or guaranteed recovery outcome.

## Before opening an issue

1. Read the [current verification status](README.md#current-verification-status).
2. Confirm whether your result came from a fixture, source test, VM, physical device, or production system.
3. Reproduce the issue using disposable data whenever possible.
4. Run the source verification commands from the README.
5. Remove all secrets and customer-identifying material from the report.

## Good public issue evidence

- repository commit SHA;
- host or guest OS version and architecture;
- fixture, VM, or physical-hardware label;
- exact non-secret command and exit code;
- expected and observed behavior;
- sanitized minimal log excerpt;
- ISO size and SHA-256 when the ISO is relevant;
- ADK, WinPE add-on, and servicing versions for build failures; and
- whether networking, Graph, BitLocker, or physical-media gates were involved.

Use [GitHub Issues](https://github.com/Morlock52/codex-rescue-usb/issues) for reproducible bugs and bounded feature requests.

## Never post publicly

- BitLocker recovery passwords or `.bek` files;
- access tokens, cookies, API keys, app secrets, or authentication screenshots;
- tenant, user, group, or device identifiers;
- serial numbers, IP or MAC addresses, or unredacted machine inventory;
- customer files, raw evidence packages, or raw event logs;
- proprietary recovery images or Microsoft installation media; or
- a vulnerability that could place users or data at risk.

Report security issues through the private process in [SECURITY.md](SECURITY.md).

## Out-of-scope emergency requests

Public Issues are not an emergency recovery service. If a device contains irreplaceable data, shows signs of physical media failure, belongs to an active incident, or involves regulated/customer information, stop experimenting and follow the organization’s incident, backup, Microsoft support, OEM support, or professional data-recovery procedure.

## Support boundaries

The maintainers can help interpret repository behavior and reproduce bounded technical-preview defects. They cannot validate your authorization, recover or receive your keys, accept customer evidence, guarantee hardware compatibility, provide Microsoft or OpenAI account support, or take responsibility for a destructive third-party USB-writing action.
