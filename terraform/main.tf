locals {
  name = var.project_name

  tags = merge({
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

module "networking" {
  source = "./modules/networking"

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
  source = "./modules/eks"

  cluster_name            = local.name
  kubernetes_version      = var.kubernetes_version
  enable_oidc_provider    = var.enable_oidc_provider
  enable_trust_conditions = var.enable_trust_conditions
  enable_irsa_pod_role    = var.enable_irsa_pod_role
  vpc_id                  = module.networking.vpc_id
  private_subnet_ids      = module.networking.private_subnet_ids
  public_subnet_ids       = module.networking.public_subnet_ids
  node_groups             = var.node_groups
  tags                    = local.tags
}

module "rds" {
  source = "./modules/rds"

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
  source = "./modules/elasticache"

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
  source = "./modules/dynamodb"

  table_name = var.dynamodb_table_name
  hash_key   = "event_id"

  attributes = [
    { name = "event_id", type = "S" },
  ]

  tags = local.tags
}

module "sqs" {
  source = "./modules/sqs"

  queue_name = var.sqs_queue_name
  enable_dlq = var.sqs_enable_dlq
  tags       = local.tags
}

module "ecr" {
  source = "./modules/ecr"

  repository_names = var.ecr_repository_names
  tags             = local.tags
}

module "argocd" {
  source = "./modules/argocd"
  count  = var.enable_argocd ? 1 : 0

  chart_version       = var.argocd_chart_version
  server_service_type = var.argocd_server_service_type
  gitops_repo_url     = var.gitops_repo_url
  gitops_revision     = var.gitops_revision

  depends_on = [module.eks]
}
