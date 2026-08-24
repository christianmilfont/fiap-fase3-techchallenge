variable "name" {
  description = "Prefixo de nomes das instâncias RDS."
  type        = string
}

variable "vpc_id" {
  description = "VPC das instâncias."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets (privadas) do DB subnet group."
  type        = list(string)
}

variable "databases" {
  description = "Mapa de instâncias PostgreSQL a criar (chave = sufixo do identifier)."
  type = map(object({
    db_name               = string
    username              = optional(string)
    engine_version        = optional(string)
    instance_class        = optional(string)
    allocated_storage     = optional(number)
    max_allocated_storage = optional(number)
    multi_az              = optional(bool)
  }))
}

variable "engine_version" {
  description = "Versão padrão do PostgreSQL."
  type        = string
  default     = "16.3"
}

variable "instance_class" {
  description = "Classe padrão das instâncias."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Armazenamento inicial padrão (GB)."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Limite de autoscaling de armazenamento (GB)."
  type        = number
  default     = 50
}

variable "master_username" {
  description = "Usuário master padrão."
  type        = string
  default     = "postgres"
}

variable "port" {
  description = "Porta do PostgreSQL."
  type        = number
  default     = 5432
}

variable "multi_az" {
  description = "Habilita Multi-AZ por padrão."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Dias de retenção de backup."
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Proteção contra exclusão."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Pula snapshot final ao destruir."
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDRs autorizados a acessar as instâncias."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "Security groups autorizados a acessar as instâncias."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
