output "endpoints" {
  description = "Endpoints (host:porta) de cada instância."
  value       = { for k, db in aws_db_instance.this : k => db.endpoint }
}

output "addresses" {
  description = "Hostnames de cada instância."
  value       = { for k, db in aws_db_instance.this : k => db.address }
}

output "db_names" {
  description = "Nome do banco inicial de cada instância."
  value       = { for k, db in aws_db_instance.this : k => db.db_name }
}

output "usernames" {
  description = "Usuário master de cada instância."
  value       = { for k, db in aws_db_instance.this : k => db.username }
}

output "passwords" {
  description = "Senhas geradas para cada instância."
  value       = { for k, p in random_password.this : k => p.result }
  sensitive   = true
}

output "security_group_id" {
  description = "Security group das instâncias RDS."
  value       = aws_security_group.this.id
}
