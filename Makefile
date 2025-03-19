# Platform Infrastructure Makefile
# This Makefile provides commands for working with the Terraform/Terragrunt infrastructure

# Default shell
SHELL := /bin/bash

# Default variables
ENV ?= dev
REGION ?= westus
CLOUD ?= azure
MODULE ?= all
NO_CONFIRM ?= false

# Paths
INFRA_DIR := $(CURDIR)/infra
LIVE_DIR := $(INFRA_DIR)/live
MODULES_DIR := $(INFRA_DIR)/modules

# Set specific paths based on inputs
CLOUD_ENV_DIR := $(LIVE_DIR)/$(CLOUD)/$(ENV)
CLOUD_ENV_REGION_DIR := $(CLOUD_ENV_DIR)/$(REGION)

.PHONY: help
help: ## Show this help message
	@echo 'Usage: make [target] [ENV=env] [REGION=region] [CLOUD=cloud] [MODULE=module] [NO_CONFIRM=true]'
	@echo ''
	@echo 'Targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ''
	@echo 'Variables:'
	@echo '  ENV: Environment to target (default: dev)'
	@echo '  REGION: Region to target (default: westus)'
	@echo '  CLOUD: Cloud provider to target (default: azure)'
	@echo '  MODULE: Specific module to target (default: all)'
	@echo '  NO_CONFIRM: Skip all confirmation prompts (default: false)'

.PHONY: init
init: ## Initialize all modules
	@echo "Initializing $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all init

.PHONY: init-upgrade
init-upgrade: ## Initialize all modules and upgrade dependencies
	@echo "Initializing $(CLOUD)/$(ENV)/$(REGION) with dependency upgrades..."
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all init -upgrade

.PHONY: init-module
init-module: ## Initialize a specific module
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "Initializing module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt init

.PHONY: init-upgrade-module
init-upgrade-module: ## Initialize a specific module and upgrade dependencies
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "Initializing module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION) with dependency upgrades..."
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt init -upgrade

.PHONY: plan
plan: ## Plan all modules
	@echo "Planning $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all plan

.PHONY: plan-module
plan-module: ## Plan a specific module
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "Planning module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt plan

.PHONY: apply
apply: ## Apply all modules
	@echo "Applying $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all apply -auto-approve

.PHONY: apply-module
apply-module: ## Apply a specific module
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "Applying module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt apply -auto-approve

.PHONY: destroy
destroy: ## Destroy all modules (USE WITH CAUTION)
	@echo "WARNING: You are about to destroy all resources in $(CLOUD)/$(ENV)/$(REGION)..."
	@if [ "$(NO_CONFIRM)" != "true" ]; then \
		echo "Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]; \
	fi
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all destroy -auto-approve

.PHONY: destroy-module
destroy-module: ## Destroy a specific module (USE WITH CAUTION)
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "WARNING: You are about to destroy module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION)..."
	@if [ "$(NO_CONFIRM)" != "true" ]; then \
		echo "Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]; \
	fi
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt destroy -auto-approve

.PHONY: clean
clean: ## Clean Terragrunt cache
	@echo "Cleaning Terragrunt cache in $(CLOUD)/$(ENV)/$(REGION)..."
	@find $(CLOUD_ENV_REGION_DIR) -type d -name ".terragrunt-cache" -prune -exec rm -rf {} \; 2>/dev/null || true

.PHONY: clean-all
clean-all: ## Clean all Terragrunt cache
	@echo "Cleaning all Terragrunt cache..."
	@find $(LIVE_DIR) -type d -name ".terragrunt-cache" -prune -exec rm -rf {} \; 2>/dev/null || true

.PHONY: validate
validate: ## Validate all modules
	@echo "Validating $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all validate

.PHONY: validate-module
validate-module: ## Validate a specific module
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "Validating module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt validate

.PHONY: fmt
fmt: ## Format all Terraform files
	@echo "Formatting Terraform files..."
	@find $(INFRA_DIR) -name "*.tf" -exec terraform fmt {} \;

.PHONY: lint
lint: ## Lint all Terraform files using tflint
	@echo "Linting Terraform files..."
	@find $(MODULES_DIR) -type d -maxdepth 2 -exec sh -c 'cd {} && echo "Linting {}" && tflint || true' \;

