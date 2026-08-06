# Security and data-boundary model

Codex Rescue USB is built around a simple rule: being technically capable of an action does not authorize that action. The system separates observation, proposal, approval, execution, and independent verification.

## Protected assets

- customer and user files;
- BitLocker recovery passwords and external-key files;
- access tokens, app secrets, and authentication context;
- tenant, user, group, and device identifiers;
- raw Windows logs and event payloads;
- network addresses and machine-specific evidence;
- boot configuration and encrypted-volume state; and
- the integrity of the recovery ISO and checked-in source.

## Threats addressed by the current design

| Threat | Control |
| --- | --- |
| Wrong disk or volume | Exact target identity, blocked system/RAM drives, fresh recheck, exact token |
| Evidence written to the wrong destination | Marker file, exactly-one candidate, excluded internal/RAM drives, rescan |
| Earlier evidence overwritten | Existing output directory causes refusal |
| Recovery secret exposed to Codex or logs | No secret fields, masked local input, no redirected numerical-password path, pattern scans |
| Raw evidence automatically uploaded | No automatic handoff; separate local summary/ZIP and operator review |
| Network used without consent | Offline startup policy and exact selected-adapter enable/disable token |
| Cloud permission expansion | Fixed delegated read-only scopes, `GET` allowlist, no app-only identity |
| Cloud response leaks identifiers | Bounded mapping, raw response discarded, final GUID/secret validation |
| Stale approval used after state changes | Approval bound to proposal and target digests; one-use execution |
| Malicious or malformed target data | Schema validation, bounds, text-only rendering, fail-closed parsing |
| Stale artifact presented as verified | Build verifier records exact identity and removes older success on failure |

## Recovery-material policy

Recovery material must never be:

- stored in the repository;
- typed into the fixture console;
- passed in a command-line argument;
- redirected to a file or transcript;
- placed in raw or sanitized evidence;
- displayed in a screenshot;
- pasted into Codex, GitHub, email, chat, or a ticket;
- fetched through the Graph module; or
- retained after the owner-controlled recovery event.

External-key material stays on its separate owner-controlled drive. A numerical recovery password is entered only into the local masked prompt. If a secret appears in a captured artifact, stop, quarantine the artifact, remove it from publication paths, and follow the private reporting process in [SECURITY.md](../../SECURITY.md).

## Evidence classification

### Raw local evidence

Raw WinPE and Windows diagnostic output can contain device-specific identifiers, addresses, paths, and troubleshooting details. Keep it on technician-controlled storage. Do not commit or attach it to a public issue.

### Sanitized escalation package

The Windows assessment exporter emits a separate ZIP with sanitized JSON, sanitized HTML, and a privacy declaration. It excludes raw management logs. A human must still review it before sharing.

### Codex aggregate summary

`New-CodexEvidenceSummary.ps1` validates manifest/checksum integrity and emits bounded aggregate facts outside the raw package. It rejects unexpected subdirectories, recovery-key artifacts, numerical-password patterns, and invalid privacy declarations. It is the preferred starting artifact for Codex, but still requires operator review.

## Network and authentication

WinPE is intended to remain disconnected. The full-Windows workspace starts offline and enables only an explicitly selected physical adapter. The QEMU Guest Agent is a separate Proxmox management channel; its reachability does not mean Windows guest networking is enabled.

Codex authentication occurs only in the maintained full-Windows environment after image creation. The build image must not retain user Codex or Graph authentication, access tokens, API keys, or client secrets.

Graph authentication is delegated and operator-attended. The module requests process-scoped context so the sign-in does not persist beyond the current PowerShell process. Disconnect and return the selected adapter offline after the bounded query.

## Repair authorization model

The current real environments are diagnostic-first. The fixture console demonstrates the future execution contract:

1. observe validated evidence;
2. identify a likely cause;
3. construct a complete allowlisted proposal;
4. show target, expected effects, risk, rollback, and verification plan;
5. approve the exact proposal once;
6. revalidate state immediately before execution;
7. return a typed receipt; and
8. verify independent post-action evidence.

Real repair operations must not be added by bypassing this contract. Each new repair requires a documented rollback path, negative tests, disposable-VM runtime evidence, and later physical-hardware acceptance.

## Known limits

The current controls reduce risk but do not create a forensic product, guarantee recovery, or replace backups, legal authorization, organizational incident procedures, OEM tooling, Microsoft support, or professional data-recovery services. A compromised firmware, malicious USB device, physically failing drive, or hostile target installation may invalidate ordinary assumptions.

Use disposable media and isolated systems during evaluation. Escalate failing-drive cases to preservation/imaging specialists rather than experimenting with repairs.
