#!/usr/bin/env bash

# Shared helpers for Bash scripts in this repository.

COMMON_VERBOSE="${COMMON_VERBOSE:-false}"
_COMMON_TRAP_INSTALLED="${_COMMON_TRAP_INSTALLED:-false}"
declare -ag COMMON_TEMP_DIRS=()

_log() {
  local level="$1"
  shift
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf '[%s] [%s] %s\n' "$ts" "$level" "$*"
}

info() {
  _log "INFO" "$@"
}

warn() {
  _log "WARN" "$@" >&2
}

error() {
  _log "ERROR" "$@" >&2
}

debug() {
  if [[ "$COMMON_VERBOSE" == "true" ]]; then
    _log "DEBUG" "$@"
  fi
}

set_verbose() {
  COMMON_VERBOSE="$1"
}

exit_with() {
  local code="$1"
  shift
  if [[ $# -gt 0 ]]; then
    error "$@"
  fi
  exit "$code"
}

die() {
  local message="$1"
  local code="${2:-1}"
  exit_with "$code" "$message"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "Required command '$cmd' not found in PATH" 1
  fi
}

require_cmds() {
  local cmd
  for cmd in "$@"; do
    require_cmd "$cmd"
  done
}

_cleanup_temp_dirs() {
  local dir
  for dir in "${COMMON_TEMP_DIRS[@]:-}"; do
    if [[ -n "$dir" && -d "$dir" ]]; then
      rm -rf "$dir"
      debug "Removed temp dir: $dir"
    fi
  done
}

common_cleanup() {
  local code="$?"
  _cleanup_temp_dirs
  return "$code"
}

setup_cleanup_trap() {
  if [[ "$_COMMON_TRAP_INSTALLED" != "true" ]]; then
    trap common_cleanup EXIT
    _COMMON_TRAP_INSTALLED="true"
  fi
}

create_temp_dir() {
  local prefix="${1:-infra}"
  local temp_dir
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX")"
  COMMON_TEMP_DIRS+=("$temp_dir")
  debug "Created temp dir: $temp_dir"
  printf '%s\n' "$temp_dir"
}

retry_with_backoff() {
  local max_attempts="$1"
  local delay_secs="$2"
  shift 2

  if [[ "$max_attempts" -lt 1 ]]; then
    die "max_attempts must be >= 1" 2
  fi

  local attempt=1
  local current_delay="$delay_secs"
  while true; do
    if "$@"; then
      return 0
    fi

    if (( attempt >= max_attempts )); then
      error "Command failed after $attempt attempts: $*"
      return 1
    fi

    warn "Attempt $attempt failed. Retrying in ${current_delay}s: $*"
    sleep "$current_delay"
    attempt=$((attempt + 1))
    current_delay=$((current_delay * 2))
  done
}
