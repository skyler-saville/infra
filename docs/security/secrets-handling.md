# Secrets handling guidance

## Approved secret storage mechanisms

Secrets must **never** be committed to this repository. Store sensitive values only in approved secret stores:

- CI/CD provider managed secrets (for example, GitHub Actions encrypted secrets/variables).
- Cloud KMS/secret manager services used by runtime environments.
- Organization-approved vault tooling.
- Local developer secret stores outside the repository (for example, shell profile exports or local keychain integrations).

Do not store secrets in:

- tracked `.env` files,
- checked-in configuration files,
- scripts, tests, or inline command arguments.

Use example files (such as `*.env.example`) for non-sensitive placeholders only.

## Redacting sensitive values in logs

When logging:

- never print full credential values,
- log only metadata (e.g., key name and source),
- if reference is required, show only a short fingerprint (for example last 4 chars),
- avoid `set -x` in scripts that may handle secrets.

Use the shared logging helpers in `lib/common.sh` and keep logged output high-level.

## Validating `.env` and config exclusions

This repository enforces two checks:

1. **Pre-commit hook** via `gitleaks` to detect secrets before commit.
2. **Sensitive file exclusion validator** (`scripts/check-sensitive-files-excluded.sh`) to ensure required ignore patterns exist and no sensitive `.env`/secret-like config files are tracked.

Install hooks locally:

```bash
pre-commit install
```

Run checks manually:

```bash
pre-commit run --all-files
scripts/check-sensitive-files-excluded.sh
```

For incident response steps when a secret is detected, see [Secret leak remediation](./secret-leak-remediation.md).