.PHONY: deps
deps: ## Check for dependency updates
	@echo "Checking for dependency updates..."
	@cd $(INFRA_DIR) && echo "TODO: Implement dependency checking"

.PHONY: list-modules
list-modules: ## List available modules for a specific cloud/env/region
	@echo "Available modules in $(CLOUD)/$(ENV)/$(REGION):"
	@find $(CLOUD_ENV_REGION_DIR) -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort

.PHONY: list-regions
list-regions: ## List available regions for a specific cloud/env
	@echo "Available regions in $(CLOUD)/$(ENV):"
	@find $(CLOUD_ENV_DIR) -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort

.PHONY: list-envs
list-envs: ## List available environments for a specific cloud
	@echo "Available environments in $(CLOUD):"
	@find $(LIVE_DIR)/$(CLOUD) -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort

.PHONY: list-clouds
list-clouds: ## List available cloud providers
	@echo "Available cloud providers:"
	@find $(LIVE_DIR) -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort

# Azure-specific commands
.PHONY: login-azure
login-azure: ## Login to Azure
	@echo "Logging in to Azure..."
	@az login

# AWS-specific commands
.PHONY: login-aws
login-aws: ## Login to AWS
	@echo "Configuring AWS credentials..."
	@aws configure

# Cloud-agnostic operations
.PHONY: show-outputs
show-outputs: ## Show outputs for all modules
	@echo "Outputs for $(CLOUD)/$(ENV)/$(REGION):"
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all output

.PHONY: show-outputs-module
show-outputs-module: ## Show outputs for a specific module
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "Outputs for module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION):"
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt output

.PHONY: show-state
show-state: ## Show state for all modules (limited info)
	@echo "State for $(CLOUD)/$(ENV)/$(REGION):"
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all state list

.PHONY: show-state-module
show-state-module: ## Show state for a specific module
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "State for module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION):"
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt state list

.PHONY: plan-file
plan-file: ## Create a plan file for all modules
	@echo "Creating plan file for $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all plan -out=tfplan

.PHONY: plan-file-module
plan-file-module: ## Create a plan file for a specific module
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "Creating plan file for module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt plan -out=tfplan

.PHONY: apply-plan
apply-plan: ## Apply a plan file for all modules
	@echo "Applying plan file for $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all apply tfplan

.PHONY: apply-plan-module
apply-plan-module: ## Apply a plan file for a specific module
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "Applying plan file for module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt apply tfplan

# Testing commands
.PHONY: test
test: ## Run all Terraform tests
	@echo "Running all Terraform tests..."
	@ALL_PASSED=true; \
	TEST_DIRS=( \
		"infra/tests/modules/azure/key_vault" \
		"infra/tests/modules/azure/naming" \
		"infra/tests/modules/azure/networking" \
		"infra/tests/modules/azure/storage_account" \
		"infra/tests/modules/azure/storage_container" \
		"infra/tests/modules/azure/aks_core" \
		"infra/tests/modules/azure/aks_identity" \
		"infra/tests/modules/azure/aks_node_pools" \
	); \
	for dir in "$${TEST_DIRS[@]}"; do \
		if [ -d "$$dir" ]; then \
			echo "=== Running tests in $$dir ==="; \
			(cd "$$dir" && terraform init -input=false && terraform test) || { ALL_PASSED=false; }; \
		else \
			echo "⚠️ Directory $$dir does not exist, skipping"; \
		fi; \
	done; \
	echo "=== Test Results Summary ==="; \
	if [ "$$ALL_PASSED" = true ]; then \
		echo "✅ All tests passed"; \
	else \
		echo "❌ Some tests failed"; \
		exit 1; \
	fi

.PHONY: test-module
test-module: ## Run tests for a specific module
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@TEST_DIR="infra/tests/modules/azure/$(MODULE)"; \
	if [ -d "$$TEST_DIR" ]; then \
		echo "=== Running tests in $$TEST_DIR ==="; \
		cd "$$TEST_DIR" && terraform init -input=false && terraform test; \
	else \
		echo "Error: Test directory $$TEST_DIR does not exist"; \
		exit 1; \
	fi 