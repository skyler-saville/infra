#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORKDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORKDIR"
}

create_deploy_fixture() {
  local base="$1"
  local origin="$base/origin.git"
  local app="$base/app"

  mkdir -p "$base"
  git init --bare "$origin" >/dev/null
  git clone "$origin" "$app" >/dev/null

  cat > "$app/Makefile" <<'MAKEFILE'
.PHONY: deploy health

deploy:
	@echo "deploy target"

health:
	@echo "health target"
MAKEFILE

  (
    cd "$app"
    git add Makefile
    git -c user.name='Test Bot' -c user.email='test@example.com' commit -m 'initial commit' >/dev/null
    git push origin HEAD:main >/dev/null
  )

  # Remote advances by one commit so dry-run has a planned update.
  git clone "$origin" "$base/advance" >/dev/null
  (
    cd "$base/advance"
    git checkout -b main origin/main >/dev/null
    echo "v2" > VERSION
    git add VERSION
    git -c user.name='Test Bot' -c user.email='test@example.com' commit -m 'advance remote' >/dev/null
    git push origin main >/dev/null
  )

  cat > "$base/project.env" <<EOF_ENV
APP_DIR=$app
BRANCH=main
MAKE_TARGET_DEPLOY=deploy
MAKE_TARGET_HEALTH=health
EOF_ENV
}

@test "scaffold-script shows help output" {
  run "$REPO_ROOT/scripts/scaffold-script.sh" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: scaffold-script.sh"* ]]
}

@test "scaffold-script rejects invalid option" {
  run "$REPO_ROOT/scripts/scaffold-script.sh" --bogus

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option: --bogus"* ]]
}

@test "scaffold-script dry-run does not create files" {
  target="$WORKDIR/generated/new-script.sh"

  run "$REPO_ROOT/scripts/scaffold-script.sh" --dry-run "$target"

  [ "$status" -eq 0 ]
  [ ! -e "$target" ]
  [[ "$output" == *"Dry-run complete. No changes were made."* ]]
}

@test "deploy-project shows help output" {
  run "$REPO_ROOT/deploy-tools/bin/deploy-project.sh" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy-project.sh"* ]]
}

@test "deploy-project fails when required dependency is missing" {
  fixture="$WORKDIR/deps"
  create_deploy_fixture "$fixture"

  run env PATH="/nonexistent" "$REPO_ROOT/deploy-tools/bin/deploy-project.sh" \
    --execute --env dev "$fixture/project.env"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Required command 'git' not found in PATH"* ]]
}

@test "deploy-project dry-run does not mutate local checkout" {
  fixture="$WORKDIR/dry-run"
  create_deploy_fixture "$fixture"
  before_head="$(git -C "$fixture/app" rev-parse HEAD)"

  run "$REPO_ROOT/deploy-tools/bin/deploy-project.sh" \
    --dry-run --env dev "$fixture/project.env"

  [ "$status" -eq 0 ]
  after_head="$(git -C "$fixture/app" rev-parse HEAD)"
  [ "$before_head" = "$after_head" ]
  [[ "$output" == *"Dry-run complete. No changes were made."* ]]
}

@test "deploy-project returns non-zero when app dir is not a git repo" {
  fixture="$WORKDIR/invalid-state"
  mkdir -p "$fixture/not-a-repo"
  cat > "$fixture/project.env" <<EOF_ENV
APP_DIR=$fixture/not-a-repo
EOF_ENV

  run "$REPO_ROOT/deploy-tools/bin/deploy-project.sh" \
    --execute --env dev "$fixture/project.env"

  [ "$status" -ne 0 ]
  [[ "$output" == *"is not a git repository"* ]]
}
