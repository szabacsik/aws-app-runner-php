SHELL := /bin/bash

# Default variables (can be overridden: make up AWS_REGION=eu-west-1 IMAGE_TAG=v1)
# Avoid calling terraform during Makefile parsing; default to eu-central-1 and allow override via make/env
AWS_REGION ?= eu-central-1
IMAGE_TAG ?= latest
ENV ?= development
TF_DIR := infra/live/$(ENV)

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
	terraform -chdir=$(TF_DIR) init -upgrade
	terraform -chdir=$(TF_DIR) fmt -recursive

## Format Terraform code
tf-fmt:
	terraform -chdir=$(TF_DIR) fmt -recursive

## Validate Terraform configuration
tf-validate: tf-init
	terraform -chdir=$(TF_DIR) validate

## Plan Terraform changes
tf-plan: tf-init
	terraform -chdir=$(TF_DIR) plan

## Apply Terraform changes
tf-apply: tf-init
	terraform -chdir=$(TF_DIR) apply -auto-approve

## Destroy Terraform-managed infrastructure
tf-destroy: tf-init
	terraform -chdir=$(TF_DIR) destroy -auto-approve

## Print all Terraform outputs (read-only)
tf-get-outputs:
	terraform -chdir=$(TF_DIR) output

## Convenience: destroy everything (calls tf-destroy)
down: tf-destroy
	@echo "Infrastructure destroyed. ECR repository force-deleted if non-empty."

## Ensure ECR exists in selected environment before first push
tf-ensure-ecr: tf-init
	terraform -chdir=$(TF_DIR) apply -auto-approve -target=module.app.aws_ecr_repository.this

# Docker login/build/push using AWS CLI
ecr-login:
	@REG=$$(terraform -chdir=$(TF_DIR) output -raw ecr_repo_url | sed 's@/.*@@'); \
	aws ecr get-login-password --region $(AWS_REGION) | $(DOCKER) login --username AWS --password-stdin $$REG

# Build image (based on provided base image) and tag with ECR repo URI and IMAGE_TAG
## Build Docker image tagged for ECR
build:
	@set -euo pipefail; \
	ECR_REPO_URI=$$(terraform -chdir=$(TF_DIR) output -raw ecr_repo_url); \
	echo "Building image $$ECR_REPO_URI:$(IMAGE_TAG)"; \
	$(DOCKER) build -t $$ECR_REPO_URI:$(IMAGE_TAG) .

## (No-op) tag alias to keep flow explicit
tag:
	@set -euo pipefail; \
	ECR_REPO_URI=$$(terraform -chdir=$(TF_DIR) output -raw ecr_repo_url); \
	echo "Tagging local image as $$ECR_REPO_URI:$(IMAGE_TAG)"; \
	$(DOCKER) tag $$ECR_REPO_URI:$(IMAGE_TAG) $$ECR_REPO_URI:$(IMAGE_TAG)

## Push Docker image to ECR
push: ecr-login
	@set -euo pipefail; \
	ECR_REPO_URI=$$(terraform -chdir=$(TF_DIR) output -raw ecr_repo_url); \
	echo "Pushing $$ECR_REPO_URI:$(IMAGE_TAG)"; \
	$(DOCKER) push $$ECR_REPO_URI:$(IMAGE_TAG)

# New docker-build/docker-push targets per env
## Build (env-aware)
docker-build:
	@ECR=$$(terraform -chdir=$(TF_DIR) output -raw ecr_repo_url); \
	$(DOCKER) build -t $$ECR:$(IMAGE_TAG) .

## Push (env-aware)
docker-push: ecr-login
	@ECR=$$(terraform -chdir=$(TF_DIR) output -raw ecr_repo_url); \
	$(DOCKER) push $$ECR:$(IMAGE_TAG)

# Deploy new image (push to ECR). App Runner is configured with auto_deployments_enabled, so this triggers a new deployment.
## Build+push to trigger App Runner deployment
deploy: build push
	@echo "Deployment triggered by ECR image push. App Runner will roll out automatically."

# Full bootstrap from zero: create ECR, build+push initial image, then create the rest of the infra and service
## Deploy flow: ensure ECR, build & push image, then apply infra
up: tf-ensure-ecr docker-build docker-push tf-apply

# Read-only helpers (get-*)
## Print service URL (read-only)
get-url:
	@terraform -chdir=$(TF_DIR) output -raw service_url


## Simple smoke test: curl the service URL (read-only)
get-curl:
	@URL=$$(terraform -chdir=$(TF_DIR) output -raw service_url 2>/dev/null || true); \
	test -n "$$URL" || (echo "Service URL not found. Did you run 'make up ENV=$(ENV)'?"; exit 1); \
	echo "GET $$URL"; \
	curl -sS -L "$$URL" | jq . || curl -sS -L "$$URL"

## Basic HTTP status check against the service URL (read-only)
get-status:
	@URL=$$(terraform -chdir=$(TF_DIR) output -raw service_url); \
	test -n "$$URL" || (echo "Service URL not found. Did you run 'make up ENV=$(ENV)'?"; exit 1); \
	CODE=$$(curl -s -o /dev/null -w "%{http_code}" -L "$$URL"); \
	echo "Status: $$CODE | URL: $$URL"

## Print current AWS identity (read-only)
get-identity:
	@aws sts get-caller-identity --output table


# Clean Terraform env roots only (local state)
clean:
	@find infra/live -type d -name ".terraform" -prune -exec rm -rf {} +; \
	find infra/live -type f -name ".terraform.lock.hcl" -delete; \
	find infra/live -type f -name "terraform.tfstate*" -delete

## Remove local ECR-tagged image and dangling images (best-effort)
docker-clean-local:
	@set -euo pipefail; \
	if command -v $(DOCKER) >/dev/null 2>&1; then \
		ECR_REPO_URI=$$(terraform -chdir=$(TF_DIR) output -raw ecr_repo_url 2>/dev/null || true); \
		if [ -n "$$ECR_REPO_URI" ]; then \
			echo "Removing local image $$ECR_REPO_URI:$(IMAGE_TAG) (if present)"; \
			$(DOCKER) image rm -f "$$ECR_REPO_URI:$(IMAGE_TAG)" 2>/dev/null || true; \
		fi; \
		echo "Removing dangling images"; \
		$(DOCKER) image prune -f >/dev/null 2>&1 || true; \
	fi

# Pristine cleanup
pristine: down clean


