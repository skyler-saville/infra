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
Usage: deploy-project.sh --env <dev|staging|prod> [--allow-prod] /path/to/project.env

Options:
  --env <name>    Environment profile to load (required)
  --allow-prod    Required safeguard to run with --env prod
USAGE
}

ENV_NAME=""
ALLOW_PROD=false
CONF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ -z "$CONF" || ! -f "$CONF" ]]; then
  usage
  exit_with 2 "A valid project env file is required"
fi

load_infra_profile "$ENV_NAME" "$ALLOW_PROD" DEPLOY_LOCK_DIR DEPLOY_GIT_REMOTE

# shellcheck disable=SC1090
source "$CONF"

: "${APP_DIR:?APP_DIR required}"
: "${BRANCH:=main}"
: "${MAKE_TARGET_DEPLOY:=deploy}"
: "${MAKE_TARGET_HEALTH:=health}"
: "${HEALTH_TIMEOUT_SECS:=30}"

export PATH="/usr/local/bin:/usr/bin:/bin"
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

PREV_COMMIT="$(git -C "$APP_DIR" rev-parse HEAD)"

retry_with_backoff 3 1 git -C "$APP_DIR" fetch "$DEPLOY_GIT_REMOTE" "$BRANCH"
git -C "$APP_DIR" show-ref --verify --quiet "refs/remotes/$DEPLOY_GIT_REMOTE/$BRANCH" || \
  die "$DEPLOY_GIT_REMOTE/$BRANCH not found after fetch"

REMOTE_COMMIT="$(git -C "$APP_DIR" rev-parse "$DEPLOY_GIT_REMOTE/$BRANCH")"

if [[ "$PREV_COMMIT" == "$REMOTE_COMMIT" ]]; then
  info "No changes."
  exit 0
fi

info "Updating $APP_DIR: $PREV_COMMIT -> $REMOTE_COMMIT"
git -C "$APP_DIR" reset --hard "$DEPLOY_GIT_REMOTE/$BRANCH"

info "Deploying via make $MAKE_TARGET_DEPLOY"
if ! make -C "$APP_DIR" "$MAKE_TARGET_DEPLOY"; then
  error "Deploy failed. Rolling back to $PREV_COMMIT"
  git -C "$APP_DIR" reset --hard "$PREV_COMMIT"
  make -C "$APP_DIR" "$MAKE_TARGET_DEPLOY" || true
  exit 1
fi

# Optional health check: only run if the target exists
if make -C "$APP_DIR" -qp 2>/dev/null | awk -F: '/^[a-zA-Z0-9][^$#[:space:]]*:/ {print $1}' | grep -Fxq "$MAKE_TARGET_HEALTH"; then
  info "Health check via make $MAKE_TARGET_HEALTH (timeout ${HEALTH_TIMEOUT_SECS}s)"
  deadline=$((SECONDS + HEALTH_TIMEOUT_SECS))
  until make -C "$APP_DIR" "$MAKE_TARGET_HEALTH"; do
    if (( SECONDS >= deadline )); then
      error "Health check failed. Rolling back to $PREV_COMMIT"
      git -C "$APP_DIR" reset --hard "$PREV_COMMIT"
      make -C "$APP_DIR" "$MAKE_TARGET_DEPLOY" || true
      exit 1
    fi
    sleep 1
  done
else
  warn "No health target '$MAKE_TARGET_HEALTH' found; skipping health check."
fi

info "Deploy OK."
