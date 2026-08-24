output "primary_endpoint_address" {
  description = "Endpoint primário do Redis."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Endpoint de leitura do Redis."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Porta do Redis."
  value       = var.port
}

output "security_group_id" {
  description = "Security group do cluster Redis."
  value       = aws_security_group.this.id
}
