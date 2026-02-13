#!/usr/bin/env bash

# Shared environment profile loader for infrastructure scripts.

# shellcheck source=lib/common.sh
source "${ROOT_DIR:?ROOT_DIR must be set before sourcing env-loader.sh}/lib/common.sh"

load_infra_profile() {
  local env_name="$1"
  local allow_prod="${2:-false}"
  shift 2 || true
  local required_vars=("$@")

  if [[ -z "$env_name" ]]; then
    die "Environment selection is required. Pass --env <dev|staging|prod>."
  fi

  local profile_path="$ROOT_DIR/env/${env_name}.env"
  if [[ ! -f "$profile_path" ]]; then
    die "Environment profile not found: $profile_path"
  fi

  case "$env_name" in
    prod|production)
      if [[ "$allow_prod" != "true" ]]; then
        die "Refusing to run against '$env_name' without --allow-prod."
      fi
      ;;
  esac

  # shellcheck disable=SC1090
  source "$profile_path"

  local var_name
  for var_name in "${required_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
      die "Required variable '$var_name' is not set in $profile_path"
    fi
  done

  info "Execution context"
  info "  profile: $env_name"
  info "  profile file: $profile_path"
  info "  lock dir: ${DEPLOY_LOCK_DIR:-<unset>}"
  info "  git remote: ${DEPLOY_GIT_REMOTE:-<unset>}"
}
