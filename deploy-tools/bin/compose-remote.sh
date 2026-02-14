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
Usage: compose-remote.sh (--dry-run|--execute|--checklist) --env <dev|staging|prod> [options]

Deploy docker compose to a remote host over ssh, supporting cascading compose override files.

Options:
  --dry-run                    Required safety mode; print planned actions only
  --execute                    Apply deployment changes
  --checklist                  Print pre-execution safety checklist and exit
  --env <name>                 Environment profile to load (required)
  --allow-prod                 Required safeguard to run with --env prod
  --project-env <path>         Optional project env file with defaults
  --host <ssh-target>          SSH target (for example: deploy@example.com)
  --remote-dir <path>          Remote working directory containing compose files
  --compose-file <path>        Compose file; can be repeated (applied in order)
  --env-file <path>            Compose env file; can be repeated
  --compose-project-name <n>   Compose project name override
  --service <name>             Optional service to target for pull/up
  --ssh-option <arg>           Additional ssh option; can be repeated
  --no-pull                    Skip docker compose pull before up
USAGE
}

join_quoted() {
  local item
  local quoted=()
  for item in "$@"; do
    quoted+=("$(printf '%q' "$item")")
  done
  printf '%s' "${quoted[*]}"
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

remote_action() {
  local remote_cmd="$1"
  local ssh_cmd=(ssh)
  if [[ ${#SSH_OPTIONS[@]} -gt 0 ]]; then
    ssh_cmd+=("${SSH_OPTIONS[@]}")
  fi
  ssh_cmd+=("$SSH_TARGET" bash -lc "$remote_cmd")
  run_action "${ssh_cmd[@]}"
}

print_checklist() {
  cat <<EOF_CHECKLIST
Remote compose deployment checklist

Targeted resources:
  - Environment profile: env/${ENV_NAME}.env
  - Project config file: ${PROJECT_ENV_PATH:-<none>}
  - SSH target: ${SSH_TARGET:-<required --host>}
  - Remote compose directory: ${REMOTE_DIR:-<required --remote-dir>}
  - Compose files (cascade order): ${COMPOSE_FILES[*]:-docker-compose.yml docker-compose.<env>.yml}

Permissions required:
  - SSH access to target host
  - Remote access to Docker daemon for deployment user
  - Ability to run: ssh, bash, docker compose

Backup/rollback readiness:
  - Confirm previous image tags are available in registry/local cache
  - Confirm service rollback command in runbook (for example pinned image digest)
  - Validate a known-good compose override can be re-applied quickly

Confirmation prompts required before execution:
  - Use --execute to apply changes (default workflow should start with --dry-run)
  - Use --allow-prod when --env prod is selected
  - Verify maintenance window and on-call readiness before execution
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
COMPOSE_PROJECT_NAME=""
SERVICE_NAME=""
SKIP_PULL=false

SSH_OPTIONS=()
COMPOSE_FILES=()
COMPOSE_ENV_FILES=()

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
    --compose-file)
      [[ $# -ge 2 ]] || die "--compose-file requires a value"
      COMPOSE_FILES+=("$2")
      shift 2
      ;;
    --env-file)
      [[ $# -ge 2 ]] || die "--env-file requires a value"
      COMPOSE_ENV_FILES+=("$2")
      shift 2
      ;;
    --compose-project-name)
      [[ $# -ge 2 ]] || die "--compose-project-name requires a value"
      COMPOSE_PROJECT_NAME="$2"
      shift 2
      ;;
    --service)
      [[ $# -ge 2 ]] || die "--service requires a value"
      SERVICE_NAME="$2"
      shift 2
      ;;
    --ssh-option)
      [[ $# -ge 2 ]] || die "--ssh-option requires a value"
      SSH_OPTIONS+=("$2")
      shift 2
      ;;
    --no-pull)
      SKIP_PULL=true
      shift
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
: "${COMPOSE_PROJECT_NAME:=${REMOTE_COMPOSE_PROJECT:-}}"

if [[ ${#COMPOSE_FILES[@]} -eq 0 ]]; then
  COMPOSE_FILES+=("docker-compose.yml")
  COMPOSE_FILES+=("docker-compose.${ENV_NAME}.yml")
fi

if [[ "$CHECKLIST_ONLY" == true ]]; then
  print_checklist
  exit 0
fi

[[ -n "$SSH_TARGET" ]] || die "Remote host is required via --host or REMOTE_HOST"
[[ -n "$REMOTE_DIR" ]] || die "Remote directory is required via --remote-dir or REMOTE_APP_DIR"

require_cmds ssh

compose_cmd=(docker compose)
for compose_file in "${COMPOSE_FILES[@]}"; do
  compose_cmd+=( -f "$compose_file" )
done
for env_file in "${COMPOSE_ENV_FILES[@]}"; do
  compose_cmd+=( --env-file "$env_file" )
done
if [[ -n "$COMPOSE_PROJECT_NAME" ]]; then
  compose_cmd+=( --project-name "$COMPOSE_PROJECT_NAME" )
fi

pull_cmd=("${compose_cmd[@]}" pull)
up_cmd=("${compose_cmd[@]}" up -d --remove-orphans)
if [[ -n "$SERVICE_NAME" ]]; then
  pull_cmd+=("$SERVICE_NAME")
  up_cmd+=("$SERVICE_NAME")
fi

info "Planned changes summary"
info "  - remote host: $SSH_TARGET"
info "  - remote dir: $REMOTE_DIR"
info "  - compose files (order): ${COMPOSE_FILES[*]}"
if [[ ${#COMPOSE_ENV_FILES[@]} -gt 0 ]]; then
  info "  - compose env files: ${COMPOSE_ENV_FILES[*]}"
fi
if [[ -n "$COMPOSE_PROJECT_NAME" ]]; then
  info "  - compose project name: $COMPOSE_PROJECT_NAME"
fi
if [[ -n "$SERVICE_NAME" ]]; then
  info "  - service filter: $SERVICE_NAME"
fi

preflight_cmd="$(join_quoted command -v docker) && $(join_quoted docker compose version)"
remote_action "$(join_quoted cd "$REMOTE_DIR") && $preflight_cmd"

if [[ "$SKIP_PULL" == false ]]; then
  remote_action "$(join_quoted cd "$REMOTE_DIR") && $(join_quoted "${pull_cmd[@]}")"
else
  warn "Skipping pull due to --no-pull"
fi

remote_action "$(join_quoted cd "$REMOTE_DIR") && $(join_quoted "${up_cmd[@]}")"

if [[ "$DRY_RUN" == true ]]; then
  info "Dry-run complete. No changes were made."
else
  info "Remote compose deploy completed successfully."
fi
