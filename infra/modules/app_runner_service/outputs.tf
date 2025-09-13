output "service_url" {
  description = "Public URL of the App Runner service"
  value       = aws_apprunner_service.this.service_url
}

output "ecr_repo_url" {
  description = "ECR repository URL to push the image"
  value       = aws_ecr_repository.this.repository_url
}

output "aws_region" {
  description = "Region in use"
  value       = var.aws_region
}
