variable "name" {
  description = "Prefixo de nomes do cluster Redis."
  type        = string
}

variable "vpc_id" {
  description = "VPC do cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets (privadas) do subnet group."
  type        = list(string)
}

variable "node_type" {
  description = "Tipo do nó do ElastiCache."
  type        = string
  default     = "cache.t3.micro"
}

variable "engine_version" {
  description = "Versão do Redis."
  type        = string
  default     = "7.1"
}

variable "num_cache_clusters" {
  description = "Quantidade de nós (1 = sem réplica)."
  type        = number
  default     = 1
}

variable "port" {
  description = "Porta do Redis."
  type        = number
  default     = 6379
}

variable "at_rest_encryption_enabled" {
  description = "Criptografia em repouso."
  type        = bool
  default     = true
}

variable "transit_encryption_enabled" {
  description = "Criptografia em trânsito (TLS)."
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDRs autorizados a acessar o Redis."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "Security groups autorizados a acessar o Redis."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
