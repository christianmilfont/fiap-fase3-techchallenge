# External Secrets Operator IRSA Role
# Permite que o External Secrets Operator leia secrets do AWS Secrets Manager via IRSA
# Elimina a necessidade de secrets manuais no Kubernetes

# Data source para obter o OIDC provider ARN do cluster EKS
data "aws_iam_openid_connect_provider" "eks" {
  url = var.eks_oidc_provider_url
}

# IAM Role para External Secrets Operator via IRSA
resource "aws_iam_role" "eso" {
  name = "${var.project_name}-eso"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = data.aws_iam_openid_connect_provider.eks.arn }
      Condition = {
        StringEquals = {
          "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = var.service_account_subject
          "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, { Name = "${var.project_name}-eso-role" })
}

# Policy para permitir acesso ao Secrets Manager
resource "aws_iam_role_policy" "secrets_manager" {
  name = "${var.project_name}-eso-secrets-manager-policy"
  role = aws_iam_role.eso.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.secret_arns
      }
    ]
  })
}