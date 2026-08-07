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
| Arbitrary elevated code | Per-action broker accepts typed allowlisted operations and fixed packaged assets only |
| Loose or modified privileged script | Package-relative path, exact catalog, Authenticode signer, and SHA-256 validation |
| Malicious online/offline update | Trusted publisher identity, trusted code-signing chain, detached manifest signature, safe paths, sizes, and hashes |
| Forced downgrade | Current/N-1 cache, downgrade refusal, separate operator-visible rollback |
| Proxmox cross-resource deletion | Session-tracked VM ID, unique label, label re-read, and target-bound delete phrase |
| USB identity swap | Stable model/serial/unique ID fingerprint and immediate pre-clear re-scan |
| Unrecoverable UEFI change | Non-target EFI backup, per-file manifest, archive read proof, separate rollback |
| BitLocker salvage secret in process audit | `.bek` path only, generic ephemeral name, no `-rp`, protected staging, no command/output logging |
| Telemetry identifier leakage | Disabled default, dual consent, allowlisted envelope, forbidden-field rejection |

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

The advanced salvage workflow is narrower: it accepts only an owner-supplied `.bek` and optional matching key package. It does not expose `repair-bde -rp` because process-command auditing can retain numerical recovery material. Original key filenames are never included in plans or receipts, and the child process receives only fixed generic ephemeral paths.

## Software supply-chain boundary

Privileged assets are packaged in the signed MSIX. The release process signs PowerShell scripts before generating the exact asset catalog, then signs PE files and the final MSIX bundle. The broker derives its installed package version and catalog digest rather than accepting them from the UI.

A public Git checkout is untrusted development input. The broker rejects scripts outside its installed `Assets` root, unexpected catalog entries, missing signatures, changed hashes, unsupported schemas, and a signer different from the cataloged release signer.

Online and offline update verification uses a detached signed release manifest, stable package publisher identity, trusted code-signing chain, artifact path containment, exact sizes, and SHA-256. Azure Artifact Signing uses short-lived certificates, so update policy binds the stable publisher identity rather than one daily leaf-certificate thumbprint.

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

The optional Proxmox connector is separate from target networking. It requires HTTPS and a pinned server-certificate SHA-256 fingerprint, uses a session token by default, creates no VM network adapter, applies a unique session label, and deletes only session-tracked resources whose label still matches. The endpoint and token are operator supplied.

Telemetry is disabled by default. Even when administrator policy and operator consent both exist, only the versioned allowlisted envelope may be sent to an operator-supplied HTTPS OTLP endpoint. Usernames, hostnames, tenant/device IDs, disk identifiers, addresses, filenames, raw errors, command output, prompts, credentials, and recovery material are forbidden.

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

The new USB, UEFI, and `.bek` salvage executors implement this source contract, but their positive disposable-target acceptance gates remain open. Source presence is not permission to use them on customer media.

## Known limits

The current controls reduce risk but do not create a forensic product, guarantee recovery, or replace backups, legal authorization, organizational incident procedures, OEM tooling, Microsoft support, or professional data-recovery services. A compromised firmware, malicious USB device, physically failing drive, or hostile target installation may invalidate ordinary assumptions.

Use disposable media and isolated systems during evaluation. Escalate failing-drive cases to preservation/imaging specialists rather than experimenting with repairs.
