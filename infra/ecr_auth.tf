# Data source to obtain a temporary Docker login token for Amazon ECR
# This avoids requiring the AWS CLI. The token is valid for ~12 hours.

data "aws_ecr_authorization_token" "current" {}

# Data source to reveal the current AWS identity (useful to verify credentials without AWS CLI)
data "aws_caller_identity" "current" {}
