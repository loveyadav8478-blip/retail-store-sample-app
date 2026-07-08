# =============================================================================
# ECR REPOSITORIES
# =============================================================================

locals {
  ecr_services = ["cart", "catalog", "checkout", "orders", "ui"]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.ecr_services)

  name                 = "retail-store-sample-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Service = each.key
  })
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# =============================================================================
# IAM USER FOR GITHUB ACTIONS
# =============================================================================

resource "aws_iam_user" "github_actions_ecr" {
  name = "github-actions-ecr-${var.environment}"
  path = "/ci/"

  tags = merge(local.common_tags, {
    Purpose = "GitHub Actions CI/CD ECR access"
  })
}

resource "aws_iam_access_key" "github_actions_ecr" {
  user = aws_iam_user.github_actions_ecr.name
}

# =============================================================================
# ECR IAM POLICY
# =============================================================================

resource "aws_iam_policy" "ecr_policy" {
  name        = "retail-store-ecr-policy-${var.environment}"
  description = "ECR permissions for GitHub Actions CI/CD"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRReadWrite"
        Effect = "Allow"
        Action = [
          # Read
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:ListImages",
          "ecr:GetRepositoryPolicy",
          # Write / Push
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          # Delete
          "ecr:DeleteRepository",
          "ecr:BatchDeleteImage",
          "ecr:DeleteRepositoryPolicy",
          # Create
          "ecr:CreateRepository",
          "ecr:SetRepositoryPolicy",
          "ecr:PutLifecyclePolicy",
          "ecr:TagResource"
        ]
        Resource = [for repo in aws_ecr_repository.services : repo.arn]
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_user_policy_attachment" "github_actions_ecr" {
  user       = aws_iam_user.github_actions_ecr.name
  policy_arn = aws_iam_policy.ecr_policy.arn
}

# =============================================================================
# OUTPUTS - Add these to GitHub Actions secrets
# =============================================================================

output "ecr_user_access_key_id" {
  description = "Access key ID for GitHub Actions - add as AWS_ACCESS_KEY_ID secret"
  value       = aws_iam_access_key.github_actions_ecr.id
}

output "ecr_user_secret_access_key" {
  description = "Secret access key for GitHub Actions - add as AWS_SECRET_ACCESS_KEY secret"
  value       = aws_iam_access_key.github_actions_ecr.secret
  sensitive   = true
}

output "ecr_repository_urls" {
  description = "ECR repository URLs for all services"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}
