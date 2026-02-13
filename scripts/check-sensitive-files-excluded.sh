#!/usr/bin/env bash
set -euo pipefail

required_patterns=(
  ".env"
  ".env.*"
  "*.local"
  "config/*.secrets.*"
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fqx "$pattern" .gitignore; then
    echo "Missing required ignore pattern in .gitignore: ${pattern}" >&2
    exit 1
  fi
done

tracked_sensitive_files="$(git ls-files | rg '(^|/)\.env($|\.)|(^|/)config/.*(secret|secrets).*(\.ya?ml|\.json|\.toml|\.ini)$' || true)"

if [[ -n "$tracked_sensitive_files" ]]; then
  echo "Tracked files that look sensitive were found:" >&2
  echo "$tracked_sensitive_files" >&2
  exit 1
fi

echo "Sensitive file exclusion policy checks passed."
