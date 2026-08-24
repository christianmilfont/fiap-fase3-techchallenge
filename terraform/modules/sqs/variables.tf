variable "queue_name" {
  description = "Nome da fila (sem sufixo .fifo)."
  type        = string
}

variable "fifo_queue" {
  description = "Cria a fila como FIFO."
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Deduplicação por conteúdo (apenas FIFO)."
  type        = bool
  default     = true
}

variable "visibility_timeout_seconds" {
  description = "Tempo de invisibilidade da mensagem em processamento."
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "Retenção das mensagens na fila."
  type        = number
  default     = 345600
}

variable "delay_seconds" {
  description = "Atraso de entrega das mensagens."
  type        = number
  default     = 0
}

variable "max_message_size" {
  description = "Tamanho máximo da mensagem em bytes."
  type        = number
  default     = 262144
}

variable "receive_wait_time_seconds" {
  description = "Long polling (segundos)."
  type        = number
  default     = 10
}

variable "enable_dlq" {
  description = "Cria uma dead-letter queue associada."
  type        = bool
  default     = true
}

variable "max_receive_count" {
  description = "Tentativas antes de mover a mensagem para a DLQ."
  type        = number
  default     = 5
}

variable "dlq_message_retention_seconds" {
  description = "Retenção das mensagens na DLQ."
  type        = number
  default     = 1209600
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
