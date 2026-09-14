output "eso_role_arn" {
  description = "ARN da IAM role para External Secrets Operator."
  value       = aws_iam_role.eso.arn
}

output "eso_role_name" {
  description = "Nome da IAM role para External Secrets Operator."
  value       = aws_iam_role.eso.name
}