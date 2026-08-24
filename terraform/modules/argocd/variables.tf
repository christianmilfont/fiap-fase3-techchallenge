variable "namespace" {
  description = "Namespace onde o ArgoCD é instalado."
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "Versão do chart argo-cd."
  type        = string
  default     = "7.7.11"
}

variable "apps_chart_version" {
  description = "Versão do chart argocd-apps usado no bootstrap do app-of-apps."
  type        = string
  default     = "2.0.2"
}

variable "server_service_type" {
  description = "Tipo do Service do argocd-server (LoadBalancer expõe a UI)."
  type        = string
  default     = "LoadBalancer"
}

variable "server_domain" {
  description = "Domínio da UI do ArgoCD (opcional; vazio usa o DNS do LoadBalancer)."
  type        = string
  default     = ""
}

variable "enable_root_app" {
  description = "Cria a Application raiz (app-of-apps) apontando para o repositório GitOps."
  type        = bool
  default     = true
}

variable "gitops_repo_url" {
  description = "URL do repositório com os manifests GitOps."
  type        = string
}

variable "gitops_revision" {
  description = "Branch/tag monitorada pelo ArgoCD."
  type        = string
  default     = "main"
}

variable "gitops_argocd_path" {
  description = "Caminho, dentro do repositório, com o AppProject e as Applications."
  type        = string
  default     = "gitops/argocd"
}
