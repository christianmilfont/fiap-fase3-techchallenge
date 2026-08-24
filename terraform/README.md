# Infraestrutura como Código — ToggleMaster (Fase 3)

Projeto Terraform que substitui a criação manual da Fase 2. Toda a infraestrutura é
provisionada por módulos e o estado fica em um bucket S3 (backend remoto).

## Estrutura

```
terraform/
├── bootstrap/            # cria o bucket S3 do estado remoto (estado local, roda 1x)
├── modules/
│   ├── networking/       # VPC, subnets públicas/privadas, IGW, NAT, route tables
│   ├── eks/              # cluster EKS + node groups (usa a LabRole)
│   ├── rds/              # instâncias PostgreSQL + subnet group + security group
│   ├── elasticache/      # cluster Redis (replication group)
│   ├── dynamodb/         # tabela ToggleMasterAnalytics
│   ├── sqs/              # fila principal + DLQ
│   └── ecr/              # repositórios de imagens
├── backend.tf            # backend S3 com use_lockfile
├── main.tf               # composição dos módulos
├── variables.tf / outputs.tf
├── backend.hcl.example
└── terraform.tfvars.example
```

## Passo 1 — Bootstrap do backend remoto

O bucket de estado não pode ser criado pelo mesmo state que ele guarda, então roda antes:

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output backend_config
```

## Passo 2 — Infraestrutura

```bash
cd terraform
cp backend.hcl.example backend.hcl     # preencha com o output acima
cp terraform.tfvars.example terraform.tfvars

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

O `backend.tf` usa `use_lockfile = true`: o lock do estado é feito pelo próprio S3
(arquivo `.tflock`), sem necessidade de tabela DynamoDB de lock. Requer Terraform >= 1.11.

## Recursos provisionados

| Item | Recurso |
| --- | --- |
| Networking | 1 VPC, 2 subnets públicas, 2 subnets privadas, IGW, NAT Gateway, route tables |
| Kubernetes | 1 cluster EKS + node groups gerenciados |
| Bancos | 3 instâncias RDS PostgreSQL: `togglemaster-auth-db`, `togglemaster-flag-db`, `togglemaster-targeting-db` |
| Cache | 1 cluster ElastiCache Redis `togglemaster-redis` |
| NoSQL | 1 tabela DynamoDB `ToggleMasterAnalytics` (hash key `event_id`) |
| Mensageria | 1 fila SQS `togglemaster-queue` + DLQ |
| Registry | 5 repositórios ECR (`togglemaster/<serviço>`) |

Os nomes reproduzem os da Fase 2 (`parte2 - kubernets/fase-c-eks.md`), então os manifestos
de `manifests-eks/` continuam válidos.

## AWS Academy (LabRole)

O ambiente do Academy não permite criar IAM roles. O módulo `eks` faz `data "aws_iam_role"`
da role existente (`lab_role_name`, padrão `LabRole`) e a associa tanto ao control plane
quanto aos node groups.

## Acesso ao cluster

```bash
terraform output -raw kubeconfig_command | bash
kubectl get nodes
```

## Preenchendo os manifests do EKS

```bash
terraform output -json database_urls        # DATABASE_URL de cada secret
terraform output -raw redis_url             # REDIS_URL do evaluation-service
terraform output -raw sqs_queue_url         # AWS_SQS_URL dos configmaps
terraform output -json ecr_repository_urls  # imagens dos deployments
```

## Senhas do RDS

São geradas por `random_password` e ficam no estado (por isso o bucket é criptografado e privado):

```bash
terraform output -json rds_passwords
```
