# GitHub Actions OIDC Provider
# Permite que workflows do GitHub Actions assumam uma role IAM via OIDC
# Elimina a necessidade de credenciais estáticas (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY)

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(var.tags, { Name = "${var.project_name}-github-oidc" })
}

# IAM Role para GitHub Actions
# Esta role será assumida pelos workflows do GitHub Actions via OIDC
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        # Restringe aos repositórios especificados
        StringLike = {
          "token.actions.githubusercontent.com:sub" = var.github_repositories
        }
      }
    }]
  })

  tags = merge(var.tags, { Name = "${var.project_name}-github-actions-role" })
}

# Policy para permitir push nos repositórios ECR
resource "aws_iam_role_policy" "ecr_push" {
  name = "${var.project_name}-github-actions-ecr-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage"
        ]
        Resource = var.ecr_repository_arns
      }
    ]
  })
}