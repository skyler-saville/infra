#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/env-loader.sh
source "$ROOT_DIR/lib/env-loader.sh"

setup_cleanup_trap

usage() {
  cat <<'USAGE'
Usage: ssh-project.sh (--dry-run|--execute|--checklist) --env <dev|staging|prod> [options] --command <cmd>

Run audited SSH commands against a deployment target.

Options:
  --dry-run                Required safety mode; print planned actions only
  --execute                Run command on remote host
  --checklist              Print pre-execution safety checklist and exit
  --env <name>             Environment profile to load (required)
  --allow-prod             Required safeguard to run with --env prod
  --project-env <path>     Optional project env file with defaults
  --host <ssh-target>      SSH target (for example: deploy@example.com)
  --remote-dir <path>      Optional remote directory to cd into before command
  --command <cmd>          Command string to execute remotely
  --ssh-option <arg>       Additional ssh option; can be repeated
USAGE
}

run_action() {
  local cmd=("$@")
  if [[ "$DRY_RUN" == true ]]; then
    info "would execute: ${cmd[*]}"
    return 0
  fi

  info "executing: ${cmd[*]}"
  "${cmd[@]}"
}

print_checklist() {
  cat <<EOF_CHECKLIST
SSH execution checklist

Targeted resources:
  - Environment profile: env/${ENV_NAME}.env
  - SSH target: ${SSH_TARGET:-<required --host>}
  - Remote directory: ${REMOTE_DIR:-<none>}
  - Command: ${REMOTE_COMMAND:-<required --command>}

Permissions required:
  - SSH access to target host
  - Sufficient rights for requested remote command

Backup/rollback readiness:
  - Confirm command-level rollback procedure in runbook
  - Capture current state before mutating actions (service status, config snapshot)

Confirmation prompts required before execution:
  - Use --execute to run remote commands (default workflow should start with --dry-run)
  - Use --allow-prod when --env prod is selected
EOF_CHECKLIST
}

ENV_NAME=""
ALLOW_PROD=false
DRY_RUN=false
CHECKLIST_ONLY=false
MODE_COUNT=0
PROJECT_ENV_PATH=""
SSH_TARGET=""
REMOTE_DIR=""
REMOTE_COMMAND=""
SSH_OPTIONS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --checklist)
      CHECKLIST_ONLY=true
      ((MODE_COUNT += 1))
      shift
      ;;
    --env)
      [[ $# -ge 2 ]] || die "--env requires a value"
      ENV_NAME="$2"
      shift 2
      ;;
    --allow-prod)
      ALLOW_PROD=true
      shift
      ;;
    --project-env)
      [[ $# -ge 2 ]] || die "--project-env requires a value"
      PROJECT_ENV_PATH="$2"
      shift 2
      ;;
    --host)
      [[ $# -ge 2 ]] || die "--host requires a value"
      SSH_TARGET="$2"
      shift 2
      ;;
    --remote-dir)
      [[ $# -ge 2 ]] || die "--remote-dir requires a value"
      REMOTE_DIR="$2"
      shift 2
      ;;
    --command)
      [[ $# -ge 2 ]] || die "--command requires a value"
      REMOTE_COMMAND="$2"
      shift 2
      ;;
    --ssh-option)
      [[ $# -ge 2 ]] || die "--ssh-option requires a value"
      SSH_OPTIONS+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -* )
      die "Unknown option: $1"
      ;;
    *)
      die "Unexpected argument: $1"
      ;;
  esac
done

if (( MODE_COUNT != 1 )); then
  usage
  exit_with 2 "Choose exactly one mode: --dry-run, --execute, or --checklist"
fi

load_infra_profile "$ENV_NAME" "$ALLOW_PROD"

if [[ -n "$PROJECT_ENV_PATH" ]]; then
  [[ -f "$PROJECT_ENV_PATH" ]] || die "Project env file not found: $PROJECT_ENV_PATH"
  # shellcheck disable=SC1090
  source "$PROJECT_ENV_PATH"
fi

: "${SSH_TARGET:=${REMOTE_HOST:-}}"
: "${REMOTE_DIR:=${REMOTE_APP_DIR:-}}"

if [[ "$CHECKLIST_ONLY" == true ]]; then
  print_checklist
  exit 0
fi

[[ -n "$SSH_TARGET" ]] || die "Remote host is required via --host or REMOTE_HOST"
[[ -n "$REMOTE_COMMAND" ]] || die "Remote command is required via --command"

require_cmds ssh

remote_cmd="$REMOTE_COMMAND"
if [[ -n "$REMOTE_DIR" ]]; then
  remote_cmd="cd $(printf '%q' "$REMOTE_DIR") && $REMOTE_COMMAND"
fi

ssh_cmd=(ssh)
if [[ ${#SSH_OPTIONS[@]} -gt 0 ]]; then
  ssh_cmd+=("${SSH_OPTIONS[@]}")
fi
ssh_cmd+=("$SSH_TARGET" bash -lc "$remote_cmd")

info "Planned changes summary"
info "  - remote host: $SSH_TARGET"
if [[ -n "$REMOTE_DIR" ]]; then
  info "  - remote dir: $REMOTE_DIR"
fi
info "  - remote command: $REMOTE_COMMAND"

run_action "${ssh_cmd[@]}"

if [[ "$DRY_RUN" == true ]]; then
  info "Dry-run complete. No changes were made."
else
  info "Remote ssh command completed successfully."
fi
