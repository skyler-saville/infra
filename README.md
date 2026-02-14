# infra

## Shared Bash helpers

Common reusable shell helpers live in `lib/common.sh`, including:

- structured log formatting (`info`, `warn`, `error`, `debug`),
- retry with exponential backoff (`retry_with_backoff`),
- safe temp-directory lifecycle and exit cleanup trap (`create_temp_dir`, `setup_cleanup_trap`),
- command dependency checks (`require_cmd`, `require_cmds`),
- normalized error/exit helpers (`die`, `exit_with`).

Source this file in repository scripts to avoid copy/pasted utility logic.

## Environment profiles for infrastructure scripts

Infrastructure scripts now use explicit environment profiles in `env/`:

- `env/dev.env`
- `env/staging.env`
- `env/prod.env`

`lib/env-loader.sh` enforces that scripts:

- require an explicit `--env` selection,
- fail if the profile file is missing,
- validate required profile variables,
- block prod by default unless explicitly unlocked,
- print selected context before running the main action.

Example deploy usage:

```bash
deploy-tools/bin/deploy-project.sh --env staging deploy-tools/projects/jukebotx.env.example
```

Prod requires an explicit override flag:

```bash
deploy-tools/bin/deploy-project.sh --env prod --allow-prod deploy-tools/projects/jukebotx.env.example
```

## Remote Docker/Compose and SSH tooling

Additional deployment helpers are available under `deploy-tools/bin`:

- `compose-remote.sh`: deploy remote Docker Compose projects over SSH with cascading
  `-f` overrides (`docker-compose.yml`, then env-specific overlays, then custom files).
- `ssh-project.sh`: run controlled remote SSH commands with shared safety semantics.

Both scripts follow the repository safety convention and require exactly one mode:
`--dry-run`, `--execute`, or `--checklist`.

Examples:

```bash
deploy-tools/bin/compose-remote.sh \
  --dry-run \
  --env staging \
  --project-env deploy-tools/projects/compose-project.env.example

deploy-tools/bin/ssh-project.sh \
  --execute \
  --env dev \
  --host deploy@example.com \
  --remote-dir /opt/my-app \
  --command 'docker compose ps'
```

## Script scaffold for maintainers

## Script metadata for incident response

All shell scripts (`*.sh`) must include adjacent metadata files using:

- `<script-path>.metadata.yaml`

The metadata schema captures owner/team, purpose, risk level, preconditions,
rollback steps, and runbook links to improve incident-time discoverability.

See the standard and repository-wide index in:

- [Script metadata standard and index](docs/scripts-metadata.md)

## Mutating script safety convention

Any script that can change files, infrastructure, or runtime state must follow this convention:

- require an explicit mode flag: `--dry-run` or `--execute`,
- include `--dry-run` support in usage/help,
- print `would execute: ...` for each mutating action in dry-run mode,
- perform no side effects while dry-run is enabled,
- print a summary of planned changes before actions run,
- for high-impact scripts, provide a `--checklist` mode that prints:
  - targeted resources,
  - permissions required,
  - backup/rollback readiness,
  - confirmation prompts required before execution.

This convention is implemented in existing mutating scripts such as
`deploy-tools/bin/deploy-project.sh` and `scripts/scaffold-script.sh`.


For production-impacting tasks, run checklist mode in runbooks and CI policy checks before execution:

```bash
deploy-tools/bin/deploy-project.sh --checklist --env prod --allow-prod deploy-tools/projects/jukebotx.env.example
```

Use `scripts/scaffold-script.sh` to create new Bash scripts with:

- strict mode (`set -euo pipefail`),
- shared helpers from `lib/common.sh`,
- argument parsing scaffold (`--help`, `--dry-run`, `--execute`, `--verbose`),
- preflight checks for required binaries/environment variables,
- usage examples and inline maintenance notes.

Example:

```bash
scripts/scaffold-script.sh --execute scripts/my-new-task.sh
```

Then edit the generated file to fill in the TODOs for script-specific behavior,
preflight requirements, and examples.


## Schema-based configuration validation

Environment profiles in `env/*.env` are now validated with JSON Schema (`schemas/env-profile.schema.json`) via `scripts/validate-config.py`.

This validation now:

- fails fast for malformed config structure,
- enforces required fields and allowed values,
- blocks unsafe production combinations (for example, prod lock directories under `/tmp`).

Run locally:

```bash
make validate-config
```

For full local checks prior to commit:

```bash
make preflight
```

Shell formatting is standardized with `shfmt` for scripts in `deploy-tools/bin/*.sh`, `scripts/*.sh`, and `lib/*.sh`.

- apply formatting: `make fmt-scripts`
- verify formatting (CI-safe diff mode): `make check-fmt`

`check-fmt` is included in `make preflight`, runs in CI (`.github/workflows/script-tests.yml`), and is enforced by pre-commit hooks (`.pre-commit-config.yaml`). When `shfmt` is not installed, local runs are skipped with a warning; GitHub Actions CI remains strict.

`validate-config` also runs in CI (`.github/workflows/script-tests.yml`) and in pre-commit hooks (`.pre-commit-config.yaml`).

## Secret scanning and secure configuration hygiene

This repository now enforces secret scanning in both local developer workflow and CI:

- pre-commit hook: `gitleaks` runs before each commit,
- CI workflow: `.github/workflows/secret-scanning.yml` runs the same scan for pushes/PRs,
- policy check: `scripts/check-sensitive-files-excluded.sh` validates ignore rules and sensitive-file tracking.

Setup and run locally:

```bash
pre-commit install
pre-commit run --all-files
scripts/check-sensitive-files-excluded.sh
```

See detailed guidance and incident response docs:

- [Secrets handling guidance](docs/security/secrets-handling.md)
- [Secret leak remediation runbook](docs/security/secret-leak-remediation.md)


## Script test framework and CI

This repository now uses [Bats](https://bats-core.readthedocs.io/) for shell-script regression tests in `tests/bats`.

Current coverage includes:

- help output and invalid argument handling,
- dry-run no-op guarantees,
- required dependency checks,
- non-zero exits for invalid runtime state.

Run locally:

```bash
make test-scripts
```

If `bats` is not installed, local `make test-scripts` exits early with a warning; GitHub Actions CI remains strict and installs/runs Bats in `.github/workflows/script-tests.yml`.

CI runs these checks automatically in `.github/workflows/script-tests.yml` on pushes and pull requests.
