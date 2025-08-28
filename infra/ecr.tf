resource "aws_ecr_repository" "this" {
  name                 = "${var.project_name}-${var.environment}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecr"
  }
}

resource "aws_ecr_lifecycle_policy" "cleanup" {
  repository = aws_ecr_repository.this.name
  policy     = jsonencode({
    rules = [{
      rulePriority = 1,
      description  = "Keep last 10 images",
      selection    = {
        tagStatus   = "any",
        countType   = "imageCountMoreThan",
        countNumber = 10
      },
      action = { type = "expire" }
    }]
  })
}
