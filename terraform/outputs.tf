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
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint da API do EKS."
  value       = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Comando para configurar o kubectl."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "rds_endpoints" {
  description = "Endpoints das instâncias PostgreSQL."
  value       = module.rds.endpoints
}

output "rds_passwords" {
  description = "Senhas geradas das instâncias PostgreSQL."
  value       = module.rds.passwords
  sensitive   = true
}

output "database_urls" {
  description = "DATABASE_URL pronta para os Secrets dos microserviços."
  value = {
    for k, addr in module.rds.addresses :
    k => "postgres://${module.rds.usernames[k]}:${urlencode(module.rds.passwords[k])}@${addr}:5432/${module.rds.db_names[k]}"
  }
  sensitive = true
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
  description = "URL da fila SQS (AWS_SQS_URL dos configmaps)."
  value       = module.sqs.queue_url
}

output "eks_oidc_provider_arn" {
  description = "ARN do OIDC provider do cluster (IRSA)."
  value       = module.eks.oidc_provider_arn
}

output "ecr_repository_urls" {
  description = "URLs dos repositórios ECR."
  value       = module.ecr.repository_urls
}

output "argocd_namespace" {
  description = "Namespace do ArgoCD (null quando enable_argocd = false)."
  value       = var.enable_argocd ? module.argocd[0].namespace : null
}

output "argocd_admin_password_command" {
  description = "Comando para ler a senha inicial do admin do ArgoCD."
  value       = var.enable_argocd ? module.argocd[0].admin_password_command : null
}

output "argocd_server_url_command" {
  description = "Comando para descobrir o DNS do LoadBalancer da UI do ArgoCD."
  value       = var.enable_argocd ? module.argocd[0].server_url_command : null
}
