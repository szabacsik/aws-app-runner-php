SHELL := /bin/bash

# Default variables (can be overridden: make up AWS_REGION=eu-west-1 IMAGE_TAG=v1)
# Avoid calling terraform during Makefile parsing; default to eu-central-1 and allow override via make/env
AWS_REGION ?= eu-central-1
IMAGE_TAG ?= latest

# Container CLI: Docker only (Podman not supported)
DOCKER := docker

# AWS profile: default to 'private' unless overridden
AWS_PROFILE ?= private
export AWS_PROFILE

# Centralized Terraform variable export (keeps behavior without inline TF_VAR noise)
export TF_VAR_aws_region := $(AWS_REGION)
export TF_VAR_image_tag := $(IMAGE_TAG)

.PHONY: help tf-init tf-fmt tf-validate tf-plan tf-apply tf-destroy tf-get-outputs down bootstrap-ecr ecr-login build tag push deploy up get-url get-curl get-status get-identity clean pristine docker-clean-local

## Show this help and available targets
help:
	@echo "Available targets:"
	@echo "  tf-init          - Initialize Terraform (local state only)"
	@echo "  tf-fmt           - Format Terraform code"
	@echo "  tf-validate      - Validate Terraform configuration"
	@echo "  tf-plan          - Plan infrastructure changes"
	@echo "  tf-apply         - Apply infrastructure changes"
	@echo "  tf-destroy       - Destroy infrastructure"
	@echo "  tf-get-outputs   - Print Terraform outputs"
	@echo "  down             - Destroy everything (calls tf-destroy)"
	@echo "  bootstrap-ecr    - Create ECR repo only (required before first push)"
	@echo "  ecr-login        - Authenticate Docker to ECR (no AWS CLI needed)"
	@echo "  build            - Build Docker image and tag for ECR"
	@echo "  tag              - Tag local image for ECR (no-op alias to clarify flow)"
	@echo "  push             - Push image to ECR"
	@echo "  deploy           - Build+push to trigger App Runner deployment"
	@echo "  up               - Bootstrap: ECR, build+push, infra, print URL"
	@echo "  get-url          - Print service URL (auto-https if missing)"
	@echo "  get-curl         - GET the service URL (auto-https, follows redirects, pretty-prints JSON when possible)"
	@echo "  get-status       - HTTP status for the service URL (auto-https, follows redirects)"
	@echo "  get-identity     - Print current AWS identity (account, ARN, userId)"
	@echo "  docker-clean-local - Remove the locally built ECR-tagged image and dangling images (destructive, local only)"
	@echo "  clean            - Remove Terraform/Composer/JS artifacts and caches (DESTRUCTIVE: removes vendor/ and composer.lock)"
	@echo "  pristine         - Destroy infra, then deep-clean everything incl. lock files and local images (HIGHLY DESTRUCTIVE)"

# Terraform lifecycle
## Initialize Terraform (local state only)
tf-init:
	terraform -chdir=infra init

## Format Terraform code
tf-fmt:
	terraform -chdir=infra fmt -recursive

## Validate Terraform configuration
tf-validate: tf-init
	terraform -chdir=infra validate

## Plan Terraform changes
tf-plan:
	terraform -chdir=infra plan

## Apply Terraform changes
tf-apply:
	terraform -chdir=infra apply -auto-approve

## Destroy Terraform-managed infrastructure
tf-destroy:
	terraform -chdir=infra destroy -auto-approve

## Print all Terraform outputs (read-only)
tf-get-outputs:
	terraform -chdir=infra output

## Convenience: destroy everything (calls tf-destroy)
down: tf-init tf-destroy
	@echo "Infrastructure destroyed. ECR repository force-deleted if non-empty."

# Create just the ECR repository first so we can push the initial image before creating the App Runner service
## Bootstrap ECR repository only (needed before first image push)
bootstrap-ecr: tf-init
	terraform -chdir=infra apply -target=aws_ecr_repository.this -auto-approve

