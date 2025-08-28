output "service_url" {
  description = "Public URL of the App Runner service"
  value       = aws_apprunner_service.this.service_url
}


output "ecr_repo_url" {
  description = "ECR repository URL to push the image to"
  value       = aws_ecr_repository.this.repository_url
}

output "aws_region" {
  description = "AWS region used by this deployment"
  value       = var.aws_region
}

output "project_name" {
  description = "Project name used for naming resources"
  value       = var.project_name
}

output "service_arn" {
  description = "App Runner service ARN"
  value       = aws_apprunner_service.this.arn
}

output "ecr_token" {
  description = "Base64 authorization token for ECR (format: username:password). Short-lived."
  sensitive   = true
  value       = data.aws_ecr_authorization_token.current.authorization_token
}

output "ecr_proxy_endpoint" {
  description = "ECR proxy endpoint (registry URL with https scheme)"
  value       = data.aws_ecr_authorization_token.current.proxy_endpoint
}


# Current AWS identity (helps verify which credentials Terraform is using)
output "aws_account_id" {
  description = "Current AWS account ID detected by Terraform (from provider credentials)."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_caller_arn" {
  description = "Current AWS caller ARN (useful to verify which role/profile is active)."
  value       = data.aws_caller_identity.current.arn
}

output "aws_caller_user_id" {
  description = "Current AWS caller user ID."
  value       = data.aws_caller_identity.current.user_id
}
