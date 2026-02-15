# infra

## How to use this repository

### What this repository is for

`infra` is a shared operations toolkit for infrastructure and deployment workflows. Its goal is to give contributors one consistent place for:

- environment-aware deploy/ops scripts,
- safety-first execution patterns (`--dry-run`, `--execute`, `--checklist`),
- configuration validation and policy checks,
- repeatable local and CI preflight automation.

If you are new, follow the beginner walkthrough below from top to bottom.

### Beginner-friendly quickstart (step-by-step)

#### Step 1: Clone the repository

```bash
git clone <your-org-or-fork>/infra.git
cd infra
```

If you work from a fork, add the upstream remote:

```bash
git remote add upstream <canonical-org>/infra.git
git fetch upstream
```

#### Step 2: Confirm repository modules/submodules

This repository currently does **not** use Git submodules (`.gitmodules` is not present), so a normal clone is sufficient.

If submodules are introduced later, use:

```bash
git submodule update --init --recursive
```

#### Step 3: Install pinned tool versions

Tool versions are pinned in `mise.toml` to reduce local-vs-CI drift.

```bash
mise install
make bootstrap
```

`make bootstrap` validates required tools and expected versions (for example shellcheck, bats, gitleaks, shfmt, actionlint).

#### Step 4: Learn command entrypoints

This repo supports both:

- `make` (source of truth for task logic)
- `just` (shortcut command UX over Make targets)

Discover commands:

```bash
make help
just --list
```

Common commands:

```bash
just bootstrap
just fmt
just lint
just validate
just test
just preflight
just secret-check
```

#### Step 5: Understand repository layout

- `deploy-tools/bin/`: deployment/remote execution entrypoint scripts.
- `scripts/`: utility scripts for scaffolding, validation, and policy checks.
- `lib/`: shared Bash libraries reused across scripts.
- `env/`: explicit environment profiles (`dev`, `staging`, `prod`).
- `schemas/`: JSON schemas used for config validation.
- `tests/bats/`: regression tests for script behavior.
- `docs/`: detailed setup, policy, and security runbooks.

#### Step 6: Run an example workflow safely

Mutating scripts should be run in preview mode first, then execute mode.

```bash
# 1) preview intended actions (no side effects)
deploy-tools/bin/deploy-project.sh   --env staging   --dry-run   deploy-tools/projects/jukebotx.env.example

# 2) execute only after reviewing output
deploy-tools/bin/deploy-project.sh   --env staging   --execute   deploy-tools/projects/jukebotx.env.example
```

Production safety guardrails require both `--env prod` and `--allow-prod`.

#### Step 7: Validate configuration changes

Whenever you update environment profiles or schema-sensitive config, run:

```bash
make validate-config
```

#### Step 8: Run pre-PR checks

Before opening a PR, run:

```bash
make preflight
make secret-check
```

This aligns your local checks with CI expectations.

#### Step 9: Create new scripts the repo-standard way

Use the scaffold helper instead of writing script boilerplate from scratch:

```bash
scripts/scaffold-script.sh --execute scripts/my-new-task.sh
```

The scaffold includes strict mode, common helper wiring, argument parsing, and safety-mode structure.

### Troubleshooting / next docs to read

- Development setup: [docs/development-setup.md](docs/development-setup.md)
- Script metadata standard/index: [docs/scripts-metadata.md](docs/scripts-metadata.md)
- Secrets handling guidance: [docs/security/secrets-handling.md](docs/security/secrets-handling.md)
- Secret leak remediation: [docs/security/secret-leak-remediation.md](docs/security/secret-leak-remediation.md)

## Development environment bootstrap

Tool versions are pinned in `mise.toml` to reduce local-vs-CI drift.

- Initial setup: `mise install && make bootstrap`
- Refresh after version bumps: `mise install --upgrade && make bootstrap`

See [docs/development-setup.md](docs/development-setup.md) for the full setup workflow.

## Task shortcuts with `just`

This repository includes a `justfile` as a thin wrapper over existing Make targets for better command discovery via `just --list`.

- Make remains the source of truth for task logic.
- CI continues to call `make` targets directly to avoid build-system churn during the transition.

Common workflows:

```bash
just --list
just bootstrap
just lint
just fmt
just validate
just test
just preflight
just secret-check
```

Each `just` recipe delegates to the corresponding `make` target.

## VS Code Dev Container workflow

This repository includes `.devcontainer/devcontainer.json` so contributors can use a consistent containerized environment from VS Code.

### Open in Container

1. Install the VS Code **Dev Containers** extension.
2. Open this repository in VS Code.
3. Run `Dev Containers: Reopen in Container` from the command palette.

### What gets installed

On first container creation, the dev container setup installs the required CLI tools:

- `bash`
- `make`
- `python3`
- `shellcheck`
- `bats`
- `gitleaks`
- `pre-commit`

Recommended VS Code extensions are also added automatically:

- ShellCheck integration (`timonwong.shellcheck`)
- YAML support (`redhat.vscode-yaml`)
- Markdown lint (`DavidAnson.vscode-markdownlint`)

### Expected first-run behavior

- The first build can take a few minutes while base packages and tooling are installed.
- After container creation, `postCreateCommand` runs `pre-commit install` automatically.
- On your first commit in-container, repository hooks run as configured in `.pre-commit-config.yaml`.

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

`check-fmt` is included in `make preflight`, runs in CI (`.github/workflows/script-tests.yml`), and is enforced by pre-commit hooks (`.pre-commit-config.yaml`). Formatting checks use Bash parsing mode (`-ln=bash`) across these script paths. When `shfmt` is not installed, local runs are skipped with a warning; GitHub Actions CI remains strict.

`validate-config` also runs in CI (`.github/workflows/script-tests.yml`) and in pre-commit hooks (`.pre-commit-config.yaml`).

GitHub workflow files (`.github/workflows/*.yml`) are linted with `actionlint` via `make lint-workflows` locally and in CI.

## Secret scanning and secure configuration hygiene

This repository now enforces secret scanning in both local developer workflow and CI:

- pre-commit hook: `gitleaks` runs before each commit,
- CI workflow: `.github/workflows/secret-scanning.yml` runs the same scan for pushes/PRs,
- policy check: `scripts/check-sensitive-files-excluded.sh` validates ignore rules and sensitive-file tracking.

Setup and run locally:

```bash
pre-commit install --hook-type pre-commit --hook-type pre-push
pre-commit run --all-files
scripts/check-sensitive-files-excluded.sh
```

Recommended commit-time behavior:

- `pre-commit` hooks are optimized for fast local feedback (typically a few seconds on incremental commits), including formatting, changed-file shell linting, and config/secret policy checks.
- `pre-push` hooks can run slower checks such as `make test-scripts` (Bats) before code leaves your workstation.
- CI remains the source of truth for heavier checks and enforces Bats even when local tooling is missing.

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

CI now uses two tiers in `.github/workflows/script-tests.yml`:

- fast path (push + pull request): format check, shell lint, workflow lint (`actionlint`), and config validation,
- full path (push): all fast-path checks plus `make test-scripts` (Bats).

Suggested local workflow before opening a PR:

- fast path equivalent: `make check-fmt lint-scripts lint-workflows validate-config`,
- full path equivalent: `make preflight` (includes Bats when installed).

CI runs these checks automatically in `.github/workflows/script-tests.yml` on pushes and pull requests.
