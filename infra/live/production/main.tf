locals {
  app_env = "production"
  cpu     = "2 vCPU"
  memory  = "4 GB"
}

module "app" {
  source       = "../../modules/app_runner_service"

  project_name = var.project_name
  app_env      = local.app_env
  aws_region   = var.aws_region
  image_tag    = var.image_tag

  port         = 8080
  health_path  = "/health"

  cpu             = local.cpu
  memory          = local.memory
  min_size        = 2
  max_size        = 4
  max_concurrency = 100

  extra_runtime_env = {
    APP_NAME = "php-app-runner-demo"
  }

  tags = {}
}
