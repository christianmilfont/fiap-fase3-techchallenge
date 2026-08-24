variable "table_name" {
  description = "Nome da tabela DynamoDB."
  type        = string
}

variable "billing_mode" {
  description = "PAY_PER_REQUEST ou PROVISIONED."
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "hash_key" {
  description = "Chave de partição."
  type        = string
}

variable "range_key" {
  description = "Chave de ordenação (opcional)."
  type        = string
  default     = null
}

variable "attributes" {
  description = "Atributos usados nas chaves e índices."
  type = list(object({
    name = string
    type = string
  }))
}

variable "global_secondary_indexes" {
  description = "GSIs da tabela."
  type = list(object({
    name            = string
    hash_key        = string
    range_key       = optional(string)
    projection_type = optional(string, "ALL")
  }))
  default = []
}

variable "ttl_attribute" {
  description = "Atributo de TTL (null desabilita)."
  type        = string
  default     = null
}

variable "read_capacity" {
  description = "Capacidade de leitura (apenas PROVISIONED)."
  type        = number
  default     = 5
}

variable "write_capacity" {
  description = "Capacidade de escrita (apenas PROVISIONED)."
  type        = number
  default     = 5
}

variable "point_in_time_recovery_enabled" {
  description = "Habilita PITR."
  type        = bool
  default     = false
}

variable "server_side_encryption_enabled" {
  description = "Habilita criptografia gerenciada pela AWS."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
