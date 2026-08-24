output "repository_urls" {
  description = "URLs dos repositórios ECR."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "ARNs dos repositórios ECR."
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}
