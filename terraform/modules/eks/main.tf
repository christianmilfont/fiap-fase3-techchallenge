# Data source para obter account ID (só criado se não fornecido manualmente)
data "aws_caller_identity" "current" {
  count = var.enable_trust_conditions && var.account_id == null ? 1 : 0
}

# Local para determinar o account ID a usar
locals {
  # Se enable_trust_conditions = false, não usa account ID
  # Se account_id fornecido, usa o valor fornecido
  # Se enable_trust_conditions = true e account_id não fornecido, usa data source
  trust_account_id = var.enable_trust_conditions ? (var.account_id != null ? var.account_id : data.aws_caller_identity.current[0].account_id) : null
}

# IAM Role para o cluster EKS com trust conditions
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        # Condição condicional: apenas adicionar trust condition se enable_trust_conditions = true
        # Isso permite testar com floci (que não suporta STS GetCallerIdentity)
        Condition = var.enable_trust_conditions ? {
          StringEquals = {
            "aws:SourceAccount" = local.trust_account_id
          }
        } : null
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.cluster_name}-cluster-role" })
}

resource "aws_iam_role_policy_attachment" "clusterAmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "clusterAmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# IAM Role para os node groups com trust conditions
resource "aws_iam_role" "nodes" {
  name = "${var.cluster_name}-nodes-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        # Condição condicional: apenas adicionar trust condition se enable_trust_conditions = true
        Condition = var.enable_trust_conditions ? {
          StringEquals = {
            "aws:SourceAccount" = local.trust_account_id
          }
        } : null
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.cluster_name}-nodes-role" })
}

# IRSA - IAM Role para pods (service accounts)
resource "aws_iam_role" "pod_role" {
  count = var.enable_irsa_pod_role && var.enable_oidc_provider && !var.enable_service_irsa_roles ? 1 : 0

  name = "${var.cluster_name}-pod-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.this[0].arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.this[0].url, "https://", "")}:sub" = "system:serviceaccount:togglemaster:*"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.cluster_name}-pod-role" })
}

# IRSA - Política básica para pods (pode ser estendida por serviço)
resource "aws_iam_role_policy" "pod_policy" {
  count = var.enable_irsa_pod_role && var.enable_oidc_provider && !var.enable_service_irsa_roles ? 1 : 0

  name = "${var.cluster_name}-pod-policy"
  role = aws_iam_role.pod_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = "*"
        Condition = var.enable_trust_conditions ? {
          StringEquals = {
            "aws:ResourceAccount" : local.trust_account_id
          }
        } : null
      }
    ]
  })
}

# IRSA - Service-specific roles
# Analytics service role (SQS + DynamoDB)
resource "aws_iam_role" "analytics_service" {
  # Gated pelo OIDC provider, nao por trust conditions: o assume_role_policy
  # abaixo referencia aws_iam_openid_connect_provider.this[0], que existe
  # quando enable_oidc_provider = true. IRSA nao usa aws:SourceAccount.
  count = var.enable_service_irsa_roles && var.enable_oidc_provider ? 1 : 0

  name = "${var.cluster_name}-analytics-service"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.this[0].arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.this[0].url, "https://", "")}:sub" = "system:serviceaccount:analytics-service:analytics-service-sa"
            "${replace(aws_iam_openid_connect_provider.this[0].url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.cluster_name}-analytics-service-role" })
}

resource "aws_iam_role_policy" "analytics_service" {
  # Precisa casar exatamente com o count da role: a policy referencia
  # aws_iam_role.<role>[0].id e quebra com Invalid index se a role nao existir.
  count = var.enable_service_irsa_roles && var.enable_oidc_provider ? 1 : 0

  name = "${var.cluster_name}-analytics-service-policy"
  role = aws_iam_role.analytics_service[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_queue_arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem"
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

# Evaluation service role (SQS)
resource "aws_iam_role" "evaluation_service" {
  # Gated pelo OIDC provider, nao por trust conditions: o assume_role_policy
  # abaixo referencia aws_iam_openid_connect_provider.this[0], que existe
  # quando enable_oidc_provider = true. IRSA nao usa aws:SourceAccount.
  count = var.enable_service_irsa_roles && var.enable_oidc_provider ? 1 : 0

  name = "${var.cluster_name}-evaluation-service"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.this[0].arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.this[0].url, "https://", "")}:sub" = "system:serviceaccount:evaluation-service:evaluation-service-sa"
            "${replace(aws_iam_openid_connect_provider.this[0].url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.cluster_name}-evaluation-service-role" })
}

resource "aws_iam_role_policy" "evaluation_service" {
  # Precisa casar exatamente com o count da role: a policy referencia
  # aws_iam_role.<role>[0].id e quebra com Invalid index se a role nao existir.
  count = var.enable_service_irsa_roles && var.enable_oidc_provider ? 1 : 0

  name = "${var.cluster_name}-evaluation-service-policy"
  role = aws_iam_role.evaluation_service[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = var.sqs_queue_arn
      }
    ]
  })
}

# KEDA operator role (SQS)
resource "aws_iam_role" "keda_operator" {
  # Gated pelo OIDC provider, nao por trust conditions: o assume_role_policy
  # abaixo referencia aws_iam_openid_connect_provider.this[0], que existe
  # quando enable_oidc_provider = true. IRSA nao usa aws:SourceAccount.
  count = var.enable_service_irsa_roles && var.enable_oidc_provider ? 1 : 0

  name = "${var.cluster_name}-keda-operator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.this[0].arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.this[0].url, "https://", "")}:sub" = "system:serviceaccount:keda:keda-operator"
            "${replace(aws_iam_openid_connect_provider.this[0].url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.cluster_name}-keda-operator-role" })
}

resource "aws_iam_role_policy" "keda_operator" {
  # Precisa casar exatamente com o count da role: a policy referencia
  # aws_iam_role.<role>[0].id e quebra com Invalid index se a role nao existir.
  count = var.enable_service_irsa_roles && var.enable_oidc_provider ? 1 : 0

  name = "${var.cluster_name}-keda-operator-policy"
  role = aws_iam_role.keda_operator[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_queue_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "nodesAmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "nodesAmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "nodesAmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes.name
}

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Security group do control plane do EKS"
  vpc_id      = var.vpc_id

  egress {
    description = "Saida liberada"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-cluster-sg" })
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  tags = merge(var.tags, { Name = var.cluster_name })
}

data "tls_certificate" "oidc" {
  count = var.enable_oidc_provider ? 1 : 0

  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  count = var.enable_oidc_provider ? 1 : 0

  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc[0].certificates[0].sha1_fingerprint]

  tags = merge(var.tags, { Name = "${var.cluster_name}-oidc" })
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-${each.key}"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = each.value.subnet_type == "public" ? var.public_subnet_ids : var.private_subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  disk_size      = each.value.disk_size
  ami_type       = each.value.ami_type

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = each.value.labels

  tags = merge(var.tags, { Name = "${var.cluster_name}-${each.key}" })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
