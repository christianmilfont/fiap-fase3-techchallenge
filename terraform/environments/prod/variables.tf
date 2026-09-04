# Variáveis comuns para todos os ambientes
# Estas variáveis são herdadas dos módulos e podem ser sobrescritas por ambiente

variable "aws_region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "AZs utilizadas pelas subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas."
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas."
  type        = list(string)
  default     = ["10.0.128.0/20", "10.0.144.0/20"]
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway para as subnets privadas."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Usa um único NAT Gateway (menor custo)."
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes do EKS."
  type        = string
  default     = "1.30"
}

variable "enable_oidc_provider" {
  description = "Cria o IAM OIDC provider do cluster (necessário para IRSA)."
  type        = bool
  default     = true
}

variable "enable_trust_conditions" {
  description = "Habilita trust conditions restritas nas IAM roles (requer STS GetCallerIdentity). Desabilite para floci ou testes locais."
  type        = bool
  default     = true
}

variable "enable_irsa_pod_role" {
  description = "Cria IAM role para pods usar IRSA (IAM Roles for Service Accounts)."
  type        = bool
  default     = true
}

variable "node_groups" {
  description = "Node groups do cluster EKS."
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
  default = {
    standard-workers = {
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size       = 1
      max_size       = 4
      subnet_type    = "private"
    }
  }
}

variable "databases" {
  description = "Instâncias RDS PostgreSQL do projeto (chave = sufixo do identifier)."
  type = map(object({
    db_name               = string
    username              = optional(string)
    engine_version        = optional(string)
    instance_class        = optional(string)
    allocated_storage     = optional(number)
    max_allocated_storage = optional(number)
    multi_az              = optional(bool)
  }))
  default = {
    auth-db      = { db_name = "auth_db" }
    flag-db      = { db_name = "flags_db" }
    targeting-db = { db_name = "targeting_db" }
  }
}

variable "rds_instance_class" {
  description = "Classe padrão das instâncias RDS."
  type        = string
  default     = "db.t3.micro"
}

variable "rds_engine_version" {
  description = "Versão padrão do PostgreSQL."
  type        = string
  default     = "15"
}

variable "redis_node_type" {
  description = "Tipo de nó do ElastiCache Redis."
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_cache_clusters" {
  description = "Número de nós do Redis."
  type        = number
  default     = 1
}

variable "redis_engine_version" {
  description = "Versão do Redis."
  type        = string
  default     = "7.0"
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB de analytics."
  type        = string
  default     = "ToggleMasterAnalytics"
}

variable "sqs_queue_name" {
  description = "Nome da fila SQS."
  type        = string
  default     = "togglemaster-queue"
}

variable "sqs_enable_dlq" {
  description = "Cria uma dead-letter queue para a fila principal."
  type        = bool
  default     = true
}

variable "ecr_repository_names" {
  description = "Repositórios ECR do projeto."
  type        = list(string)
  default = [
    "togglemaster/auth-service",
    "togglemaster/flag-service",
    "togglemaster/targeting-service",
    "togglemaster/evaluation-service",
    "togglemaster/analytics-service",
  ]
}

variable "enable_argocd" {
  description = "Instala o ArgoCD no cluster (exige acesso à API do EKS na hora do apply)."
  type        = bool
  default     = true
}

variable "argocd_chart_version" {
  description = "Versão do chart argo-cd."
  type        = string
  default     = "7.7.11"
}

variable "argocd_server_service_type" {
  description = "Tipo do Service do argocd-server (LoadBalancer expõe a UI)."
  type        = string
  default     = "LoadBalancer"
}

variable "gitops_repo_url" {
  description = "Repositório monitorado pelo ArgoCD."
  type        = string
  default     = "https://github.com/christianmilfont/fiap-fase3-techchallenge.git"
}

variable "gitops_revision" {
  description = "Branch monitorada pelo ArgoCD."
  type        = string
  default     = "main"
}

variable "tags" {
  description = "Tags adicionais aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}

variable "enable_eks" {
  description = "Habilita criação do cluster EKS. Desabilite para testes com emuladores que não suportam EKS."
  type        = bool
  default     = true
}
