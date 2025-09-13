locals {
  env3         = lower(substr(var.app_env, 0, 3))
  project_max  = 32 - (1 + length(local.env3) + length("-asc"))
  project_trim = substr(var.project_name, 0, local.project_max)
  asc_name     = "${local.project_trim}-${local.env3}-asc"
}

# ECR repository for this env
resource "aws_ecr_repository" "this" {
  name                 = "${var.project_name}-${var.app_env}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge({
    Name        = "${var.project_name}-${var.app_env}-ecr"
    Environment = var.app_env
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }, var.tags)
}

# IAM role for App Runner to pull from ECR
data "aws_iam_policy_document" "apprunner_ecr_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["build.apprunner.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "apprunner_ecr_access" {
  name               = "${var.project_name}-${var.app_env}-apprunner-ecr-access"
  assume_role_policy = data.aws_iam_policy_document.apprunner_ecr_assume.json
  tags = merge({
    Name        = "${var.project_name}-${var.app_env}-apprunner-ecr-access"
    Environment = var.app_env
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }, var.tags)
}

resource "aws_iam_role_policy_attachment" "apprunner_ecr_access" {
  role       = aws_iam_role.apprunner_ecr_access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# App Runner autoscaling configuration
resource "aws_apprunner_auto_scaling_configuration_version" "this" {
  auto_scaling_configuration_name = local.asc_name
  max_concurrency                 = var.max_concurrency
  max_size                        = var.max_size
  min_size                        = var.min_size

  lifecycle {
    create_before_destroy = true
  }

  tags = merge({
    Name        = local.asc_name
    Environment = var.app_env
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }, var.tags)
}

# App Runner service
resource "aws_apprunner_service" "this" {
  service_name = "${var.project_name}-${var.app_env}"

  # Image-based source (ECR)
  source_configuration {
    image_repository {
      image_identifier       = "${aws_ecr_repository.this.repository_url}:${var.image_tag}"
      image_repository_type  = "ECR"
      image_configuration {
        port = tostring(var.port)
        # Inject APP_ENV + extra vars at image configuration level (supported by provider)
        runtime_environment_variables = merge(
          var.image_runtime_env,
          var.extra_runtime_env,
          {
            APP_ENV = var.app_env
          }
        )
      }
    }
    auto_deployments_enabled = true

    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_ecr_access.arn
    }
  }

  instance_configuration {
    cpu    = var.cpu
    memory = var.memory
  }

  health_check_configuration {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
    timeout             = 2
    protocol            = "HTTP"
    path                = var.health_path
  }

  # Public ingress, default egress (no VPC connector)
  network_configuration {
    ingress_configuration { is_publicly_accessible = true }
    egress_configuration  { egress_type = "DEFAULT" }
  }

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.this.arn

  tags = merge({
    Name        = "${var.project_name}-${var.app_env}"
    Environment = var.app_env
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }, var.tags)
}
