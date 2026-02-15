# Thin task runner wrappers around Make targets.
# Make remains the source of truth for task implementation.

default:
  @just --list

# Verify required tooling is installed and version-pinned.
bootstrap:
  @make --no-print-directory bootstrap

# Run shell and workflow lint checks.
lint:
  @make --no-print-directory lint-scripts
  @make --no-print-directory lint-workflows

# Format shell scripts with shfmt.
fmt:
  @make --no-print-directory fmt-scripts

# Validate environment profiles against JSON Schema.
validate:
  @make --no-print-directory validate-config

# Run shell script safety tests.
test:
  @make --no-print-directory test-scripts

# Run local preflight checks used before commits.
preflight:
  @make --no-print-directory preflight

# Run sensitive file policy validation and optional gitleaks scan.
secret-check:
  @make --no-print-directory secret-check
