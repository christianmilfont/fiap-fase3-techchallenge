# Infraestrutura como Código — ToggleMaster (Fase 3)

Projeto Terraform que substitui a criação manual da Fase 2. Toda a infraestrutura é
provisionada por módulos e o estado fica em um bucket S3 (backend remoto).

## Estrutura

```
terraform/
├── bootstrap/            # cria o bucket S3 do estado remoto (estado local, roda 1x)
├── environments/         # ambientes separados (dev, prod)
│   ├── dev/              # configurações de desenvolvimento
│   │   ├── main.tf       # invoca módulos com config de dev
│   │   ├── variables.tf  # variáveis comuns
│   │   └── dev.tfvars    # variáveis específicas do dev
│   └── prod/             # configurações de produção
│       ├── main.tf       # invoca módulos com config de prod
│       ├── variables.tf  # variáveis comuns
│       └── prod.tfvars   # variáveis específicas do prod
├── modules/
│   ├── networking/       # VPC, subnets públicas/privadas, IGW, NAT, route tables
│   ├── eks/              # cluster EKS + node groups com IAM roles automáticas
│   ├── rds/              # instâncias PostgreSQL + subnet group + security group
│   ├── elasticache/      # cluster Redis (replication group)
│   ├── dynamodb/         # tabela ToggleMasterAnalytics
│   ├── sqs/              # fila principal + DLQ
│   ├── ecr/              # repositórios de imagens
│   └── argocd/           # Helm chart do ArgoCD
├── backend.tf            # backend S3 com use_lockfile
├── main.tf               # composição dos módulos (uso direto, sem separação de ambientes)
├── variables.tf / outputs.tf
├── .checkov.yaml         # configuração de security scanning
├── backend.hcl.example
└── terraform.tfvars.example
```

## 🚀 Como Usar

### Opção 1: Usar Estrutura de Ambientes (Recomendado)

Para projetos com ambientes separados (dev/prod), use a estrutura `environments/`:

```bash
# Ambiente de Desenvolvimento
cd terraform/environments/dev
cp ../../backend.hcl.example backend.hcl  # preencha com o output do bootstrap
terraform init -backend-config=backend.hcl
terraform plan -var-file="dev.tfvars"
terraform apply -var-file="dev.tfvars" -auto-approve

# Ambiente de Produção
cd terraform/environments/prod
cp ../../backend.hcl.example backend.hcl  # key diferente: togglemaster/prod.tfstate
terraform init -backend-config=backend.hcl
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars" -auto-approve
```

Veja `terraform/environments/README.md` para documentação completa.

### Opção 2: Uso Direto (Ambiente Único)

Para uso simples ou testes rápidos:

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output backend_config

cd ..
cp backend.hcl.example backend.hcl     # preencha com o output acima
cp terraform.tfvars.example terraform.tfvars

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

### Passo 1 — Bootstrap do backend remoto

O bucket de estado não pode ser criado pelo mesmo state que ele guarda, então roda antes:

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output backend_config
```

### Passo 2 — Infraestrutura

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

## IAM Roles Automáticas & Segurança

O Terraform cria automaticamente as IAM roles necessárias para o EKS:

### IAM Roles
- **Cluster role**: AmazonEKSClusterPolicy + AmazonEKSVPCResourceController
- **Node groups role**: AmazonEKSWorkerNodePolicy + AmazonEKS_CNI_Policy + AmazonEC2ContainerRegistryReadOnly
- **Pod role (IRSA)**: IAM role para pods usar IRSA (IAM Roles for Service Accounts)

### Security Features
- **Trust conditions**: Condições restritas em assume role policies
- **Account isolation**: Condições `aws:SourceAccount` para evitar cross-account access
- **IRSA**: Pods podem acessar AWS resources com permissões específicas
- **Least privilege**: Políticas IAM restritivas e específicas

### Security Scanning
- **Checkov integration**: Configuração `.checkov.yaml` com 40+ security checks
- **Automated scanning**: `checkov -d terraform/ -f terraform/.checkov.yaml`
- **Cobertura**: IAM, EKS, RDS, S3, VPC security checks

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

## 🔒 Segurança - Arquivos Locais

Por segurança, alguns arquivos devem ser criados localmente e **não versionados**:

### Arquivos Não Versionados
- **`terraform.tfvars`**: Contém variáveis específicas do ambiente (credenciais, configurações)
- **`backend.hcl`**: Contém credenciais do bucket S3 (bucket, key, region)
- **Arquivos de ambiente**: `environments/dev/backend.hcl`, `environments/prod/backend.hcl`

### Proteção via .gitignore
O `.gitignore` do Terraform bloqueia automaticamente:
```gitignore
*.tfvars
!*.tfvars.example
backend.hcl
!backend.hcl.example
```

### Templates Disponíveis
- **`terraform.tfvars.example`**: Template para criar `terraform.tfvars` local
- **`backend.hcl.example`**: Template para criar `backend.hcl` local
- **`environments/dev/dev.tfvars`**: Configurações de desenvolvimento
- **`environments/prod/prod.tfvars`**: Configurações de produção

### Benefícios
- **Zero dados sensíveis no Git**: Credenciais e configurações específicas ficam locais
- **Flexibilidade por ambiente**: Cada desenvolvedor pode ter suas próprias configurações
- **Segurança**: Segredos nunca são commitados no repositório
- **Colaboração segura**: .example files permitem colaboração sem expor dados sensíveis
