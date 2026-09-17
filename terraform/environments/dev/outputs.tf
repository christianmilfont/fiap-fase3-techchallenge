output "vpc_id" {
  description = "ID da VPC."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Subnets públicas."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Subnets privadas."
  value       = module.networking.private_subnet_ids
}

output "eks_cluster_name" {
  description = "Nome do cluster EKS."
  value       = var.enable_eks ? module.eks[0].cluster_name : null
}

output "eks_cluster_endpoint" {
  description = "Endpoint da API do EKS."
  value       = var.enable_eks ? module.eks[0].cluster_endpoint : null
}

output "kubeconfig_command" {
  description = "Comando para configurar o kubectl."
  value       = var.enable_eks ? "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks[0].cluster_name}" : null
}

output "rds_endpoints" {
  description = "Endpoints das instâncias PostgreSQL."
  value       = module.rds.endpoints
}

output "redis_url" {
  description = "REDIS_URL para o evaluation-service."
  value       = "redis://${module.elasticache.primary_endpoint_address}:${module.elasticache.port}"
}

output "redis_primary_endpoint" {
  description = "Endpoint primário do Redis."
  value       = module.elasticache.primary_endpoint_address
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB."
  value       = module.dynamodb.table_name
}

output "sqs_queue_url" {
  description = "URL da fila SQS."
  value       = module.sqs.queue_url
}

output "eks_oidc_provider_arn" {
  description = "ARN do OIDC provider do cluster (IRSA)."
  value       = var.enable_eks ? module.eks[0].oidc_provider_arn : null
}

output "ecr_repository_urls" {
  description = "URLs dos repositórios ECR."
  value       = module.ecr.repository_urls
}

output "github_actions_role_arn" {
  description = "ARN da IAM role para GitHub Actions (OIDC)."
  value       = module.github_oidc.github_actions_role_arn
}

output "eso_role_arn" {
  description = "ARN da IAM role para External Secrets Operator (IRSA)."
  value       = module.external_secrets.eso_role_arn
}

output "app_secret_arns" {
  description = "ARNs dos secrets do AWS Secrets Manager (map: serviço => arn)."
  value       = module.secrets_manager.app_secret_arns
}

output "analytics_role_arn" {
  description = "ARN da IAM role para analytics-service (IRSA)."
  value       = var.enable_eks ? module.eks[0].analytics_role_arn : null
}

output "evaluation_role_arn" {
  description = "ARN da IAM role para evaluation-service (IRSA)."
  value       = var.enable_eks ? module.eks[0].evaluation_role_arn : null
}

output "keda_role_arn" {
  description = "ARN da IAM role para keda-operator (IRSA)."
  value       = var.enable_eks ? module.eks[0].keda_role_arn : null
}
