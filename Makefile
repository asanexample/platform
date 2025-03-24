# Platform Infrastructure Makefile
# Provides commands for working with Terraform/Terragrunt infrastructure

# Default shell
SHELL := /bin/bash

# Default variables
ENV ?= dev
REGION ?=
CLOUD ?=
MODULE ?= all
NO_CONFIRM ?= false

# Paths
INFRA_DIR := $(CURDIR)/infra
LIVE_DIR := $(INFRA_DIR)/live
MODULES_DIR := $(INFRA_DIR)/modules
TESTS_DIR := $(INFRA_DIR)/tests
AZURE_TESTS_DIR := $(TESTS_DIR)/modules/azure

# Set specific paths based on inputs
CLOUD_ENV_DIR := $(LIVE_DIR)/$(CLOUD)/$(ENV)
CLOUD_ENV_REGION_DIR := $(CLOUD_ENV_DIR)/$(REGION)

# Check required parameters
define check_required_params
	@if [ -z "$(CLOUD)" ]; then \
		echo "Error: CLOUD parameter is required. Example: make $(1) CLOUD=azure REGION=eastus"; \
		exit 1; \
	fi
	@if [ -z "$(REGION)" ]; then \
		echo "Error: REGION parameter is required. Example: make $(1) CLOUD=azure REGION=eastus"; \
		exit 1; \
	fi
endef

# Azure helper function - safely export credentials from Azure CLI to environment
define azure_credentials_export
	AZURE_SUBSCRIPTION_ID=$$(az account show --query id -o tsv); \
	AZURE_TENANT_ID=$$(az account show --query tenantId -o tsv); \
	echo "Using Azure subscription: $$(az account show --query name -o tsv) ($$AZURE_SUBSCRIPTION_ID)"; \
	echo "Tenant ID: $$AZURE_TENANT_ID"; \
	export TF_VAR_azure_subscription_id="$$AZURE_SUBSCRIPTION_ID"; \
	export TF_VAR_azure_tenant_id="$$AZURE_TENANT_ID"; \
	$(1)
endef

# Azure authentication check
define azure_auth_check
	@echo "Checking Azure CLI login status..."; \
	az account show > /dev/null 2>&1 || { echo "Not logged in to Azure CLI. Please run 'make login-azure' first."; exit 1; }; \
	$(call azure_credentials_export,$(1))
endef

# Display help information
.PHONY: help
help: ## Show this help message
	@echo 'Usage: make [target] [ENV=env] [REGION=region] [CLOUD=cloud] [MODULE=module] [NO_CONFIRM=true]'
	@echo ''
	@echo 'Targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ''
	@echo 'Variables:'
	@echo '  ENV: Environment to target (default: dev)'
	@echo '  REGION: Region to target (REQUIRED, no default)'
	@echo '  CLOUD: Cloud provider to target (REQUIRED, no default)'
	@echo '  MODULE: Specific module to target (default: all)'
	@echo '  NO_CONFIRM: Skip all confirmation prompts (default: false)'

# --- Initialize Operations ---

.PHONY: init
init: ## Initialize all modules
	$(call check_required_params,"init")
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all init); \
	else \
		cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all init; \
	fi

.PHONY: init-upgrade
init-upgrade: ## Initialize all modules and upgrade dependencies
	$(call check_required_params,"init-upgrade")
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all init -upgrade); \
	else \
		cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all init -upgrade; \
	fi

.PHONY: init-module
init-module: ## Initialize a specific module
	$(call check_required_params,"init-module")
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt init); \
	else \
		cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt init; \
	fi

.PHONY: init-upgrade-module
init-upgrade-module: ## Initialize a specific module and upgrade dependencies
	$(call check_required_params,"init-upgrade-module")
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt init -upgrade); \
	else \
		cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt init -upgrade; \
	fi

# --- Plan Operations ---

.PHONY: plan
plan: ## Plan all modules
	$(call check_required_params,"plan")
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all plan); \
	else \
		cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all plan; \
	fi

.PHONY: plan-module
plan-module: ## Plan a specific module
	$(call check_required_params,"plan-module")
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt plan); \
	else \
		cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt plan; \
	fi

# --- Apply Operations ---

.PHONY: apply
apply: ## Apply all modules
	$(call check_required_params,"apply")
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all apply -auto-approve); \
	else \
		cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all apply -auto-approve; \
	fi

