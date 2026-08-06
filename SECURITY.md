# Security policy

## Supported versions

Security fixes are developed against the latest commit on the default branch. Technical-preview artifacts and historical alpha ISOs are evidence records, not long-term supported releases.

## Report a vulnerability privately

Do not open a public issue for a vulnerability. Use GitHub’s **Report a vulnerability** control on the repository’s Security tab when private vulnerability reporting is available. If that control is unavailable, open a public issue containing only the sentence `Private security contact requested` and no technical details, secrets, identifiers, or exploit steps. A maintainer can then establish a private channel.

Include, through the private channel only:

- affected commit and component;
- a concise impact statement;
- safe reproduction steps using disposable fixtures;
- whether recovery material, target selection, evidence privacy, network consent, Graph scope, or artifact integrity is involved; and
- a suggested mitigation if known.

## Secret exposure

Never submit a real BitLocker recovery password, external-key file, access token, tenant response, customer evidence package, or production identifier—even privately unless an authorized incident process explicitly requires it. Use synthetic values and disposable virtual disks.

If recovery material appears in a local log, screenshot, Git object, issue, or other artifact:

1. stop sharing the artifact;
2. disconnect it from automated upload or synchronization paths;
3. follow the owner’s credential/recovery-material rotation or incident process;
4. preserve only the minimum non-secret evidence needed to diagnose the defect; and
5. report the underlying exposure path privately.

## Security design scope

Read the project’s [security and data-boundary model](docs/reference/security-model.md). A passing source test or disposable-VM test does not establish physical or production security. The project is not a replacement for backups, enterprise incident response, endpoint-management policy, Microsoft support, or professional data recovery.
