# Contributing

Contributions are welcome when they preserve the project’s evidence and authorization boundaries.

## Start with the contract

Read:

- [Architecture](docs/reference/architecture.md)
- [Security model](docs/reference/security-model.md)
- [Verification evidence](docs/reference/verification-evidence.md)

For significant behavior changes, open a feature issue before implementation. Describe the operator problem, evidence required, authorization gate, rollback strategy, and acceptance environment.

## Development setup

The Python fixture console uses only the standard library.

```bash
git clone https://github.com/Morlock52/codex-rescue-usb.git
cd codex-rescue-usb
PYTHONPATH=src python3 -m codex_rescue --port 8080
```

Run the baseline checks:

```bash
python3 -W error::ResourceWarning -m unittest discover -s tests -v
python3 -m compileall -q src tests
node --check web/assets/app.js
```

PowerShell changes must also parse in Windows PowerShell 5.1 unless the component explicitly documents a later runtime. WinPE changes require a clean ISO build, exact artifact verification, and a disconnected disposable-VM boot before a VM-runtime claim is added.

## Required change discipline

- Keep changes narrow and explain every new data field or side effect.
- Add negative tests before or with safety-sensitive behavior.
- Never add a recovery-key, password, token, raw tenant response, or customer evidence fixture.
- Preserve the distinction between raw, sanitized, and Codex-approved artifacts.
- Do not add automatic uploads, implicit network enablement, broad Graph scopes, disk guessing, silent overwrite, or an unattended repair path.
- Bind sensitive approval to the exact target and current operation.
- Recheck the target immediately before a side effect.
- Label screenshots and documentation as fixture, source, VM, physical hardware, or production evidence.
- Do not upgrade a verification claim without the corresponding runtime record.

## Pull-request checklist

- [ ] The issue or operator problem is linked.
- [ ] Existing and new tests pass.
- [ ] Security and privacy implications are documented.
- [ ] Failure and ambiguity paths fail closed.
- [ ] No secret or production identifier appears in code, fixtures, logs, screenshots, or Git history.
- [ ] Documentation matches the actual evidence level.
- [ ] New screenshots are privacy-reviewed and accurately captioned.
- [ ] PowerShell and JavaScript syntax checks pass where applicable.
- [ ] A VM or physical acceptance claim includes exact artifact identity and environment details.

## License

By contributing, you agree that your contribution is licensed under the repository’s [Apache License 2.0](LICENSE).
