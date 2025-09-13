# Run a PHP app on AWS App Runner (Terraform + Docker + Makefile)

This repository is a learning-oriented, production‑inspired scaffold to run a PHP application on AWS App Runner. It reflects a strong belief in PHP as a reliable, scalable, developer‑friendly language. The goal is to help you understand and practice the full lifecycle: build a container, push to ECR, provision infrastructure with Terraform, and have App Runner deploy automatically. Everything is streamlined through a Makefile.

Base image: `szabacsik/php-fpm-phalcon-nginx-bookworm:latest` (Nginx + PHP‑FPM + Phalcon, listens on 8080)

## Why this project exists
- Learn how to run a real PHP app on AWS App Runner, end‑to‑end.
- Keep things clean and reproducible using Terraform and a Makefile.
- Demonstrate good defaults: tagging, least privilege, separation of environments, immutable images, and safe cleanup.
- Provide a minimal PHP example (Phalcon Micro) with health and status endpoints you can extend into an API.

What you get
- Amazon ECR repository for your application image.
- AWS App Runner service pulling from ECR with auto‑deployments on image updates.
- Default egress (no VPC/NAT). Simpler and cheaper: no fixed outbound IP is provided.
- A Makefile that encapsulates common actions (bootstrap, build, push, deploy, inspect, teardown).

Important notes (networking and cost)
- Inbound vs outbound IPs (plain English): Your App Runner service gets a public HTTPS URL (a DNS name). The public IP behind that URL is managed by AWS and may change; App Runner does not offer a single, fixed inbound IP to allow‑list. If you truly need a stable inbound IP for clients to reach you, put a static‑IP capable service in front (e.g., AWS Global Accelerator) or use an ALB/NLB architecture that fits your requirements.
- Egress mode: DEFAULT egress (no VPC, no NAT). Outbound traffic uses AWS-managed IPs that may change; no fixed egress IP is provided. If you require a fixed egress IP, you can re-enable a VPC Connector + NAT/EIP pattern, which is intentionally disabled here to avoid costs.
- Costs: App Runner bills while running. This scaffold does not create a NAT Gateway by default to avoid costs. When you finish experimenting, destroy the stack to stop charges. Use `make down` followed by `make clean`/`make pristine`. In AWS Console, double‑check that the App Runner service and ECR repository are gone if you want zero cost.

## Prerequisites
- Operating systems: Linux and macOS work out of the box. Windows is supported via WSL2 (Ubuntu) or Git Bash because the Makefile requires bash.
- Containers: Docker Desktop on Windows/macOS; on Linux you can use Docker Engine. Podman is not supported by this scaffold.
- Terraform: >= 1.13.0 (provider versions pinned by `.terraform.lock.hcl`).
- Tools: GNU Make and curl; `jq` is optional for pretty JSON.
- AWS: An AWS account and credentials available via environment variables or the shared config/credentials files.

## Architecture overview
- Dockerfile extends a solid PHP base image and copies `app/public` into the container (Nginx serves from `/var/www/html`).
- Terraform provisions:
  - No VPC/NAT by default (uses App Runner DEFAULT egress).
  - ECR repository (scan on push; force delete for easy teardown).
  - IAM role for App Runner to pull from ECR.
  - App Runner service with:
    - ECR image source tracking a tag (default `latest`).
    - Auto deployments enabled.
    - Port 8080 and `/health` HTTP health check.
    - Public ingress enabled, DEFAULT egress (no VPC Connector).
- Terraform outputs expose the service URL, ECR repo URL, and convenience identity info.

## Quick start (development environment)
1. Ensure AWS credentials are available. By default Makefile uses `AWS_PROFILE=private`. Override if needed (see below).
2. Bootstrap, build, push, apply infra, and print URL:
   - `make up`
3. Open the service URL:
   - `make get-url`
4. Smoke test:
   - `make get-curl`
5. Check status:
   - `make get-status`

## Autoscaling & instance size

