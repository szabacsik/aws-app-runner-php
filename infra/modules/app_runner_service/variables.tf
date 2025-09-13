variable "project_name" {
  description = "Project name used for naming AWS resources"
  type        = string
}

variable "app_env" {
  description = "Environment label injected into tags and APP_ENV (e.g., development, staging, qa, production)"
  type        = string
}

variable "aws_region" {
  description = "AWS region (duplicated here for outputs/consistency)"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy from ECR (e.g., latest, v1.0.0)"
  type        = string
  default     = "latest"
}

variable "port" {
  description = "Container port"
  type        = number
  default     = 8080
}

variable "health_path" {
  description = "HTTP path for health checks"
  type        = string
  default     = "/health"
}

variable "cpu" {
  description = "App Runner CPU setting (string per AWS spec, e.g., \"1 vCPU\", \"2 vCPU\")"
  type        = string
  default     = "1 vCPU"
}

variable "memory" {
  description = "App Runner memory setting (string per AWS spec, e.g., \"2 GB\", \"4 GB\")"
  type        = string
  default     = "2 GB"
}

variable "min_size" {
  description = "Min instances for autoscaling configuration"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Max instances for autoscaling configuration"
  type        = number
  default     = 2
}

variable "max_concurrency" {
  description = "Max concurrent requests per instance"
  type        = number
  default     = 100
}

variable "extra_runtime_env" {
  description = "Additional runtime environment variables for the instance"
  type        = map(string)
  default     = {}
}

variable "image_runtime_env" {
  description = "Environment variables in image configuration (less commonly needed)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Extra tags merged into resources"
  type        = map(string)
  default     = {}
}
