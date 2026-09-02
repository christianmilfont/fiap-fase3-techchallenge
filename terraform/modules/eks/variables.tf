variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes do control plane."
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "VPC onde o cluster será criado."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas do cluster."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Subnets públicas do cluster."
  type        = list(string)
}

variable "enable_oidc_provider" {
  description = "Cria o IAM OIDC provider do cluster (necessário para IRSA)."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Habilita o endpoint privado da API do cluster."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Habilita o endpoint público da API do cluster."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs autorizados a acessar o endpoint público da API."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "authentication_mode" {
  description = "Modo de autenticação do cluster (API, API_AND_CONFIG_MAP ou CONFIG_MAP)."
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "enabled_cluster_log_types" {
  description = "Tipos de log do control plane enviados ao CloudWatch."
  type        = list(string)
  default     = ["api", "audit"]
}

variable "node_groups" {
  description = "Mapa de node groups gerenciados do cluster."
  type = map(object({
    instance_types = optional(list(string), ["t3.medium"])
    capacity_type  = optional(string, "ON_DEMAND")
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    disk_size      = optional(number, 20)
    desired_size   = optional(number, 2)
    min_size       = optional(number, 1)
    max_size       = optional(number, 4)
    subnet_type    = optional(string, "private")
    labels         = optional(map(string), {})
  }))
  default = {}
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
