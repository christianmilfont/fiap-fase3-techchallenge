# External Secrets Operator IRSA Role
# Permite que o External Secrets Operator leia secrets do AWS Secrets Manager via IRSA
# Elimina a necessidade de secrets manuais no Kubernetes

# IAM Role para External Secrets Operator via IRSA
resource "aws_iam_role" "eso" {
  name = "${var.project_name}-eso"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.eks_oidc_provider_arn }
      Condition = {
        StringEquals = {
          "${var.eks_oidc_provider_host}:sub" = var.service_account_subject
          "${var.eks_oidc_provider_host}:aud" = "sts.amazonaws.com"
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
