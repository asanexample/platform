## Multi-Cloud Platform Infrastructure Makefile
##
## This Makefile automates common operations for the multi-cloud platform.
## It provides commands for Terragrunt operations, testing, and environment management.

# Default values
ENV ?= dev
REGION ?= eastus
WORKLOAD ?= platform
MODULE ?= all
CLOUD ?= azure
COMMAND ?= plan
TERRAFORM_VERSION ?= 1.6.0
TERRAGRUNT_VERSION ?= 0.53.0

# Convenience variables
INFRA_DIR := infra
LIVE_DIR := $(INFRA_DIR)/live/$(CLOUD)
ENV_DIR := $(LIVE_DIR)/$(ENV)
REGION_DIR := $(ENV_DIR)/$(REGION)
WORKLOAD_DIR := $(REGION_DIR)/$(WORKLOAD)
MODULES_DIR := $(INFRA_DIR)/modules/$(CLOUD)
TESTS_DIR := $(INFRA_DIR)/tests/modules/$(CLOUD)

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

.PHONY: help
help: ## Show help message
	@printf "$(GREEN)Multi-Cloud Infrastructure$(NC) - Makefile commands:\n\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(YELLOW)%-30s$(NC) %s\n", $$1, $$2}'

.PHONY: version
version: ## Show tool versions
	@echo "$(GREEN)Required tool versions:$(NC)"
	@echo "- Terraform: $(TERRAFORM_VERSION)"
	@echo "- Terragrunt: $(TERRAGRUNT_VERSION)"
	terraform --version
	terragrunt --version

.PHONY: validate
validate: ## Validate terraform code
	@echo "$(GREEN)Validating Terraform code...$(NC)"
	@find $(MODULES_DIR) -type f -name "*.tf" -exec sh -c 'echo "Validating {}..." && terraform fmt -check {} && terraform validate $(dirname {})' \;

.PHONY: check-azure-auth
check-azure-auth: ## Check Azure authentication status
	@echo "$(GREEN)Checking Azure authentication status...$(NC)"
	@if ! az account show &>/dev/null; then \
		echo "$(RED)Not logged in to Azure. Running az login...$(NC)"; \
		az login; \
	else \
		echo "$(GREEN)Already logged in to Azure$(NC)"; \
	fi
	@SUBSCRIPTION_NAME=$$(grep -o 'subscription_name[[:space:]]*=[[:space:]]*"[^"]*"' "$(ENV_DIR)/env.hcl" | sed 's/subscription_name[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/'); \
	SUBSCRIPTION_ID=$$(grep -o 'subscription_id[[:space:]]*=[[:space:]]*"[^"]*"' "$(ENV_DIR)/env.hcl" | sed 's/subscription_id[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/'); \
	TENANT_ID=$$(grep -o 'tenant_id[[:space:]]*=[[:space:]]*"[^"]*"' "$(ENV_DIR)/env.hcl" | sed 's/tenant_id[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/'); \
	echo "$(YELLOW)Using subscription: $$SUBSCRIPTION_NAME ($$SUBSCRIPTION_ID)$(NC)"; \
	echo "$(YELLOW)Using tenant: $$TENANT_ID$(NC)"; \
	echo "$(YELLOW)Defined in: $(ENV)/env.hcl$(NC)"

#----------------------------------------------
# Terragrunt operations
#----------------------------------------------

.PHONY: init
init: check-azure-auth ## Initialize all modules in the specified environment/region/workload
	@echo "$(GREEN)Initializing all modules in $(ENV)/$(REGION)/$(WORKLOAD)...$(NC)"
	@cd $(WORKLOAD_DIR) && terragrunt run-all init --terragrunt-non-interactive

.PHONY: plan
plan: check-azure-auth ## Plan all modules in the specified environment/region/workload
	@echo "$(GREEN)Planning all modules in $(ENV)/$(REGION)/$(WORKLOAD)...$(NC)"
	@cd $(WORKLOAD_DIR) && terragrunt run-all plan --terragrunt-non-interactive

.PHONY: apply
apply: check-azure-auth ## Apply all modules in the specified environment/region/workload
	@echo "$(GREEN)Applying all modules in $(ENV)/$(REGION)/$(WORKLOAD)...$(NC)"
	@cd $(WORKLOAD_DIR) && terragrunt run-all apply --terragrunt-non-interactive --terragrunt-log-level info

