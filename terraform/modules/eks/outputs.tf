output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint da API do cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "CA do cluster em base64."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group gerenciado pelo EKS para comunicação cluster/nós."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_group_names" {
  description = "Nomes dos node groups criados."
  value       = [for ng in aws_eks_node_group.this : ng.node_group_name]
}

output "oidc_provider_arn" {
  description = "ARN do IAM OIDC provider (null se desabilitado)."
  value       = var.enable_oidc_provider ? aws_iam_openid_connect_provider.this[0].arn : null
}

output "oidc_issuer_url" {
  description = "URL do issuer OIDC do cluster."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}