# Login to ECR registry without AWS CLI (uses Terraform ECR auth token)
## Login to ECR Docker registry (no AWS CLI required)
ecr-login:
	@set -euo pipefail; \
	terraform -chdir=infra apply -refresh-only -target=data.aws_ecr_authorization_token.current -auto-approve >/dev/null; \
	REG=$$(terraform -chdir=infra output -raw ecr_proxy_endpoint | sed -e 's#^https://##'); \
	TOK=$$(terraform -chdir=infra output -raw ecr_token); \
	USER=$$(printf %s "$$TOK" | base64 -d | cut -d: -f1); \
	PASS=$$(printf %s "$$TOK" | base64 -d | cut -d: -f2-); \
	echo "Logging in to $$REG as $$USER"; \
	echo "$$PASS" | $(DOCKER) login --username "$$USER" --password-stdin "$$REG"

# Build image (based on provided base image) and tag with ECR repo URI and IMAGE_TAG
## Build Docker image tagged for ECR
build:
	@set -euo pipefail; \
	ECR_REPO_URI=$$(terraform -chdir=infra output -raw ecr_repo_url); \
	echo "Building image $$ECR_REPO_URI:$(IMAGE_TAG)"; \
	$(DOCKER) build -t $$ECR_REPO_URI:$(IMAGE_TAG) .

## (No-op) tag alias to keep flow explicit
tag:
	@set -euo pipefail; \
	ECR_REPO_URI=$$(terraform -chdir=infra output -raw ecr_repo_url); \
	echo "Tagging local image as $$ECR_REPO_URI:$(IMAGE_TAG)"; \
	$(DOCKER) tag $$ECR_REPO_URI:$(IMAGE_TAG) $$ECR_REPO_URI:$(IMAGE_TAG)

## Push Docker image to ECR
push: ecr-login
	@set -euo pipefail; \
	ECR_REPO_URI=$$(terraform -chdir=infra output -raw ecr_repo_url); \
	echo "Pushing $$ECR_REPO_URI:$(IMAGE_TAG)"; \
	$(DOCKER) push $$ECR_REPO_URI:$(IMAGE_TAG)

# Deploy new image (push to ECR). App Runner is configured with auto_deployments_enabled, so this triggers a new deployment.
## Build+push to trigger App Runner deployment
deploy: build push
	@echo "Deployment triggered by ECR image push. App Runner will roll out automatically."

# Full bootstrap from zero: create ECR, build+push initial image, then create the rest of the infra and service
## Create ECR, build+push, then apply infra and print URL
up: bootstrap-ecr build push tf-apply get-url
	@echo "Up completed. Service URL printed above."

# Read-only helpers (get-*)
## Print service URL (read-only)
get-url:
	@URL=$$(terraform -chdir=infra output -raw service_url 2>/dev/null || true); \
	if [ -z "$$URL" ]; then echo "No service URL found. Did you run 'make up' or 'make tf-apply'?"; exit 1; fi; \
	case "$$URL" in http://*|https://*) : ;; *) URL="https://$$URL";; esac; \
	echo "$$URL"


## Simple smoke test: curl the service URL (read-only)
get-curl:
	@URL=$$(terraform -chdir=infra output -raw service_url 2>/dev/null || true); \
	if [ -z "$$URL" ]; then echo "No service URL found. Did you run 'make up' or 'make tf-apply'?"; exit 1; fi; \
	case "$$URL" in http://*|https://*) : ;; *) URL="https://$$URL";; esac; \
	echo "GET $$URL"; \
	curl -sS -L "$$URL" | jq . || curl -sS -L "$$URL"

## Basic HTTP status check against the service URL (read-only)
get-status:
	@URL=$$(terraform -chdir=infra output -raw service_url 2>/dev/null || true); \
	if [ -z "$$URL" ]; then echo "No service URL found. Did you run 'make up' or 'make tf-apply'?"; exit 1; fi; \
	case "$$URL" in http://*|https://*) : ;; *) URL="https://$$URL";; esac; \
	CODE=$$(curl -s -o /dev/null -w "%{http_code}" -L "$$URL"); \
	echo "Status: $$CODE | URL: $$URL"