.PHONY: destroy
destroy: check-azure-auth ## Destroy all modules in the specified environment/region/workload (USE WITH CAUTION)
	@echo "$(RED)WARNING: This will destroy all infrastructure in $(ENV)/$(REGION)/$(WORKLOAD)$(NC)"
	@echo "Are you sure? [y/N]" && read ans && [ $${ans:-N} = y ]
	@echo "$(RED)Destroying all modules in $(ENV)/$(REGION)/$(WORKLOAD)...$(NC)"
	@cd $(WORKLOAD_DIR) && terragrunt run-all destroy --terragrunt-non-interactive

.PHONY: output
output: check-azure-auth ## Show outputs for all modules in the specified environment/region/workload
	@echo "$(GREEN)Showing outputs for modules in $(ENV)/$(REGION)/$(WORKLOAD)...$(NC)"
	@cd $(WORKLOAD_DIR) && terragrunt run-all output --terragrunt-non-interactive

#----------------------------------------------
# Module specific operations
#----------------------------------------------

.PHONY: init-module
init-module: check-azure-auth ## Initialize a specific module
	@echo "$(GREEN)Initializing module $(MODULE) in $(ENV)/$(REGION)/$(WORKLOAD)...$(NC)"
	@cd $(WORKLOAD_DIR)/$(MODULE) && terragrunt init --terragrunt-non-interactive

.PHONY: plan-module
plan-module: check-azure-auth ## Plan a specific module
	@echo "$(GREEN)Planning module $(MODULE) in $(ENV)/$(REGION)/$(WORKLOAD)...$(NC)"
	@cd $(WORKLOAD_DIR)/$(MODULE) && terragrunt plan --terragrunt-non-interactive

.PHONY: apply-module
apply-module: check-azure-auth ## Apply a specific module
	@echo "$(GREEN)Applying module $(MODULE) in $(ENV)/$(REGION)/$(WORKLOAD)...$(NC)"
	@cd $(WORKLOAD_DIR)/$(MODULE) && terragrunt apply --terragrunt-non-interactive

.PHONY: destroy-module
destroy-module: check-azure-auth ## Destroy a specific module (USE WITH CAUTION)
	@echo "$(RED)WARNING: This will destroy module $(MODULE) in $(ENV)/$(REGION)/$(WORKLOAD)$(NC)"
	@echo "Are you sure? [y/N]" && read ans && [ $${ans:-N} = y ]
	@echo "$(RED)Destroying module $(MODULE) in $(ENV)/$(REGION)/$(WORKLOAD)...$(NC)"
	@cd $(WORKLOAD_DIR)/$(MODULE) && terragrunt destroy --terragrunt-non-interactive

.PHONY: output-module
output-module: check-azure-auth ## Show outputs for a specific module
	@echo "$(GREEN)Showing outputs for module $(MODULE) in $(ENV)/$(REGION)/$(WORKLOAD)...$(NC)"
	@cd $(WORKLOAD_DIR)/$(MODULE) && terragrunt output --terragrunt-non-interactive

#----------------------------------------------
# Testing
#----------------------------------------------

.PHONY: test
test: check-azure-auth ## Run all tests
	@echo "$(GREEN)Running all module tests...$(NC)"
	@find $(TESTS_DIR) -name "*.tftest.hcl" -print0 | xargs -0 -n1 dirname | sort -u | xargs -I{} sh -c 'echo "$(YELLOW)Testing {}...$(NC)" && cd {} && terraform init && terraform test'

.PHONY: test-module
test-module: check-azure-auth ## Run tests for a specific module
	@echo "$(GREEN)Running tests for module $(MODULE)...$(NC)"
	@cd $(TESTS_DIR)/$(MODULE) && terraform init && terraform test

.PHONY: test-category
test-category: check-azure-auth ## Run tests for a category of modules (e.g., storage, networking)
	@echo "$(GREEN)Running tests for category $(CATEGORY)...$(NC)"
	@find $(TESTS_DIR) -path "*/$(CATEGORY)*" -name "*.tftest.hcl" -print0 | xargs -0 -n1 dirname | sort -u | xargs -I{} sh -c 'echo "$(YELLOW)Testing {}...$(NC)" && cd {} && terraform init && terraform test'

#----------------------------------------------
# Azure specific operations
#----------------------------------------------

.PHONY: az-login
az-login: ## Login to Azure CLI
	@echo "$(GREEN)Logging in to Azure...$(NC)"
	az login

.PHONY: az-show-subscription
az-show-subscription: ## Show current Azure subscription
	@echo "$(GREEN)Current Azure subscription:$(NC)"
	@az account show

.PHONY: az-list-subscriptions
az-list-subscriptions: ## List available Azure subscriptions
	@echo "$(GREEN)Available Azure subscriptions:$(NC)"
	@az account list --output table

