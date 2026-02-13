#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"

setup_cleanup_trap

usage() {
  cat <<'USAGE'
Usage: scaffold-script.sh <output-path>

Generate a Bash script scaffold with strict mode, structured logging,
argument parsing, preflight checks, and maintenance notes.

Options:
  -h, --help    Show this help message

Examples:
  scaffold-script.sh scripts/rotate-logs.sh
  scaffold-script.sh tools/new-script
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

OUTPUT_PATH="${1:-}"
if [[ -z "$OUTPUT_PATH" ]]; then
  error "output path is required"
  usage
  exit 2
fi

if [[ -e "$OUTPUT_PATH" ]]; then
  die "'$OUTPUT_PATH' already exists"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

cat > "$OUTPUT_PATH" <<'SCRIPT_TEMPLATE'
#!/usr/bin/env bash
set -euo pipefail

################################################################################
# NAME: $(basename "$0")
# PURPOSE: <describe what this script does>
# MAINTAINER NOTES:
#   - Keep this script idempotent where possible.
#   - Update usage examples when adding/changing flags.
#   - Prefer explicit preflight checks for all external dependencies.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"

SCRIPT_NAME="$(basename "$0")"
DRY_RUN=false
VERBOSE=false

usage() {
  cat <<'USAGE'
Usage: <script-name> [options] [args]

Options:
  -h, --help        Show this help message
      --dry-run     Print actions without making changes
      --verbose     Enable verbose logging

Examples:
  <script-name> --dry-run
  <script-name> --verbose -- <arg1>
USAGE
}

require_env() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    die "Required environment variable '$var_name' is not set"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        set_verbose "true"
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        error "Unknown option: $1"
        usage
        exit 2
        ;;
      *)
        break
        ;;
    esac
  done

  # Remaining positional args are available in "$@" for your main logic.
  POSITIONAL_ARGS=("$@")
}

preflight_checks() {
  # Add every required tool/env var before doing real work.
  require_cmd bash
  # require_cmd jq
  # require_env API_TOKEN
}

main() {
  parse_args "$@"
  setup_cleanup_trap
  preflight_checks

  info "Starting $SCRIPT_NAME"
  debug "DRY_RUN=$DRY_RUN VERBOSE=$VERBOSE"
  debug "POSITIONAL_ARGS=${POSITIONAL_ARGS[*]:-<none>}"

  if [[ "$DRY_RUN" == true ]]; then
    warn "Dry-run enabled; no changes will be made"
  fi

  # Example:
  # tmp_dir="$(create_temp_dir my-script)"
  # retry_with_backoff 3 1 curl -fsS https://example.com/healthz

  # TODO: implement script-specific behavior.
  info "Done"
}

main "$@"
SCRIPT_TEMPLATE

chmod +x "$OUTPUT_PATH"
info "Created scaffold: $OUTPUT_PATH"