**What’s configured by default**
- **Instance size**: pinned to **1 vCPU / 2 GB** via Terraform (`instance_configuration { cpu = "1024", memory = "2048" }` in `infra/apprunner.tf`) for consistent behavior across environments.
- **Autoscaling targets** (App Runner):
  - **min_size = 1**, **max_size = 2**
  - **max_concurrency = 100** (target concurrency per instance). When sustained concurrency per instance exceeds ~100, App Runner scales out (up to 2 instances). When load drops, it scales in.

**How to test scaling quickly (ApacheBench)**
1. Ensure the service is up and you have the URL:
   ```bash
   make get-url
   ```

2. Generate sustained load. For example, 10k requests at 200 concurrent connections:

   ```bash
   ab -n 10000 -c 200 "$(make -s get-url)/"
   ```

   > **Note:** `make get-url` already returns a full `https://…` URL. Do **not** prepend `https://` yourself; use "$(make -s get-url)/" as shown.

   > **Tip (ApacheBench):** If your JSON body varies slightly between responses (e.g., dynamic timestamps or per-instance hostnames), `ab` may show `Failed requests: Length`. This is not an HTTP error. Use the `-l` flag to accept variable lengths:
   >
   > ```bash
   > ab -l -n 10000 -c 200 "$(make -s get-url)/"
   > ```

   Or with **hey** (a modern, single-binary alternative to ab):

   ```bash
   # Duration-based test: run for 2 minutes at 200 concurrent requests
   hey -z 2m -c 200 "$(make -s get-url)/"
   ```

   * `-z 2m` runs for a fixed duration (here: 2 minutes).
   * `-c 200` sets concurrency. Increase this to push beyond the per-instance target (`max_concurrency = 100`) and trigger scale-out.

   If you prefer a fixed **request count** instead of a fixed duration:

   ```bash
   # Request-count test: send 10,000 requests with concurrency 200
   hey -n 10000 -c 200 "$(make -s get-url)/"
   ```

   This level of concurrency typically exceeds the per-instance target and should trigger a scale-out (1 → 2 active instances).

 > Different load tools report different numbers (protocol, connection model, and timing windows differ). Focus on **Active instances** and steady-state error-free throughput to validate scaling.

**How to observe it**

* In the app’s root response (`GET /`), the JSON includes `core.hostname`. Under load, responses should show different hostnames as traffic is balanced across instances.
* In AWS Console (App Runner → your service), watch **Active instances** and request/concurrency metrics increase during the test and decrease afterwards.

**Tips for demos**

* To make scaling more obvious in short tests, you can temporarily lower the target and raise the ceiling in `infra/apprunner.tf`:

  ```hcl
  resource "aws_apprunner_auto_scaling_configuration_version" "this" {
    max_concurrency = 20   # lower trigger threshold for demos
    min_size        = 1
    max_size        = 4    # allow more instances for visibility
  }
  ```

  Then:

  ```bash
  make tf-plan
  make tf-apply
  ```

  Revert to the defaults after the demo.

## Environments (per-environment Terraform roots)
We now use one Terraform root per environment, each with its own local state (no remote backend or DynamoDB locks at this stage):

```
infra/modules/app_runner_service
infra/live/development
infra/live/staging
infra/live/qa
infra/live/production
```

Usage examples:
- Default environment is `development` (Makefile: `ENV ?= development`).
- Initialize and format:
  - `make tf-init ENV=development`
- Bring everything up (creates ECR, builds & pushes, applies infra) and print URL:
  - `make up ENV=development AWS_REGION=eu-central-1 IMAGE_TAG=latest`
- Deploy a new tag to staging:
  - `make up ENV=staging IMAGE_TAG=v1.2.3`

Notes:
- State is local per environment folder (e.g., `infra/live/development/terraform.tfstate`).
- Remote state + DynamoDB locks can be introduced later; out of scope here.
- You can also use separate AWS profiles per environment and/or separate AWS accounts.
- Region defaults to `eu-central-1`; override with `AWS_REGION=...`.

## Makefile command reference
Core variables
- `AWS_PROFILE` — Defaults to `private`. Override per command.
- `AWS_REGION` — Defaults to `eu-central-1`.
- `IMAGE_TAG`   — Defaults to `latest`.

Make also exports:
- `TF_VAR_aws_region` from `AWS_REGION`.
- `TF_VAR_image_tag` from `IMAGE_TAG`.