.PHONY: apply-module
apply-module: ## Apply a specific module
	$(call check_required_params,"apply-module")
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt apply -auto-approve); \
	else \
		cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt apply -auto-approve; \
	fi

# --- Destroy Operations ---

.PHONY: destroy
destroy: ## Destroy all modules (USE WITH CAUTION)
	$(call check_required_params,"destroy")
	@echo "WARNING: You are about to destroy all resources in $(CLOUD)/$(ENV)/$(REGION)..."
	@if [ "$(NO_CONFIRM)" != "true" ]; then \
		read -p "Are you sure? [y/N] " ans && [ $${ans:-N} = y ] || exit 1; \
	fi
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all destroy -auto-approve); \
	else \
		cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all destroy -auto-approve; \
	fi

.PHONY: destroy-module
destroy-module: ## Destroy a specific module (USE WITH CAUTION)
	$(call check_required_params,"destroy-module")
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@echo "WARNING: You are about to destroy module $(MODULE) in $(CLOUD)/$(ENV)/$(REGION)..."
	@if [ "$(NO_CONFIRM)" != "true" ]; then \
		read -p "Are you sure? [y/N] " ans && [ $${ans:-N} = y ] || exit 1; \
	fi
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt destroy -auto-approve); \
	else \
		cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt destroy -auto-approve; \
	fi

# --- Validation Operations ---

.PHONY: validate
validate: ## Validate all modules
	$(call check_required_params,"validate")
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all validate); \
	else \
		cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all validate; \
	fi

.PHONY: validate-module
validate-module: ## Validate a specific module
	$(call check_required_params,"validate-module")
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt validate); \
	else \
		cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt validate; \
	fi

# --- State Operations ---

.PHONY: show-state
show-state: ## Show state for all modules
	$(call check_required_params,"show-state")
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all state list); \
	else \
		cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all state list; \
	fi

.PHONY: show-state-module
show-state-module: ## Show state for a specific module
	$(call check_required_params,"show-state-module")
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt state list); \
	else \
		cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt state list; \
	fi

# --- Output Operations ---

.PHONY: show-outputs
show-outputs: ## Show outputs for all modules
	$(call check_required_params,"show-outputs")
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all output); \
	else \
		cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all output; \
	fi

.PHONY: show-outputs-module
show-outputs-module: ## Show outputs for a specific module
	$(call check_required_params,"show-outputs-module")
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt output); \
	else \
		cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt output; \
	fi

# --- Plan File Operations ---

.PHONY: plan-file
plan-file: ## Create a plan file for all modules
	$(call check_required_params,"plan-file")
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all plan -out=$(CLOUD_ENV_REGION_DIR)/tfplan); \
	else \
		cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all plan -out=$(CLOUD_ENV_REGION_DIR)/tfplan; \
	fi

.PHONY: plan-file-module
plan-file-module: ## Create a plan file for a specific module
	$(call check_required_params,"plan-file-module")
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt plan -out=$(CLOUD_ENV_REGION_DIR)/$(MODULE)/tfplan); \
	else \
		cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt plan -out=$(CLOUD_ENV_REGION_DIR)/$(MODULE)/tfplan; \
	fi

.PHONY: apply-plan
apply-plan: ## Apply a plan file for all modules
	$(call check_required_params,"apply-plan")
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all apply $(CLOUD_ENV_REGION_DIR)/tfplan); \
	else \
		cd $(CLOUD_ENV_REGION_DIR) && terragrunt run-all apply $(CLOUD_ENV_REGION_DIR)/tfplan; \
	fi

