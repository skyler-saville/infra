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

## Script scaffold for maintainers

## Mutating script safety convention

Any script that can change files, infrastructure, or runtime state must follow this convention:

- require an explicit mode flag: `--dry-run` or `--execute`,
- include `--dry-run` support in usage/help,
- print `would execute: ...` for each mutating action in dry-run mode,
- perform no side effects while dry-run is enabled,
- print a summary of planned changes before actions run.

This convention is implemented in existing mutating scripts such as
`deploy-tools/bin/deploy-project.sh` and `scripts/scaffold-script.sh`.

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

CI runs these checks automatically in `.github/workflows/script-tests.yml` on pushes and pull requests.
