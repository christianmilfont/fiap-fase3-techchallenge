variable "project_name" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
}

variable "secret_prefix" {
  description = "Prefixo para os nomes dos secrets no Secrets Manager."
  type        = string
  default     = "togglemaster"
}

variable "recovery_window_in_days" {
  description = "Dias de recuperação antes de permitir delete imediato (0 permite delete imediato para labs)."
  type        = number
  default     = 0
}

variable "auth_database_url" {
  description = "DATABASE_URL para o auth service."
  type        = string
  sensitive   = true
}

variable "flag_database_url" {
  description = "DATABASE_URL para o flag service."
  type        = string
  sensitive   = true
}

variable "targeting_database_url" {
  description = "DATABASE_URL para o targeting service."
  type        = string
  sensitive   = true
}

variable "redis_url" {
  description = "REDIS_URL para o evaluation service."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags adicionais aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}