.PHONY: apply-plan-module
apply-plan-module: ## Apply a plan file for a specific module
	$(call check_required_params,"apply-plan-module")
	@if [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@if [ "$(CLOUD)" = "azure" ]; then \
		$(call azure_auth_check,cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt apply $(CLOUD_ENV_REGION_DIR)/$(MODULE)/tfplan); \
	else \
		cd $(CLOUD_ENV_REGION_DIR)/$(MODULE) && terragrunt apply $(CLOUD_ENV_REGION_DIR)/$(MODULE)/tfplan; \
	fi

# --- Cleanup Operations ---

.PHONY: clean
clean: ## Clean Terragrunt cache
	$(call check_required_params,"clean")
	@echo "Cleaning Terragrunt cache in $(CLOUD)/$(ENV)/$(REGION)..."
	@find $(CLOUD_ENV_REGION_DIR) -type d -name ".terragrunt-cache" -prune -exec rm -rf {} \; 2>/dev/null || true

.PHONY: clean-all
clean-all: ## Clean all Terragrunt cache
	@echo "Cleaning all Terragrunt cache..."
	@find $(LIVE_DIR) -type d -name ".terragrunt-cache" -prune -exec rm -rf {} \; 2>/dev/null || true

.PHONY: clear-state
clear-state: ## Clear all Terraform state files and locks to start fresh
	@echo "WARNING: You are about to delete all Terraform state and lock files. This is irreversible."
	@if [ "$(NO_CONFIRM)" != "true" ]; then \
		read -p "Are you sure? This will remove all state tracking and cannot be undone. [y/N] " ans && [ $${ans:-N} = y ] || exit 1; \
	fi
	@echo "Clearing all Terraform state files and locks..."
	@find $(LIVE_DIR) -name "terraform.tfstate*" -type f -delete
	@find $(LIVE_DIR) -name ".terraform.lock.hcl" -type f -delete
	@find $(LIVE_DIR) -type d -name ".terraform" -prune -exec rm -rf {} \; 2>/dev/null || true
	@find $(MODULES_DIR) -name ".terraform.lock.hcl" -type f -delete
	@find $(MODULES_DIR) -type d -name ".terraform" -prune -exec rm -rf {} \; 2>/dev/null || true
	@echo "All Terraform state files and locks have been removed. You can now start fresh."

# --- Utility Operations ---

.PHONY: fmt
fmt: ## Format all Terraform files
	@echo "Formatting Terraform files..."
	@find $(INFRA_DIR) -name "*.tf" -exec terraform fmt {} \;

.PHONY: lint
lint: ## Lint all Terraform files using tflint
	@echo "Linting Terraform files..."
	@find $(MODULES_DIR) -type d -maxdepth 2 -exec sh -c 'cd {} && echo "Linting {}" && tflint || true' \;

.PHONY: list-modules
list-modules: ## List available modules for a specific cloud/env/region
	$(call check_required_params,"list-modules")
	@echo "Available modules in $(CLOUD)/$(ENV)/$(REGION):"
	@find $(CLOUD_ENV_REGION_DIR) -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort

.PHONY: list-regions
list-regions: ## List available regions for a specific cloud/env
	@if [ -z "$(CLOUD)" ]; then \
		echo "Error: CLOUD parameter is required. Example: make list-regions CLOUD=azure"; \
		exit 1; \
	fi
	@if [ -z "$(ENV)" ]; then \
		echo "Error: ENV parameter is required. Example: make list-regions CLOUD=azure ENV=dev"; \
		exit 1; \
	fi
	@echo "Available regions in $(CLOUD)/$(ENV):"
	@find $(CLOUD_ENV_DIR) -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort

.PHONY: list-envs
list-envs: ## List available environments for a specific cloud
	@if [ -z "$(CLOUD)" ]; then \
		echo "Error: CLOUD parameter is required. Example: make list-envs CLOUD=azure"; \
		exit 1; \
	fi
	@echo "Available environments in $(CLOUD):"
	@find $(LIVE_DIR)/$(CLOUD) -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort

.PHONY: list-clouds
list-clouds: ## List available cloud providers
	@echo "Available cloud providers:"
	@find $(LIVE_DIR) -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort

# --- Testing Operations ---

.PHONY: setup-test-credentials
setup-test-credentials: ## Set up Azure credentials for Terraform tests
	@echo "Setting up Azure credentials for tests..."
	@infra/tests/setup_azure_credentials.sh

.PHONY: prepare-test-modules
prepare-test-modules: setup-test-credentials ## Prepare all test modules by initializing them
	@echo "Preparing test modules in $(AZURE_TESTS_DIR)..."
	@find "$(AZURE_TESTS_DIR)" -mindepth 1 -maxdepth 1 -type d | while read dir; do \
		if [ -d "$$dir" ] && [ "$$(find "$$dir" -name "*.tftest.hcl" -type f | wc -l)" -gt 0 ]; then \
			echo "Initializing $$dir..."; \
			(cd "$$dir" && \
			if [ ! -f main.tf ] && [ ! -f terraform.tf ]; then \
				echo '# Empty terraform file to enable initialization' > terraform.tf; \
			fi && \
			terraform init -input=false -upgrade); \
		fi; \
	done
	@echo "All test modules prepared successfully."

.PHONY: test
test: prepare-test-modules ## Run all Terraform tests (auto-discovers test directories)
	@echo "Running all Terraform tests..."
	@ALL_PASSED=true; \
	TEST_DIRS=$$(find "$(AZURE_TESTS_DIR)" -maxdepth 1 -type d | sort); \
	TOTAL_COUNT=0; \
	PASSING_COUNT=0; \
	for dir in $$TEST_DIRS; do \
		if [ "$$dir" != "$(AZURE_TESTS_DIR)" ]; then \
			echo "=== Running tests in $$dir ==="; \
			TOTAL_COUNT=$$((TOTAL_COUNT + 1)); \
			if (cd "$$dir" && terraform test); then \
				PASSING_COUNT=$$((PASSING_COUNT + 1)); \
			else \
				ALL_PASSED=false; \
			fi; \
			echo ""; \
		fi; \
	done; \
	echo "=== Test Results Summary ==="; \
	if [ "$$ALL_PASSED" = true ]; then \
		echo "✅ All $$TOTAL_COUNT modules passed"; \
	else \
		echo "❌ $$PASSING_COUNT out of $$TOTAL_COUNT modules passed"; \
		exit 1; \
	fi

.PHONY: test-module
test-module: prepare-test-modules ## Run tests for a specific module
	@if [ -z "$(MODULE)" ] || [ "$(MODULE)" = "all" ]; then \
		echo "Error: Please specify a module with MODULE=<module-name>"; \
		exit 1; \
	fi
	@TEST_DIR="$(AZURE_TESTS_DIR)/$(MODULE)"; \
	if [ -d "$$TEST_DIR" ]; then \
		echo "=== Running tests in $$TEST_DIR ==="; \
		cd "$$TEST_DIR" && terraform test; \
	else \
		echo "Error: Test directory $$TEST_DIR does not exist"; \
		exit 1; \
	fi

# --- Cloud-specific commands ---

.PHONY: login-azure
login-azure: ## Login to Azure
	@echo "Logging in to Azure..."
	@az login

.PHONY: login-aws
login-aws: ## Login to AWS
	@echo "Configuring AWS credentials..."
	@aws configure

# --- Region Scaffolding ---

.PHONY: scaffold-region
scaffold-region: ## Scaffold a new region (Usage: make scaffold-region CLOUD=azure TARGET_REGION=eastus ENV=dev)
	@if [ -z "$(CLOUD)" ]; then \
		echo "Error: CLOUD parameter is required. Example: make scaffold-region CLOUD=azure TARGET_REGION=eastus ENV=dev"; \
		exit 1; \
	fi
	@if [ -z "$(TARGET_REGION)" ]; then \
		echo "Error: TARGET_REGION parameter is required. Example: make scaffold-region CLOUD=azure TARGET_REGION=eastus ENV=dev"; \
		exit 1; \
	fi
	@if [ -z "$(ENV)" ]; then \
		echo "Error: ENV parameter is required. Example: make scaffold-region CLOUD=azure TARGET_REGION=eastus ENV=dev"; \
		exit 1; \
	fi
	@echo "Scaffolding $(TARGET_REGION) region for $(CLOUD) in environment $(ENV)..."
	@DRY_RUN_FLAG=""; \
	if [ "$(DRY_RUN)" = "true" ]; then \
		DRY_RUN_FLAG="--dry-run"; \
	fi; \
	REGION_ABBV_DEFAULT=$$(echo $(TARGET_REGION) | sed 's/\([a-z]*\).*/\1/'); \
	REGION_ABBV_VALUE=$${REGION_ABBV:-$$REGION_ABBV_DEFAULT}; \
	./scripts/scaffold_region.sh --cloud $(CLOUD) --target-region $(TARGET_REGION) --environment $(ENV) --region-abbv $$REGION_ABBV_VALUE $$DRY_RUN_FLAG
	@echo ""
	@echo "Successfully scaffolded $(TARGET_REGION) region for $(CLOUD)!"
	@echo "Next steps:"
	@echo "1. Initialize the new region: make init ENV=$(ENV) REGION=$(TARGET_REGION) CLOUD=$(CLOUD)"
	@echo "2. Plan the new region: make plan ENV=$(ENV) REGION=$(TARGET_REGION) CLOUD=$(CLOUD)"
	@echo "3. Review the generated files and make any necessary adjustments"
	@echo "4. Apply the infrastructure: make apply ENV=$(ENV) REGION=$(TARGET_REGION) CLOUD=$(CLOUD)" 