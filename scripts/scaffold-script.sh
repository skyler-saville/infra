#!/usr/bin/env bash
set -euo pipefail

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
  echo "ERROR: output path is required" >&2
  usage
  exit 2
fi

if [[ -e "$OUTPUT_PATH" ]]; then
  echo "ERROR: '$OUTPUT_PATH' already exists" >&2
  exit 1
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

info() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

error() {
  printf '[ERROR] %s\n' "$*" >&2
}

debug() {
  if [[ "$VERBOSE" == true ]]; then
    printf '[DEBUG] %s\n' "$*"
  fi
}

require_bin() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    error "Required binary '$bin' not found in PATH"
    exit 1
  fi
}

require_env() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    error "Required environment variable '$var_name' is not set"
    exit 1
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
  require_bin bash
  # require_bin jq
  # require_env API_TOKEN
}

main() {
  parse_args "$@"
  preflight_checks

  info "Starting $SCRIPT_NAME"
  debug "DRY_RUN=$DRY_RUN VERBOSE=$VERBOSE"
  debug "POSITIONAL_ARGS=${POSITIONAL_ARGS[*]:-<none>}"

  if [[ "$DRY_RUN" == true ]]; then
    warn "Dry-run enabled; no changes will be made"
  fi

  # TODO: implement script-specific behavior.
  info "Done"
}

main "$@"
SCRIPT_TEMPLATE

chmod +x "$OUTPUT_PATH"
echo "Created scaffold: $OUTPUT_PATH"
