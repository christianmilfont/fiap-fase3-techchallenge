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

## IAM Roles Automáticas

O Terraform cria automaticamente as IAM roles necessárias para o EKS:
- Role do cluster (com políticas AmazonEKSClusterPolicy e AmazonEKSVPCResourceController)
- Role dos node groups (com políticas AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy e AmazonEC2ContainerRegistryReadOnly)

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

## ArgoCD

O módulo `argocd` instala o chart oficial no cluster via provider `helm`, que se
autentica com `aws eks get-token` (o token é gerado no apply, não fica no estado).

```bash
terraform apply                                        # instala o ArgoCD junto da infra
terraform output -raw argocd_admin_password_command | bash   # senha inicial do admin
terraform output -raw argocd_server_url_command | bash       # DNS do LoadBalancer da UI
```

Como o provider precisa falar com a API do EKS, o primeiro `apply` em uma conta
vazia pode falhar ao criar o `helm_release` antes de o endpoint responder. Nesse
caso rode com `-var enable_argocd=false` e depois um segundo apply sem a flag.

Depois disso, `kubectl apply -f gitops/argocd/root-app.yaml` registra as 5
Applications (veja `gitops/README.md`).
