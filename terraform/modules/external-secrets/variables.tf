variable "project_name" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
}

variable "eks_oidc_provider_arn" {
  description = "ARN do IAM OIDC provider do cluster EKS. Sai do output do modulo eks — nao usar data source: no primeiro apply o provider ainda nao existe."
  type        = string
}

variable "eks_oidc_provider_host" {
  description = "Host do OIDC provider sem o prefixo https:// (ex: oidc.eks.us-east-1.amazonaws.com/id/XXXX). Sai de replace(module.eks.oidc_issuer_url, ...)."
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
