variable "project_name" {
  description = "Nome do projeto, usado no nome do bucket de estado."
  type        = string
  default     = "togglemaster"
}

variable "aws_region" {
  description = "Região do bucket de estado."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Nome exato do bucket de estado. Se null, gera um nome com sufixo aleatório."
  type        = string
  default     = null
}
