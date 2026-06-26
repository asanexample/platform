## Platform Infrastructure Makefile
##
## AWS-only OpenTofu + Terragrunt platform. Day-to-day plan/apply/destroy is done
## with `platctl` or `terragrunt` directly (see CLAUDE.md and the apply-and-destroy
## / platctl skills) — NOT via make. This Makefile covers building platctl, running
## the Go/Terratest suites, and regenerating module docs.
##
## Tool versions are pinned canonically in `.tool-versions` (the single source of
## truth read by local dev, CI, and the runner image) — `make version` shows them.

INFRA_DIR   := infra
MODULES_DIR := $(INFRA_DIR)/modules
LIVE_DIR    := $(INFRA_DIR)/live/aws
ENV         ?= platform
MODULE      ?= networking

# Colors for output
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m # No Color

.PHONY: help
help: ## Show help message
	@printf "$(GREEN)Platform Infrastructure$(NC) - Makefile commands:\n\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(YELLOW)%-26s$(NC) %s\n", $$1, $$2}'

.PHONY: version
version: ## Show pinned tool versions (.tool-versions is the source of truth)
	@echo "$(GREEN)Pinned tool versions (.tool-versions):$(NC)"
	@cat .tool-versions
	@echo
	@tofu --version 2>/dev/null | head -1 || true
	@terragrunt --version 2>/dev/null | head -1 || true

#----------------------------------------------
# platctl (platform orchestration CLI)
#----------------------------------------------

.PHONY: build-platctl
build-platctl: ## Build the platctl CLI binary
	@echo "$(GREEN)Building platctl...$(NC)"
	@cd cmd/platctl && go build -o ../../bin/platctl

.PHONY: install-platctl
install-platctl: ## Install platctl globally via go install
	@echo "$(GREEN)Installing platctl...$(NC)"
	@cd cmd/platctl && go install

.PHONY: test-platctl
test-platctl: ## Run platctl unit tests
	@echo "$(GREEN)Running platctl tests...$(NC)"
	@cd cmd/platctl && go test ./... -timeout 30s

#----------------------------------------------
# AWS Testing (Terratest)
#----------------------------------------------

.PHONY: test-aws
test-aws: ## Run all AWS Terratest tests (requires AWS credentials)
	@echo "$(GREEN)Running AWS Terratest suite...$(NC)"
	@cd $(INFRA_DIR)/tests/aws && go test -v -timeout 45m ./...

.PHONY: test-aws-networking
test-aws-networking: ## Run AWS networking Terratest tests
	@echo "$(GREEN)Running AWS networking tests...$(NC)"
	@cd $(INFRA_DIR)/tests/aws && go test -v -timeout 30m ./networking/...

.PHONY: test-aws-eks
test-aws-eks: ## Run AWS EKS Terratest tests
	@echo "$(GREEN)Running AWS EKS tests...$(NC)"
	@cd $(INFRA_DIR)/tests/aws && go test -v -timeout 45m ./eks/...

#----------------------------------------------
# Documentation
#----------------------------------------------

.PHONY: docs
docs: ## Regenerate terraform-docs for all modules
	@echo "$(GREEN)Regenerating module documentation...$(NC)"
	@find $(MODULES_DIR) -name "*.tf" -exec dirname {} \; | sort -u | while read dir; do \
		echo "  $(YELLOW)$$dir$(NC)"; \
		terraform-docs markdown table "$$dir" 2>/dev/null || true; \
	done
	@echo "$(GREEN)Done.$(NC)"

.PHONY: docs-module
docs-module: ## Regenerate terraform-docs for a single module (MODULE=networking or aws/eks)
	@echo "$(GREEN)Regenerating docs for $(MODULE)...$(NC)"
	@terraform-docs markdown table $(MODULES_DIR)/$(MODULE)

.PHONY: docs-check
docs-check: ## Check if terraform-docs are up to date (CI use)
	@echo "$(GREEN)Checking module documentation...$(NC)"
	@find $(MODULES_DIR) -name "*.tf" -exec dirname {} \; | sort -u | while read dir; do \
		terraform-docs markdown table --output-check "$$dir" 2>/dev/null || \
		(echo "$(RED)OUTDATED: $$dir$(NC)" && exit 1); \
	done
	@echo "$(GREEN)All module docs are up to date.$(NC)"

#----------------------------------------------
# Utility operations
#----------------------------------------------

.PHONY: clean
clean: ## Clean temporary OpenTofu/Terragrunt files
	@echo "$(GREEN)Cleaning temporary files...$(NC)"
	@find $(INFRA_DIR) -name ".terraform" -type d -prune -exec rm -rf {} \; -print
	@find $(INFRA_DIR) -name ".terragrunt-cache" -type d -prune -exec rm -rf {} \; -print
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
list-regions: ## List available regions for an environment (ENV=platform)
	@echo "$(GREEN)Available regions for $(ENV):$(NC)"
	@find $(LIVE_DIR)/$(ENV) -maxdepth 1 -mindepth 1 -type d | sort | xargs -n1 basename | sed 's/^/* /'
