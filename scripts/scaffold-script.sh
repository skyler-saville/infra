#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"

setup_cleanup_trap

usage() {
  cat <<'USAGE'
Usage: scaffold-script.sh (--dry-run|--execute) <output-path>

Generate a Bash script scaffold with strict mode, structured logging,
argument parsing, preflight checks, and maintenance notes.

Options:
  -h, --help    Show this help message
  --dry-run     Required safety mode; print planned actions only
  --execute     Create the scaffold file

Examples:
  scaffold-script.sh --dry-run scripts/rotate-logs.sh
  scaffold-script.sh --execute tools/new-script
USAGE
}

DRY_RUN=false
MODE_COUNT=0
OUTPUT_PATH=""

run_action() {
  local cmd=("$@")
  if [[ "$DRY_RUN" == true ]]; then
    info "would execute: ${cmd[*]}"
    return 0
  fi

  info "executing: ${cmd[*]}"
  "${cmd[@]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=true
      ((MODE_COUNT += 1))
      shift
      ;;
    --execute)
      DRY_RUN=false
      ((MODE_COUNT += 1))
      shift
      ;;
    -* )
      die "Unknown option: $1"
      ;;
    *)
      OUTPUT_PATH="$1"
      shift
      ;;
  esac
done

if (( MODE_COUNT != 1 )); then
  usage
  exit_with 2 "Choose exactly one mode: --dry-run or --execute"
fi

if [[ -z "$OUTPUT_PATH" ]]; then
  error "output path is required"
  usage
  exit 2
fi

if [[ -e "$OUTPUT_PATH" ]]; then
  die "'$OUTPUT_PATH' already exists"
fi

info "Planned changes summary"
info "  - create parent directory: $(dirname "$OUTPUT_PATH")"
info "  - write scaffold script to: $OUTPUT_PATH"
info "  - set executable bit on: $OUTPUT_PATH"

run_action mkdir -p "$(dirname "$OUTPUT_PATH")"

if [[ "$DRY_RUN" == true ]]; then
  info "would execute: write scaffold template to $OUTPUT_PATH"
else
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
MODE_COUNT=0
VERBOSE=false

run_action() {
  local cmd=("$@")
  if [[ "$DRY_RUN" == true ]]; then
    info "would execute: ${cmd[*]}"
    return 0
  fi

  info "executing: ${cmd[*]}"
  "${cmd[@]}"
}

usage() {
  cat <<'USAGE'
Usage: <script-name> (--dry-run|--execute) [options] [args]

Options:
  -h, --help        Show this help message
      --dry-run     Required safety mode; print planned actions only
      --execute     Apply changes
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
        ((MODE_COUNT += 1))
        shift
        ;;
      --execute)
        DRY_RUN=false
        ((MODE_COUNT += 1))
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

  if (( MODE_COUNT != 1 )); then
    usage
    exit_with 2 "Choose exactly one mode: --dry-run or --execute"
  fi
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

  info "Planned changes summary"
  info "  - add your mutating actions below"

  # Example:
  # run_action mkdir -p /tmp/my-script-output
  # run_action rm -f /tmp/my-script-output/stale-file
  # retry_with_backoff 3 1 curl -fsS https://example.com/healthz

  # TODO: implement script-specific behavior.
  info "Done"
}

main "$@"
SCRIPT_TEMPLATE
fi

run_action chmod +x "$OUTPUT_PATH"
if [[ "$DRY_RUN" == true ]]; then
  info "Dry-run complete. No changes were made."
else
  info "Created scaffold: $OUTPUT_PATH"
fi