Targets
- `make help` — Show available targets and descriptions.
- `make tf-init` — Initialize Terraform (local state by default).
- `make tf-fmt` — Format Terraform code.
- `make tf-validate` — Validate Terraform configuration.
- `make tf-plan` — Plan infrastructure changes.
- `make tf-apply` — Apply infrastructure changes.
- `make tf-destroy` — Destroy infrastructure.
- `make tf-get-outputs` — Print all Terraform outputs.
- `make bootstrap-ecr` — Create ECR repository only (needed before first push).
- `make ecr-login` — Login Docker to ECR using a Terraform‑retrieved token (no AWS CLI needed).
- `make build` — Build Docker image and tag it for ECR (`<account>.dkr.ecr.<region>.amazonaws.com/repo:IMAGE_TAG`).
- `make push` — Push the image to ECR (depends on `ecr-login`).
- `make deploy` — Build + push to trigger App Runner auto‑deployment (App Runner tracks the configured tag).
- `make up` — Bootstrap from zero: ECR, build + push, apply infra, then print URL.
- `make get-url` — Print the public service URL (auto-adds https:// if missing).
- `make get-curl` — GET the service URL (auto-adds https:// if missing, follows redirects with -L, pretty-prints JSON when possible).
- `make get-status` — Print HTTP status for the service URL (auto-adds https:// if missing, follows redirects with -L).
- `make get-identity` — Print current AWS identity (account, ARN, userId).
- `make docker-clean-local` — Remove the locally built ECR-tagged image and dangling images (destructive, local only).
- `make clean` — Remove Terraform working dirs/state remnants, plans, crash logs, Composer artifacts (vendor/, composer.lock), JS artifacts (node_modules/, lockfiles), PHPUnit cache, and OS cruft. **DESTRUCTIVE**: removes vendor/ and composer.lock.
- `make pristine` — Runs `down` (destroys cloud infra), then `clean`, then removes provider lock files and local Docker images. **HIGHLY DESTRUCTIVE**: nukes generated artifacts and locks; after this you must re-init (terraform init, composer install, etc.).

> ⚠️ DANGER: `clean` and especially `pristine` are destructive. They delete generated artifacts, caches, lock files, and (for `pristine`) also destroy cloud resources and remove local images. Use with care.

Examples
- Use another AWS profile:
  - PowerShell: `$env:AWS_PROFILE='work'; make up`
  - bash: `AWS_PROFILE=work make up`
- Pin a new image tag and roll it out immutably:
  - Build + push tag `v1`: `IMAGE_TAG=v1 make deploy`
  - Update App Runner to track `v1`: `TF_VAR_image_tag=v1 make tf-apply`
- Keep using `latest` and redeploy:
  - `make deploy` (pushes `latest`, App Runner auto‑deploys the new digest)

## End‑to‑end workflows (env‑rooted)
Create a new environment (example: staging)
1. Bring everything up for staging: `make up ENV=staging`.
2. Get URL and test: `make get-url ENV=staging && make get-status ENV=staging && make get-curl ENV=staging`.

Update PHP code only
1. Edit files under `app/public` (e.g., `index.php`).
2. Deploy a new image tag: `make up ENV=<env> IMAGE_TAG=v2` (App Runner auto‑deploys on image push).

Change infrastructure
1. Edit Terraform under the selected env root (e.g., `infra/live/staging/*.tf`) or in the shared module under `infra/modules/app_runner_service`.
2. Plan and apply: `make tf-plan ENV=<env>` then `make tf-apply ENV=<env>`.

Switch environments
- Change the `ENV` value in Make commands, e.g., `ENV=production`.

Full teardown and safe cleanup
1. Destroy cloud resources: `make down` (ECR repo is force‑deleted if non‑empty).
2. Clean local artifacts: `make clean`.
3. Reset repo to a fresh state: `make pristine` (also removes local `infra/backend.hcl` and `infra/backend_s3.tf` if you created them).
4. If you enabled remote state, do NOT delete shared S3 buckets/DynamoDB tables used by your team unless you created them solely for this demo.

## Application endpoints
- `GET /` — JSON status with method, path, query, PHP/Phalcon versions, server time, and application metadata.
  - Response header includes: `X-App-Env: development|staging|production`.
  - JSON includes an `app` block with name, env, and version, for example:

```json
{
  "status": "success",
  "app": {
    "name": "php-app-runner-demo",
    "env": "staging",
    "version": "latest"
  },
  "data": {
    "method": "GET",
    "path": "/",
    "php_version": "8.x",
    "time": "2025-01-01T00:00:00+00:00"
  }
}
```

- `GET /health` — Plain text `OK` (used by App Runner health checks). Also returns the `X-App-Env` header.
- `HEAD /health` — Returns 200 OK without body (also suitable for health checks).
- Any other path — 404 JSON with available endpoints.

Verification examples:
- `curl -i https://<service-url>/`  # check for X-App-Env header
- `curl -s https://<service-url>/ | jq .app`  # inspect app block

## Files and what they do
- `Makefile` — Env‑rooted commands for Terraform and Docker; uses `TF_DIR := infra/live/$(ENV)`.
- `Dockerfile` — Extends the base image; copies `app/public` into `/var/www/html`; exposes port 8080.
- `.dockerignore` — Reduces build context; excludes Git metadata and Terraform state files.
- `app/public/index.php` — Phalcon Micro app with `GET /`, `GET /health`, `HEAD /health`, and a JSON 404 handler.
- `infra/modules/app_runner_service/` — Reusable Terraform module (ECR, IAM for App Runner, autoscaling config, App Runner service, outputs).
- `infra/live/<env>/` — Environment roots: `development`, `staging`, `qa`, `production`. Each has `providers.tf`, `main.tf`, `outputs.tf`. State is local per env folder.
- `README.md` — You are here.

## AWS credentials (cheat‑sheet)
- By default, Makefile uses `AWS_PROFILE=private`. Override with `AWS_PROFILE=...` per command.
- Alternatively, set `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and (optionally) `AWS_SESSION_TOKEN`.
- Region can be overridden with `AWS_REGION` or via Terraform variable `TF_VAR_aws_region`.
- Verify identity any time: `make get-identity`.

## Troubleshooting

### Terraform/AWS — "No valid credential sources found"
- Reason: Using the default AWS profile is not recommended; this project expects a named profile.
- Fix: Configure and use a named profile for every run.

Commands:
```bash
# Select the profile (example: private)
export AWS_PROFILE=private
export AWS_REGION=eu-central-1

# Verify
aws sts get-caller-identity

# Terraform (env-rooted via Makefile)
make tf-plan ENV=development
```

Short note: Do not use the default profile; always set a named profile via the AWS_PROFILE variable.

- “No service URL found”: Apply infra first (`make up` or `make tf-apply`).
- The helper targets now auto-add https:// and follow redirects, so a bare hostname output from Terraform won’t cause 301 anymore.
- ECR login issues: `make ecr-login`; ensure your credentials allow `ecr:GetAuthorizationToken` and `ecr:BatchCheckLayerAvailability` etc.
- App Runner not updating: Confirm the tag you pushed matches `var.image_tag`. Change tag via `TF_VAR_image_tag=... make tf-apply`.
- Port mismatch: The image listens on 8080 and App Runner is configured for 8080.

## Security & cost
- All resources are tagged with Environment/Project/ManagedBy/Owner (see `infra/versions.tf`).
- Do not commit secrets; prefer AWS SSM Parameter Store or Secrets Manager for sensitive values.
- Costs: App Runner incurs charges while running. NAT Gateway is disabled by default in this repo to avoid costs; if you later re-enable a VPC Connector + NAT/EIP for fixed egress IPs, you will incur additional NAT costs.

## Usage and licensing
- You are free to use, copy, modify, and share this project for any purpose — learning, demos, internal tooling, or production experiments.
- No warranty is provided; use at your own risk. Review costs, security, and compliance for your environment.
- If you want a formal license file, you can add an MIT LICENSE to your fork; the intent here is permissive use.

## Next steps
- Evolve `app/public/index.php` into your own API.
- Add variables and outputs for config you care about; wire them to App Runner environment variables if needed.
- Integrate CI/CD: run `terraform fmt/validate`, plan, and apply with approval; push images on release tags.