.PHONY: az-create-state-resources
az-create-state-resources: check-azure-auth ## Create Azure resources for Terraform state
	@echo "$(GREEN)Creating Azure resources for Terraform state...$(NC)"
	az group create --name terraform-state-rg --location eastus
	az storage account create --resource-group terraform-state-rg --name tfstatemulticloud --sku Standard_LRS --encryption-services blob
	az storage container create --name terraformstate --account-name tfstatemulticloud

#----------------------------------------------
# AWS Testing (Terratest)
#----------------------------------------------

.PHONY: test-aws
test-aws: ## Run all AWS Terratest tests (requires AWS credentials)
	@echo "$(GREEN)Running AWS Terratest suite...$(NC)"
	@cd $(INFRA_DIR)/tests/aws && go test -v -timeout 30m ./...

.PHONY: test-aws-networking
test-aws-networking: ## Run AWS networking Terratest tests
	@echo "$(GREEN)Running AWS networking tests...$(NC)"
	@cd $(INFRA_DIR)/tests/aws && go test -v -timeout 30m ./networking/...

#----------------------------------------------
# Kubernetes operations
#----------------------------------------------

.PHONY: k8s-credentials
k8s-credentials: check-azure-auth ## Get credentials for AKS cluster
	@echo "$(GREEN)Getting credentials for AKS cluster...$(NC)"
	az aks get-credentials --resource-group $(ENV)-$(REGION)-rg --name $(ENV)-$(REGION)-aks

.PHONY: k8s-deploy-charts
k8s-deploy-charts: ## Deploy Helm charts to Kubernetes cluster
	@echo "$(GREEN)Deploying Helm charts to Kubernetes cluster...$(NC)"
	@find charts -name "Chart.yaml" -print0 | xargs -0 -n1 dirname | sort | xargs -I{} sh -c 'echo "Installing {}..." && helm upgrade --install $$(basename {}) {} --create-namespace --namespace $$(basename {})-system'

#----------------------------------------------
# Documentation
#----------------------------------------------

.PHONY: docs
docs: ## Regenerate terraform-docs for all modules
	@echo "$(GREEN)Regenerating module documentation...$(NC)"
	@find infra/modules -name "*.tf" -exec dirname {} \; | sort -u | while read dir; do \
		echo "  $(YELLOW)$$dir$(NC)"; \
		terraform-docs markdown table "$$dir" 2>/dev/null || true; \
	done
	@echo "$(GREEN)Done.$(NC)"

.PHONY: docs-module
docs-module: ## Regenerate terraform-docs for a single module (MODULE=networking)
	@echo "$(GREEN)Regenerating docs for $(MODULE)...$(NC)"
	@terraform-docs markdown table infra/modules/$(CLOUD)/$(MODULE)

.PHONY: docs-check
docs-check: ## Check if terraform-docs are up to date (CI use)
	@echo "$(GREEN)Checking module documentation...$(NC)"
	@find infra/modules -name "*.tf" -exec dirname {} \; | sort -u | while read dir; do \
		terraform-docs markdown table --output-check "$$dir" 2>/dev/null || \
		(echo "$(RED)OUTDATED: $$dir$(NC)" && exit 1); \
	done
	@echo "$(GREEN)All module docs are up to date.$(NC)"

#----------------------------------------------
# Utility operations
#----------------------------------------------

.PHONY: clean
clean: ## Clean temporary files
	@echo "$(GREEN)Cleaning temporary files...$(NC)"
	@find $(INFRA_DIR) -name ".terraform" -type d -prune -exec rm -rf {} \; -print
	@find $(INFRA_DIR) -name ".terraform.lock.hcl" -type f -delete
	@find $(INFRA_DIR) -name "terraform.tfstate*" -type f -delete
	@find $(INFRA_DIR) -name "*.tfplan" -type f -delete

.PHONY: list-modules
list-modules: ## List available modules
	@echo "$(GREEN)Available modules:$(NC)"
	@find $(MODULES_DIR) -maxdepth 1 -mindepth 1 -type d | sort | xargs -n1 basename | sed 's/^/* /'

.PHONY: list-environments
list-environments: ## List available environments
	@echo "$(GREEN)Available environments:$(NC)"
	@find $(LIVE_DIR) -maxdepth 1 -mindepth 1 -type d -not -path "*/\.*" -not -path "*/_*" | sort | xargs -n1 basename | sed 's/^/* /'

.PHONY: list-regions
list-regions: ## List available regions for an environment
	@echo "$(GREEN)Available regions for $(ENV):$(NC)"
	@find $(ENV_DIR) -maxdepth 1 -mindepth 1 -type d | sort | xargs -n1 basename | sed 's/^/* /' 