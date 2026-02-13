#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/env-loader.sh
source "$ROOT_DIR/lib/env-loader.sh"

set_verbose "${VERBOSE:-false}"
setup_cleanup_trap

usage() {
  cat <<'USAGE'
Usage: deploy-project.sh (--dry-run|--execute|--checklist) --env <dev|staging|prod> [--allow-prod] /path/to/project.env

Options:
  --dry-run       Required safety mode; print planned actions only
  --execute       Apply deployment changes
  --checklist     Print pre-execution safety checklist and exit
  --env <name>    Environment profile to load (required)
  --allow-prod    Required safeguard to run with --env prod
USAGE
}

print_checklist() {
  local conf_path="${1:-}"
  local app_dir="<from project env>"
  local branch="main"

  if [[ -n "$conf_path" && -f "$conf_path" ]]; then
    # shellcheck disable=SC1090
    source "$conf_path"
    app_dir="${APP_DIR:-$app_dir}"
    branch="${BRANCH:-$branch}"
  fi

  cat <<EOF_CHECKLIST
Deployment execution checklist

Targeted resources:
  - Environment profile: env/${ENV_NAME}.env
  - Project configuration file: ${conf_path:-<required path/to/project.env>}
  - Application repository: ${app_dir}
  - Git branch and remote: ${DEPLOY_GIT_REMOTE}/${branch}
  - Deploy lock directory: ${DEPLOY_LOCK_DIR}

Permissions required:
  - Read/write access to application repository and lock directory
  - Ability to run: git, make, flock, awk, grep, mkdir
  - Network access to git remote '${DEPLOY_GIT_REMOTE}'

Backup/rollback readiness:
  - Script captures previous commit before deployment (PREV_COMMIT)
  - Automatic rollback resets to PREV_COMMIT on deploy/health-check failure
  - Ensure your runbook includes service-level rollback verification steps

Confirmation prompts required before execution:
  - Use --execute to apply changes (default workflow should start with --dry-run)
  - Use --allow-prod when --env prod is selected
  - Validate on-call and change-window approvals before running --execute
EOF_CHECKLIST
}

ENV_NAME=""
ALLOW_PROD=false
CONF=""
DRY_RUN=false
MODE_COUNT=0
CHECKLIST_ONLY=false

run_action() {
  local cmd=()
  cmd=("$@")
  if [[ "$DRY_RUN" == true ]]; then
    info "would execute: ${cmd[*]}"
    return 0
  fi

  info "executing: ${cmd[*]}"
  "${cmd[@]}"
}

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
    -h|--help)
      usage
      exit 0
      ;;
    -* )
      die "Unknown option: $1"
      ;;
    *)
      CONF="$1"
      shift
      ;;
  esac
done

if (( MODE_COUNT != 1 )); then
  usage
  exit_with 2 "Choose exactly one mode: --dry-run, --execute, or --checklist"
fi

if [[ -z "$CONF" || ! -f "$CONF" ]]; then
  usage
  exit_with 2 "A valid project env file is required"
fi

load_infra_profile "$ENV_NAME" "$ALLOW_PROD" DEPLOY_LOCK_DIR DEPLOY_GIT_REMOTE

if [[ "$CHECKLIST_ONLY" == true ]]; then
  print_checklist "$CONF"
  exit 0
fi

# shellcheck disable=SC1090
source "$CONF"

: "${APP_DIR:?APP_DIR required}"
: "${BRANCH:=main}"
: "${MAKE_TARGET_DEPLOY:=deploy}"
: "${MAKE_TARGET_HEALTH:=health}"
: "${HEALTH_TIMEOUT_SECS:=30}"

# Keep a deterministic command search path in automation, while allowing
# tests to override it to validate dependency checks.
export PATH="${DEPLOY_PATH_OVERRIDE:-/usr/local/bin:/usr/bin:/bin}"
require_cmds git make flock awk grep mkdir

mkdir -p "$DEPLOY_LOCK_DIR"

