variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "eu-central-1"
}

variable "project_name" {
  type        = string
  description = "Project name"
  default     = "php-app-runner-demo"
}

variable "image_tag" {
  type        = string
  description = "Image tag to deploy"
  default     = "latest"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "staging"
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}
