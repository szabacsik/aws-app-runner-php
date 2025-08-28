variable "project_name" {
  description = "Project name used for naming AWS resources"
  type        = string
  default     = "php-app-runner-demo"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name)) && length(var.project_name) >= 3
    error_message = "project_name must be lowercase, hyphen-separated, and at least 3 characters."
  }
}

variable "environment" {
  description = "Deployment environment name (allowed: development, staging, production)"
  type        = string
  default     = "development"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment)) && length(var.environment) >= 3
    error_message = "environment must be lowercase, hyphen-separated (^[a-z0-9-]+$) and at least 3 characters."
  }

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "environment must be one of: development, staging, production."
  }
}

variable "owner" {
  description = "Owner tag value for resources"
  type        = string
  default     = "DevOps"
}

variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "eu-central-1"

  validation {
    condition     = length(var.aws_region) > 0
    error_message = "aws_region must be provided."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR notation (e.g., 10.0.0.0/16)."
  }
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks (two AZs)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2 && alltrue([for c in var.private_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "private_subnet_cidrs must contain exactly two valid CIDR blocks."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet hosting the NAT Gateway"
  type        = string
  default     = "10.0.100.0/24"

  validation {
    condition     = can(cidrnetmask(var.public_subnet_cidr))
    error_message = "public_subnet_cidr must be a valid CIDR block."
  }
}

variable "image_tag" {
  description = "Docker image tag to deploy from ECR"
  type        = string
  default     = "latest"

  validation {
    condition     = length(var.image_tag) > 0
    error_message = "image_tag cannot be empty."
  }
}
