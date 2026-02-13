SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

ENV ?= dev
SCRIPT_DIRS := deploy-tools/bin scripts lib
TOOLS := $(notdir $(wildcard deploy-tools/bin/*.sh)) $(notdir $(wildcard scripts/*.sh))

.PHONY: help bootstrap lint-scripts validate-config run list-tools

help: ## Show available automation tasks.
	@echo "Available tasks:"
	@awk 'BEGIN {FS = ":.*## "; printf "  %-18s %s\n", "Target", "Description"} /^[a-zA-Z_-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Usage examples:"
	@echo "  make bootstrap"
	@echo "  make lint-scripts"
	@echo "  make validate-config ENV=staging"
	@echo "  make run TOOL=deploy-project.sh ARGS=\"--env dev --dry-run deploy-tools/projects/jukebotx.env.example\""

bootstrap: ## Verify required tooling is installed for contributors.
	@missing=0; \
	for cmd in bash awk env; do \
		if ! command -v "$$cmd" >/dev/null 2>&1; then \
			echo "missing dependency: $$cmd"; \
			missing=1; \
		fi; \
	done; \
	if command -v shellcheck >/dev/null 2>&1; then \
		echo "found optional dependency: shellcheck"; \
	else \
		echo "optional dependency not found: shellcheck (lint will use bash -n fallback)"; \
	fi; \
	if [ "$$missing" -ne 0 ]; then \
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

validate-config: ## Validate required env profile variables (ENV=dev|staging|prod).
	@set -euo pipefail; \
	env_file="env/$(ENV).env"; \
	if [ ! -f "$$env_file" ]; then \
		echo "missing environment file: $$env_file"; \
		exit 1; \
	fi; \
	set -a; \
	source "$$env_file"; \
	set +a; \
	for required in DEPLOY_LOCK_DIR DEPLOY_GIT_REMOTE; do \
		if [ -z "$${!required:-}" ]; then \
			echo "$$env_file is missing required variable: $$required"; \
			exit 1; \
		fi; \
	done; \
	echo "validated $$env_file"

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