# Prevent overlapping deploys (requires util-linux 'flock')
LOCK_FILE="$DEPLOY_LOCK_DIR/deploy-$(basename "$APP_DIR").lock"
exec 9>"$LOCK_FILE"
flock -n 9 || { info "Deploy already running."; exit 0; }

if ! git -C "$APP_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "$APP_DIR is not a git repository"
fi

info "Selected target"
info "  app dir: $APP_DIR"
info "  branch: $BRANCH"
info "  deploy target: $MAKE_TARGET_DEPLOY"
info "  health target: $MAKE_TARGET_HEALTH"
if [[ "$DRY_RUN" == true ]]; then
  info "  mode: dry-run"
else
  info "  mode: execute"
fi

PREV_COMMIT="$(git -C "$APP_DIR" rev-parse HEAD)"

if [[ "$DRY_RUN" == true ]]; then
  REMOTE_COMMIT="$(git -C "$APP_DIR" ls-remote "$DEPLOY_GIT_REMOTE" "refs/heads/$BRANCH" | awk '{print $1}')"
  [[ -n "$REMOTE_COMMIT" ]] || die "$DEPLOY_GIT_REMOTE/$BRANCH not found via ls-remote"
else
  retry_with_backoff 3 1 git -C "$APP_DIR" fetch "$DEPLOY_GIT_REMOTE" "$BRANCH"
  git -C "$APP_DIR" show-ref --verify --quiet "refs/remotes/$DEPLOY_GIT_REMOTE/$BRANCH" || \
    die "$DEPLOY_GIT_REMOTE/$BRANCH not found after fetch"
  REMOTE_COMMIT="$(git -C "$APP_DIR" rev-parse "$DEPLOY_GIT_REMOTE/$BRANCH")"
fi

if [[ "$PREV_COMMIT" == "$REMOTE_COMMIT" ]]; then
  info "No changes."
  exit 0
fi

info "Planned changes summary"
info "  - update git checkout: $PREV_COMMIT -> $REMOTE_COMMIT"
info "  - run deploy target: make -C $APP_DIR $MAKE_TARGET_DEPLOY"

HAS_HEALTH_TARGET=false
if make -C "$APP_DIR" -qp 2>/dev/null | awk -F: '/^[a-zA-Z0-9][^$#[:space:]]*:/ {print $1}' | grep -Fxq "$MAKE_TARGET_HEALTH"; then
  HAS_HEALTH_TARGET=true
  info "  - run health target: make -C $APP_DIR $MAKE_TARGET_HEALTH"
else
  info "  - skip health target: $MAKE_TARGET_HEALTH (not found)"
fi

run_action git -C "$APP_DIR" reset --hard "$DEPLOY_GIT_REMOTE/$BRANCH"

if ! run_action make -C "$APP_DIR" "$MAKE_TARGET_DEPLOY"; then
  error "Deploy failed. Rolling back to $PREV_COMMIT"
  run_action git -C "$APP_DIR" reset --hard "$PREV_COMMIT"
  run_action make -C "$APP_DIR" "$MAKE_TARGET_DEPLOY" || true
  exit 1
fi

# Optional health check: only run if the target exists
if [[ "$HAS_HEALTH_TARGET" == true ]]; then
  info "Health check via make $MAKE_TARGET_HEALTH (timeout ${HEALTH_TIMEOUT_SECS}s)"
  deadline=$((SECONDS + HEALTH_TIMEOUT_SECS))
  until run_action make -C "$APP_DIR" "$MAKE_TARGET_HEALTH"; do
    if (( SECONDS >= deadline )); then
      error "Health check failed. Rolling back to $PREV_COMMIT"
      run_action git -C "$APP_DIR" reset --hard "$PREV_COMMIT"
      run_action make -C "$APP_DIR" "$MAKE_TARGET_DEPLOY" || true
      exit 1
    fi
    sleep 1
  done
else
  warn "No health target '$MAKE_TARGET_HEALTH' found; skipping health check."
fi

if [[ "$DRY_RUN" == true ]]; then
  info "Dry-run complete. No changes were made."
else
  info "Deploy OK."
fi
