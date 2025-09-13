output "service_url" {
  value       = module.app.service_url
  description = "Public URL of the App Runner service"
}

output "ecr_repo_url" {
  value       = module.app.ecr_repo_url
  description = "ECR repository URL to push images"
}
