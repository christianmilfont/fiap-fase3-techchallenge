# AWS Secrets Manager para secrets dos serviços
# Armazena DATABASE_URL, MASTER_KEY, SERVICE_API_KEY, etc.
# Elimina a necessidade de secrets manuais no Kubernetes

# Generate random password for MASTER_KEY (usado como SERVICE_API_KEY tambem)
resource "random_password" "master_key" {
  length           = 64
  special          = false
  override_special = ""
}

# Secret for auth service
resource "aws_secretsmanager_secret" "auth" {
  name                    = "${var.secret_prefix}/auth"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, { Name = "${var.secret_prefix}-auth" })
}

resource "aws_secretsmanager_secret_version" "auth" {
  secret_id = aws_secretsmanager_secret.auth.id
  secret_string = jsonencode({
    DATABASE_URL = var.auth_database_url
    MASTER_KEY   = random_password.master_key.result
  })
}

# Secret for flag service
resource "aws_secretsmanager_secret" "flag" {
  name                    = "${var.secret_prefix}/flag"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, { Name = "${var.secret_prefix}-flag" })
}

resource "aws_secretsmanager_secret_version" "flag" {
  secret_id = aws_secretsmanager_secret.flag.id
  secret_string = jsonencode({
    DATABASE_URL = var.flag_database_url
  })
}

# Secret for targeting service
resource "aws_secretsmanager_secret" "targeting" {
  name                    = "${var.secret_prefix}/targeting"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, { Name = "${var.secret_prefix}-targeting" })
}

resource "aws_secretsmanager_secret_version" "targeting" {
  secret_id = aws_secretsmanager_secret.targeting.id
  secret_string = jsonencode({
    DATABASE_URL = var.targeting_database_url
  })
}

# Secret for evaluation service
resource "aws_secretsmanager_secret" "evaluation" {
  name                    = "${var.secret_prefix}/evaluation"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, { Name = "${var.secret_prefix}-evaluation" })
}

resource "aws_secretsmanager_secret_version" "evaluation" {
  secret_id = aws_secretsmanager_secret.evaluation.id
  secret_string = jsonencode({
    REDIS_URL       = var.redis_url
    # Mesma chave do auth: o evaluation chama /validate no auth-service, que
    # valida contra o MASTER_KEY que ele proprio le. Se forem diferentes, a
    # chamada falha — a "chave de servico" e a master key tem que ser a mesma.
    SERVICE_API_KEY = random_password.master_key.result
  })
}