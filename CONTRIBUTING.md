# Contributing

Thanks for contributing to this repository.

## Local setup

1. Install pinned toolchains and utilities:
   ```bash
   mise install
   ```
2. Bootstrap local developer dependencies and hooks:
   ```bash
   make bootstrap
   ```

## Required pre-PR checks

Before opening a pull request, run:

```bash
make preflight
make secret-check
```

PRs should include confirmation that both commands were run successfully (or note any environment limitation that prevented a full run).

## Commit and branch naming conventions

### Branch names

Use descriptive, scoped branch names:

- `feat/<short-description>`
- `fix/<short-description>`
- `chore/<short-description>`
- `docs/<short-description>`
- `ops/<short-description>`

Examples:

- `feat/add-preflight-smoke-tests`
- `docs/update-contributing-guide`

### Commit messages

Use Conventional Commit style where practical:

- `feat: add staged rollout support`
- `fix: handle empty environment file`
- `docs: add pull request template`

Keep subject lines concise and imperative. Add context in the body when behavior, risk, or rollout considerations are non-trivial.

## Safety expectations for script execution modes

Operational scripts in this repository are expected to support explicit safety modes.

### `--dry-run`

`--dry-run` must be safe and non-mutating:

- Performs validation and planning logic.
- Prints intended actions (for example, `would execute: ...`).
- Produces **no** side effects in local or remote environments.

### `--execute`

`--execute` is the explicit opt-in for mutating behavior:

- Runs the actual changes.
- Should only proceed after argument validation and safety checks.
- Should provide clear logging so reviewers/operators can trace what happened.

Scripts must not perform mutating actions by default when neither flag is provided; they should fail with usage guidance or require explicit mode selection.
