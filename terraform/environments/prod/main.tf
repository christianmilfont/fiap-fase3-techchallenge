# Ambiente de Produção
# Invoca os módulos principais com configurações otimizadas para produção

locals {
  name = "togglemaster-prod"

  tags = merge({
    Project     = "togglemaster"
    Environment = "prod"
    ManagedBy   = "terraform"
  }, var.tags)
}

module "networking" {
  source = "../../modules/networking"

  name                 = local.name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  tags                 = local.tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name              = local.name
  kubernetes_version        = var.kubernetes_version
  enable_oidc_provider      = var.enable_oidc_provider
  enable_trust_conditions   = var.enable_trust_conditions
  enable_irsa_pod_role      = var.enable_irsa_pod_role
  enable_service_irsa_roles = var.enable_service_irsa_roles
  vpc_id                    = module.networking.vpc_id
  private_subnet_ids        = module.networking.private_subnet_ids
  public_subnet_ids         = module.networking.public_subnet_ids
  node_groups               = var.node_groups
  sqs_queue_arn             = module.sqs.queue_arn
  dynamodb_table_arn        = module.dynamodb.table_arn
  tags                      = local.tags
}

module "rds" {
  source = "../../modules/rds"

  name           = local.name
  vpc_id         = module.networking.vpc_id
  subnet_ids     = module.networking.private_subnet_ids
  databases      = var.databases
  instance_class = var.rds_instance_class
  engine_version = var.rds_engine_version

  allowed_cidr_blocks        = [module.networking.vpc_cidr]
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  tags = local.tags
}

module "elasticache" {
  source = "../../modules/elasticache"

  name               = local.name
  vpc_id             = module.networking.vpc_id
  subnet_ids         = module.networking.private_subnet_ids
  node_type          = var.redis_node_type
  num_cache_clusters = var.redis_num_cache_clusters
  engine_version     = var.redis_engine_version

  allowed_cidr_blocks        = [module.networking.vpc_cidr]
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  tags = local.tags
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  table_name = var.dynamodb_table_name
  hash_key   = "event_id"

  attributes = [
    { name = "event_id", type = "S" },
  ]

  tags = local.tags
}

module "sqs" {
  source = "../../modules/sqs"

  queue_name = var.sqs_queue_name
  enable_dlq = var.sqs_enable_dlq
  tags       = local.tags
}

module "ecr" {
  source = "../../modules/ecr"

  repository_names = var.ecr_repository_names
  tags             = local.tags
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  project_name        = local.name
  github_repositories = var.github_repositories
  ecr_repository_arns = values(module.ecr.repository_arns)
  tags                = local.tags
}

module "external_secrets" {
  source = "../../modules/external-secrets"

  project_name            = local.name
  eks_oidc_provider_url   = module.eks.oidc_issuer_url
  service_account_subject = var.eso_service_account_subject
  secret_arns             = values(module.secrets_manager.app_secret_arns)
  tags                    = local.tags
}

module "secrets_manager" {
  source = "../../modules/secrets-manager"

  project_name            = local.name
  secret_prefix           = var.secret_prefix
  recovery_window_in_days = var.recovery_window_in_days
  auth_database_url       = "postgres://${module.rds.usernames["auth-db"]}:${urlencode(module.rds.passwords["auth-db"])}@${module.rds.addresses["auth-db"]}:5432/${module.rds.db_names["auth-db"]}"
  flag_database_url       = "postgres://${module.rds.usernames["flag-db"]}:${urlencode(module.rds.passwords["flag-db"])}@${module.rds.addresses["flag-db"]}:5432/${module.rds.db_names["flag-db"]}"
  targeting_database_url  = "postgres://${module.rds.usernames["targeting-db"]}:${urlencode(module.rds.passwords["targeting-db"])}@${module.rds.addresses["targeting-db"]}:5432/${module.rds.db_names["targeting-db"]}"
  redis_url               = "redis://${module.elasticache.primary_endpoint_address}:${module.elasticache.port}"
  tags                    = local.tags
}
