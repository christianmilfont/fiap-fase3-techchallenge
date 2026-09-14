output "app_secret_arns" {
  description = "ARNs dos secrets do AWS Secrets Manager (map: serviço => arn)."
  value = {
    auth       = aws_secretsmanager_secret.auth.arn
    flag       = aws_secretsmanager_secret.flag.arn
    targeting  = aws_secretsmanager_secret.targeting.arn
    evaluation = aws_secretsmanager_secret.evaluation.arn
  }
}

output "master_key" {
  description = "MASTER_KEY gerado (sensitive)."
  value       = random_password.master_key.result
  sensitive   = true
}

output "service_api_key" {
  description = "SERVICE_API_KEY gerado (sensitive)."
  value       = random_password.service_api_key.result
  sensitive   = true
}