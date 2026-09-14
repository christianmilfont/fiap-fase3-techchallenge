output "github_actions_role_arn" {
  description = "ARN da IAM role para GitHub Actions."
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Nome da IAM role para GitHub Actions."
  value       = aws_iam_role.github_actions.name
}

output "github_oidc_provider_arn" {
  description = "ARN do OIDC provider do GitHub."
  value       = aws_iam_openid_connect_provider.github.arn
}