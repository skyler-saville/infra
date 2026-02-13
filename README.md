# infra

## Shared Bash helpers

Common reusable shell helpers live in `lib/common.sh`, including:

- structured log formatting (`info`, `warn`, `error`, `debug`),
- retry with exponential backoff (`retry_with_backoff`),
- safe temp-directory lifecycle and exit cleanup trap (`create_temp_dir`, `setup_cleanup_trap`),
- command dependency checks (`require_cmd`, `require_cmds`),
- normalized error/exit helpers (`die`, `exit_with`).

Source this file in repository scripts to avoid copy/pasted utility logic.

## Script scaffold for maintainers

Use `scripts/scaffold-script.sh` to create new Bash scripts with:

- strict mode (`set -euo pipefail`),
- shared helpers from `lib/common.sh`,
- argument parsing scaffold (`--help`, `--dry-run`, `--verbose`),
- preflight checks for required binaries/environment variables,
- usage examples and inline maintenance notes.

Example:

```bash
scripts/scaffold-script.sh scripts/my-new-task.sh
```

Then edit the generated file to fill in the TODOs for script-specific behavior,
preflight requirements, and examples.
