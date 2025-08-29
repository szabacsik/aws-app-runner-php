
locals {
  env3          = lower(substr(var.environment, 0, 3))
  // Max length is 32. We build: <project>-<env3>-asc
  // Reserve: 1 dash + env3 (3) + "-asc" (4) = 8 chars. So project part max = 32 - 8 = 24.
  project_max   = 32 - (1 + length(local.env3) + length("-asc"))
  project_trim  = substr(var.project_name, 0, local.project_max)
  asc_name      = "${local.project_trim}-${local.env3}-asc"
}

resource "aws_apprunner_auto_scaling_configuration_version" "this" {
  auto_scaling_configuration_name = local.asc_name
  max_concurrency                 = 100
  max_size                        = 2
  min_size                        = 1
}

resource "aws_apprunner_service" "this" {
  service_name = "${var.project_name}-${var.environment}"

  source_configuration {
    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_ecr_access.arn
    }
    auto_deployments_enabled = true

    image_repository {
      image_identifier      = "${aws_ecr_repository.this.repository_url}:${var.image_tag}"
      image_repository_type = "ECR"
      image_configuration {
        port = "8080"
        runtime_environment_variables = {
          APP_ENV     = var.environment
          APP_NAME    = var.project_name
          APP_VERSION = var.image_tag
        }
      }
    }
  }

  # Pin instance size for consistent performance across environments
  instance_configuration {
    cpu    = "1024"   # 1 vCPU
    memory = "2048"   # 2 GB
  }

  network_configuration {
    egress_configuration {
      egress_type = "DEFAULT"
    }
    ingress_configuration {
      is_publicly_accessible = true
    }
  }

  health_check_configuration {
    protocol            = "HTTP"
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
    timeout             = 2
  }

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.this.arn

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}
