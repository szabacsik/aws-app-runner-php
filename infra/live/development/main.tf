locals {
  app_env = "development"
  cpu     = "1 vCPU"
  memory  = "2 GB"
}

module "app" {
  source = "../../modules/app_runner_service"

  project_name = var.project_name
  app_env      = local.app_env
  aws_region   = var.aws_region
  image_tag    = var.image_tag

  port        = 8080
  health_path = "/health"

  cpu             = local.cpu
  memory          = local.memory
  min_size        = 1
  max_size        = 1
  max_concurrency = 50

  extra_runtime_env = {
    APP_NAME = "php-app-runner-demo"
  }

  tags = {}
}
