SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

ENV ?= dev
SCRIPT_DIRS := deploy-tools/bin scripts lib
TOOLS := $(notdir $(wildcard deploy-tools/bin/*.sh)) $(notdir $(wildcard scripts/*.sh))
SCRIPT_GLOBS := deploy-tools/bin/*.sh scripts/*.sh lib/*.sh
SCRIPT_FILES := $(wildcard $(SCRIPT_GLOBS))
PYTHON_BIN ?= python3

EXPECTED_SHELLCHECK_VERSION := 0.10.0
EXPECTED_BATS_VERSION := 1.11.1
EXPECTED_GITLEAKS_VERSION := 8.24.2
EXPECTED_PYTHON_VERSION := 3.12.9
EXPECTED_SHFMT_VERSION := 3.11.0

.PHONY: help bootstrap preflight fmt-scripts check-fmt lint-scripts test-scripts validate-config secret-check run list-tools

help: ## Show available automation tasks.
	@echo "Available tasks:"
	@awk 'BEGIN {FS = ":.*## "; printf "  %-18s %s\n", "Target", "Description"} /^[a-zA-Z_-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Usage examples:"
	@echo "  make bootstrap"
	@echo "  make preflight"
	@echo "  make lint-scripts"
	@echo "  make validate-config"
	@echo "  make run TOOL=deploy-project.sh ARGS=\"--env dev --dry-run deploy-tools/projects/jukebotx.env.example\""

bootstrap: ## Verify required tooling is installed and version-pinned.
	@set -euo pipefail; \
	missing=0; \
	mismatch=0; \
	check_cmd() { \
		local cmd="$$1"; \
		if ! command -v "$$cmd" >/dev/null 2>&1; then \
			echo "[missing] $$cmd is not installed"; \
			missing=1; \
		fi; \
	}; \
	check_version() { \
		local label="$$1"; \
		local expected="$$2"; \
		local current="$$3"; \
		if [ "$$current" = "$$expected" ]; then \
			echo "[ok] $$label $$current"; \
		else \
			echo "[version-mismatch] $$label expected $$expected but found $$current"; \
			mismatch=1; \
		fi; \
	}; \
	for cmd in bash awk env shellcheck bats gitleaks shfmt $(PYTHON_BIN); do \
		check_cmd "$$cmd"; \
	done; \
	if [ "$$missing" -eq 0 ]; then \
		shellcheck_version="$$(shellcheck --version | awk -F': ' '/version:/ {print $$2}')"; \
		bats_version="$$(bats -v | awk '{print $$2}')"; \
		gitleaks_version="$$(gitleaks version | awk '{print $$1}')"; \
		python_version="$$($(PYTHON_BIN) --version | awk '{print $$2}')"; \
		shfmt_version="$$(shfmt --version | sed 's/^v//')"; \
		check_version shellcheck "$(EXPECTED_SHELLCHECK_VERSION)" "$$shellcheck_version"; \
		check_version bats "$(EXPECTED_BATS_VERSION)" "$$bats_version"; \
		check_version gitleaks "$(EXPECTED_GITLEAKS_VERSION)" "$$gitleaks_version"; \
		check_version $(PYTHON_BIN) "$(EXPECTED_PYTHON_VERSION)" "$$python_version"; \
		check_version shfmt "$(EXPECTED_SHFMT_VERSION)" "$$shfmt_version"; \
	fi; \
	if [ "$$missing" -ne 0 ] || [ "$$mismatch" -ne 0 ]; then \
		echo; \
		echo "bootstrap failed. Install or align tool versions with: mise install"; \
		exit 1; \
	fi; \
	echo "bootstrap checks passed"

lint-scripts: ## Lint shell scripts with shellcheck when available, else syntax-check with bash -n.
	@set -euo pipefail; \
	files="$$(find $(SCRIPT_DIRS) -type f -name '*.sh')"; \
	if [ -z "$$files" ]; then \
		echo "no shell scripts found"; \
		exit 0; \
	fi; \
	if command -v shellcheck >/dev/null 2>&1; then \
		echo "running shellcheck"; \
		shellcheck $$files; \
	else \
		echo "shellcheck not found; running bash -n syntax checks"; \
		for file in $$files; do \
			bash -n "$$file"; \
		done; \
	fi

fmt-scripts: ## Format shell scripts with shfmt.
	@set -euo pipefail; \
	if ! command -v shfmt >/dev/null 2>&1; then \
		if [ "$${GITHUB_ACTIONS:-}" = "true" ]; then \
			echo "shfmt is required for script formatting"; \
			exit 1; \
		fi; \
		echo "warning: shfmt not found; skipping fmt-scripts outside CI"; \
		exit 0; \
	fi; \
	files="$(SCRIPT_FILES)"; \
	if [ -z "$$files" ]; then \
		echo "no shell scripts found"; \
		exit 0; \
	fi; \
	shfmt -w -i 2 -ci -sr -ln=bash $$files

check-fmt: ## Verify shell scripts are formatted with shfmt.
	@set -euo pipefail; \
	if ! command -v shfmt >/dev/null 2>&1; then \
		if [ "$${GITHUB_ACTIONS:-}" = "true" ]; then \
			echo "shfmt is required for formatting checks"; \
			exit 1; \
		fi; \
		echo "warning: shfmt not found; skipping check-fmt outside CI"; \
		exit 0; \
	fi; \
	files="$(SCRIPT_FILES)"; \
	if [ -z "$$files" ]; then \
		echo "no shell scripts found"; \
		exit 0; \
	fi; \
	shfmt -d -i 2 -ci -sr -ln=bash $$files


test-scripts: ## Run shell script safety tests (requires bats).
	@set -euo pipefail; \
	if ! command -v bats >/dev/null 2>&1; then \
		if [ "$${GITHUB_ACTIONS:-}" = "true" ]; then \
			echo "bats is required to run script tests"; \
			exit 1; \
		fi; \
		echo "warning: bats not found; skipping test-scripts outside CI"; \
		exit 0; \
	fi; \
	bats tests/bats


secret-check: ## Run sensitive file policy validation and optional gitleaks scan.
	@set -euo pipefail; \
	scripts/check-sensitive-files-excluded.sh; \
	if command -v gitleaks >/dev/null 2>&1; then \
		echo "running gitleaks working-tree scan"; \
		gitleaks detect --no-git --source . --redact; \
	else \
		echo "gitleaks not found; install pre-commit hooks to run secret scan locally"; \
	fi

validate-config: ## Validate environment profiles against JSON Schema.
	@set -euo pipefail; \
	if ! command -v $(PYTHON_BIN) >/dev/null 2>&1; then \
		echo "$(PYTHON_BIN) is required for config validation"; \
		exit 1; \
	fi; \
	$(PYTHON_BIN) scripts/validate-config.py

run: ## Run a repository script by name. Usage: make run TOOL=<script.sh> ARGS="..."
	@set -euo pipefail; \
	if [ -z "$${TOOL:-}" ]; then \
		echo "TOOL is required. See: make list-tools"; \
		exit 1; \
	fi; \
	if [ -x "deploy-tools/bin/$$TOOL" ]; then \
		target="deploy-tools/bin/$$TOOL"; \
	elif [ -x "scripts/$$TOOL" ]; then \
		target="scripts/$$TOOL"; \
	else \
		echo "unknown tool: $$TOOL"; \
		echo "available tools:"; \
		$(MAKE) --no-print-directory list-tools; \
		exit 1; \
	fi; \
	echo "running $$target $${ARGS:-}"; \
	"$$target" $${ARGS:-}

list-tools: ## List script entry points discoverable by make run.
	@printf '%s\n' $(TOOLS)
preflight: ## Run local preflight checks used before commits.
	@set -euo pipefail; \
	$(MAKE) --no-print-directory check-fmt; \
	$(MAKE) --no-print-directory lint-scripts; \
	$(MAKE) --no-print-directory validate-config; \
	$(MAKE) --no-print-directory test-scripts
