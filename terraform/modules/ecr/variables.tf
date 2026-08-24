variable "repository_names" {
  description = "Nomes dos repositórios ECR."
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "MUTABLE ou IMMUTABLE."
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Habilita scan de vulnerabilidades no push."
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Permite destruir repositórios com imagens."
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Quantidade de imagens mantidas pela lifecycle policy (0 desabilita)."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
