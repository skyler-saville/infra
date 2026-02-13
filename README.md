# infra

## Script scaffold for maintainers

Use `scripts/scaffold-script.sh` to create new Bash scripts with:

- strict mode (`set -euo pipefail`),
- structured log helpers (`info`, `warn`, `error`),
- argument parsing scaffold (`--help`, `--dry-run`, `--verbose`),
- preflight checks for required binaries/environment variables,
- usage examples and inline maintenance notes.

Example:

```bash
scripts/scaffold-script.sh scripts/my-new-task.sh
```

Then edit the generated file to fill in the TODOs for script-specific behavior,
preflight requirements, and examples.
