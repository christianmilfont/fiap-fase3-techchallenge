variable "project_name" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
}

variable "github_repositories" {
  description = "Lista de repositórios GitHub que podem assumir esta role (formato: repo:owner/repo:*)."
  type        = list(string)
  default = [
    "repo:alansenairj/auth-service:*",
    "repo:alansenairj/evaluation-service:*",
    "repo:alansenairj/flag-service:*",
    "repo:alansenairj/targeting-service:*",
    "repo:alansenairj/analytics-service:*",
  ]
}

variable "ecr_repository_arns" {
  description = "ARNs dos repositórios ECR que a role pode acessar para push."
  type        = list(string)
}

variable "tags" {
  description = "Tags adicionais aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}