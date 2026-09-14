variable "project_name" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
}

variable "eks_oidc_provider_url" {
  description = "URL do OIDC provider do cluster EKS."
  type        = string
}

variable "service_account_subject" {
  description = "Subject do ServiceAccount do External Secrets Operator (formato: system:serviceaccount:namespace:serviceaccount)."
  type        = string
  default     = "system:serviceaccount:external-secrets:external-secrets"
}

variable "secret_arns" {
  description = "ARNs dos secrets do AWS Secrets Manager que o ESO pode acessar."
  type        = list(string)
}

variable "tags" {
  description = "Tags adicionais aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}