## Print current AWS identity (read-only)
get-identity:
	@set -euo pipefail; \
	terraform -chdir=infra apply -refresh-only -target=data.aws_caller_identity.current -auto-approve >/dev/null; \
	echo "AWS account: $$(terraform -chdir=infra output -raw aws_account_id)"; \
	echo "Caller ARN : $$(terraform -chdir=infra output -raw aws_caller_arn)"; \
	echo "User ID    : $$(terraform -chdir=infra output -raw aws_caller_user_id)"


# Clean temporary and reproducible artifacts to restore a fresh checkout state
## Remove local Terraform state/cache and typical build artifacts
clean:
	@set -euo pipefail; \
	echo "Cleaning reproducible and temporary files..."; \
	# Terraform working dirs (root + infra)
	find . -type d -name ".terraform" -prune -exec rm -rf {} + 2>/dev/null || true; \
	# Terraform state, backups, locks (root + infra)
	rm -f terraform.tfstate terraform.tfstate.backup .terraform.tfstate.lock.info 2>/dev/null || true; \
	rm -f infra/terraform.tfstate infra/terraform.tfstate.backup infra/.terraform.tfstate.lock.info 2>/dev/null || true; \
	# Terraform workspace-local state dirs (root + infra)
	rm -rf terraform.tfstate.d infra/terraform.tfstate.d 2>/dev/null || true; \
	# Terraform plans (root + infra)
	rm -f *.tfplan plan.out infra/*.tfplan infra/plan.out 2>/dev/null || true; \
	# Terraform crash logs (root + infra)
	rm -f crash.log crash.*.log infra/crash.log infra/crash.*.log 2>/dev/null || true; \
	# Composer artifacts
	rm -rf vendor 2>/dev/null || true; \
	rm -f composer.lock composer.phar 2>/dev/null || true; \
	# JS artifacts (if any)
	rm -rf node_modules 2>/dev/null || true; \
	rm -f package-lock.json yarn.lock pnpm-lock.yaml 2>/dev/null || true; \
	# PHPUnit cache
	rm -f .phpunit.result.cache 2>/dev/null || true; \
	# OS cruft
	find . -name ".DS_Store" -delete 2>/dev/null || true; \
	find . -name "Thumbs.db" -delete 2>/dev/null || true; \
	echo "Clean complete."

## Remove local ECR-tagged image and dangling images (best-effort)
docker-clean-local:
	@set -euo pipefail; \
	if command -v $(DOCKER) >/dev/null 2>&1; then \
		ECR_REPO_URI=$$(terraform -chdir=infra output -raw ecr_repo_url 2>/dev/null || true); \
		if [ -n "$$ECR_REPO_URI" ]; then \
			echo "Removing local image $$ECR_REPO_URI:$(IMAGE_TAG) (if present)"; \
			$(DOCKER) image rm -f "$$ECR_REPO_URI:$(IMAGE_TAG)" 2>/dev/null || true; \
		fi; \
		echo "Removing dangling images"; \
		$(DOCKER) image prune -f >/dev/null 2>&1 || true; \
	fi

## Run 'down' then 'clean' and also drop lock files & local-only infra configs + local image
pristine: down clean docker-clean-local
	@set -euo pipefail; \
	# Remove local variable files and non-versioned backend configs inside infra
	rm -f infra/*.tfvars infra/*.auto.tfvars infra/backend.hcl infra/backend_s3.tf 2>/dev/null || true; \
	# Remove provider lock files (root + infra)
	rm -f .terraform.lock.hcl infra/.terraform.lock.hcl 2>/dev/null || true; \
	echo "Repository workspace is now pristine (nuked generated artifacts and locks)."
