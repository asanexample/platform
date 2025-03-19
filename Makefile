# Platform Infrastructure Makefile
# This Makefile provides commands for working with the Terraform/Terragrunt infrastructure

# Default shell
SHELL := /bin/bash

# Default variables
ENV ?= dev
REGION ?= westus
CLOUD ?= azure
MODULE ?= all

# Paths
INFRA_DIR := $(CURDIR)/infra
LIVE_DIR := $(INFRA_DIR)/live
MODULES_DIR := $(INFRA_DIR)/modules

# Set specific paths based on inputs
CLOUD_ENV_DIR := $(LIVE_DIR)/$(CLOUD)/$(ENV)
CLOUD_ENV_REGION_DIR := $(CLOUD_ENV_DIR)/$(REGION)

.PHONY: help
help: ## Show this help message
	@echo 'Usage: make [target] [ENV=env] [REGION=region] [CLOUD=cloud] [MODULE=module]'
	@echo ''
	@echo 'Targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ''
	@echo 'Variables:'
	@echo '  ENV: Environment to target (default: dev)'
	@echo '  REGION: Region to target (default: westus)'
	@echo '  CLOUD: Cloud provider to target (default: azure)'
	@echo '  MODULE: Specific module to target (default: all)'

.PHONY: init
init: ## Initialize all modules
	@echo "Initializing $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all init

.PHONY: init-module
init-module: ## Initialize a specific module
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "Initializing module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt init

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
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all apply

.PHONY: apply-module
apply-module: ## Apply a specific module
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "Applying module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION)..."
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt apply

.PHONY: destroy
destroy: ## Destroy all modules (USE WITH CAUTION)
	@echo "WARNING: You are about to destroy all resources in $(CLOUD)/$(ENV)/$(REGION)..."
	@echo "Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]
	@cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all destroy

.PHONY: destroy-module
destroy-module: ## Destroy a specific module (USE WITH CAUTION)
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "WARNING: You are about to destroy module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION)..."
	@echo "Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]
	@cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt destroy

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