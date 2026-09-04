# Guia de Testes com Floci - Ambiente Dev

Este guia explica como testar a infraestrutura Terraform usando o floci (emulador AWS local) para testes rápidos sem custos na AWS.

## 🎯 Por que Usar Floci?

- ✅ **Testes rápidos:** Sem necessidade de recursos AWS reais
- ✅ **Zero custos:** Nenhuma cobrança da AWS durante testes
- ✅ **Iteração rápida:** Valide mudanças instantaneamente
- ✅ **Ambiente isolado:** Não afeta infraestrutura de produção
- ✅ **Completamente local:** Funciona mesmo sem internet

## 📋 Pré-requisitos

### 1. Docker e Docker Compose
```bash
docker --version
docker-compose --version
```

### 2. Floci Emulador
O floci já está configurado no projeto em `floci/`

### 3. Terraform
```bash
terraform --version
```

### 4. AWS CLI (Opcional, para verificar recursos)
```bash
aws --version
```

## 🚀 Passo a Passo

### Passo 1: Iniciar o Floci

```bash
cd floci
docker-compose up -d
```

**Verificar se está rodando:**
```bash
docker ps
# Deve mostrar o container floci-k8s rodando
```

### Passo 2: Executar Script de Inicialização

```bash
bash floci-init.sh
```

**Este script cria:**
- SQS: togglemaster-queue
- DynamoDB: ToggleMasterAnalytics
- ElastiCache: togglemaster-redis (porta 6379)
- RDS: auth-db (7001), flag-db (7002), targeting-db (7003)
- ECR: 5 repositórios básicos
- Docker login no ECR local

### Passo 3: Configurar Terraform para Floci

O ambiente dev já está configurado com `providers.tf` para usar o floci:

```bash
cd terraform/environments/dev
```

**Arquivos de configuração:**
- `providers.tf` - Provider AWS configurado para localhost:4566
- `backend.hcl` - Backend local (terraform.tfstate)
- `dev_floci.tfvars` - Variáveis otimizadas para floci

### Passo 4: Inicializar Terraform

```bash
terraform init -reconfigure
```

### Passo 5: Rodar Checkov (Security Scanning)

```bash
cd ../..
checkov -d . -f .checkov.yaml
```

**Checkov analisará:**
- IAM security checks
- EKS security checks  
- RDS security checks
- S3 security checks
- VPC security checks
- ECR security checks

### Passo 6: Planejar (Simulação)

```bash
cd environments/dev
terraform plan -var-file="dev_floci.tfvars"
```

**O que será criado (sem EKS):**
- ✅ VPC, subnets públicas/privadas
- ✅ Internet Gateway, route tables
- ✅ RDS PostgreSQL (3 instâncias)
- ✅ ElastiCache Redis
- ✅ DynamoDB tabela
- ✅ SQS fila + DLQ
- ✅ ECR repositórios (com sufixo -floci)
- ❌ EKS cluster (desabilitado para floci)
- ❌ ArgoCD (desabilitado sem EKS)

### Passo 7: Aplicar (Criar Recursos)

```bash
terraform apply -var-file="dev_floci.tfvars" -auto-approve
```

### Passo 8: Verificar Recursos Criados

```bash
# Verificar VPCs
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request ec2 describe-vpcs

# Verificar instâncias RDS
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request rds describe-db-instances

# Verificar filas SQS
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request sqs list-queues

# Verificar tabelas DynamoDB
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request dynamodb list-tables

# Verificar repositórios ECR
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request ecr describe-repositories
```

### Passo 9: Testar Conexões

```bash
# Testar conexão RDS (porta 7001)
nc -zv localhost 7001

# Testar conexão Redis (porta 6379)
nc -zv localhost 6379

# Testar ECR
docker pull alpine
docker tag alpine localhost:5100/togglemaster/auth-service-floci:test
docker push localhost:5100/togglemaster/auth-service-floci:test
```

### Passo 10: Destruir Recursos

```bash
terraform destroy -var-file="dev_floci.tfvars" -auto-approve
```

### Passo 11: Parar Floci

```bash
cd ../../floci
docker-compose down
```

## 🔧 Configurações Específicas do Floci

### Variáveis em dev_floci.tfvars

```hcl
# Trust conditions desabilitadas (floci não suporta STS)
enable_trust_conditions = false
enable_irsa_pod_role = false
enable_oidc_provider = false

# EKS desabilitado (floci não suporta EKS completamente)
enable_eks = false

# NAT Gateway desabilitado (floci não suporta NAT)
enable_nat_gateway = false
single_nat_gateway = false

# Apenas 1 AZ (floci simplificado)
availability_zones = ["us-east-1a"]
public_subnet_cidrs = ["10.0.0.0/20"]
private_subnet_cidrs = ["10.0.128.0/20"]

# Repositórios com sufixo para evitar conflitos
ecr_repository_names = [
  "togglemaster/auth-service-floci",
  "togglemaster/flag-service-floci",
  "togglemaster/targeting-service-floci",
  "togglemaster/evaluation-service-floci",
  "togglemaster/analytics-service-floci",
]
```

### Provider Configuração

```hcl
provider "aws" {
  region = "us-east-1"
  
  # Credenciais dummy para floci
  access_key          = "test"
  secret_key          = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id = true
  
  # Endpoints locais do floci
  endpoints {
    ec2       = "http://localhost:4566"
    eks       = "http://localhost:4566"
    elasticache = "http://localhost:4566"
    rds       = "http://localhost:4566"
    sqs       = "http://localhost:4566"
    dynamodb  = "http://localhost:4566"
    ecr       = "http://localhost:4566"
    iam       = "http://localhost:4566"
    s3        = "http://localhost:4566"
  }
  
  s3_use_path_style = true
}
```

## 🐛 Troubleshooting

### Problema: "InvalidClientTokenId"
**Solução:** Verifique se o floci está rodando:
```bash
docker ps | grep floci
```

### Problema: "RepositoryAlreadyExistsException"
**Solução:** Os repositórios já existem no floci. Use nomes com sufixo `-floci` ou destrua os existentes:
```bash
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  ecr delete-repository --repository-name togglemaster/auth-service --force
```

### Problema: "deserialization failed" (EKS)
**Solução:** EKS não é suportado completamente pelo floci. Use `enable_eks = false` no tfvars.

### Problema: "Backend configuration missing"
**Solução:** Remova o arquivo `backend.hcl` ou use o backend local padrão:
```bash
rm backend.hcl
terraform init -reconfigure
```

## 📊 Serviços Suportados vs Não Suportados

### ✅ Suportados pelo Floci
- ✅ VPC, subnets, route tables
- ✅ Security groups
- ✅ RDS PostgreSQL
- ✅ ElastiCache Redis
- ✅ DynamoDB
- ✅ SQS
- ✅ ECR
- ✅ IAM (limitado)
- ✅ S3

### ❌ Não Suportados (ou limitado)
- ❌ EKS (não suporta cluster real)
- ❌ NAT Gateway
- ❌ Load Balancers
- ❌ KMS (limitado)
- ❌ Lambda (limitado)

## 🎯 Fluxo de Trabalho Recomendado

### Para Desenvolvimento Iterativo
```bash
# 1. Fazer mudança no código
vim terraform/modules/rds/main.tf

# 2. Rodar Checkov
checkov -d terraform/ -f terraform/.checkov.yaml

# 3. Testar com floci
cd terraform/environments/dev
terraform plan -var-file="dev_floci.tfvars"
terraform apply -var-file="dev_floci.tfvars" -auto-approve

# 4. Validar manualmente
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request rds describe-db-instances

# 5. Destruir e repetir
terraform destroy -var-file="dev_floci.tfvars" -auto-approve
```

### Para Deploy em Produção
```bash
# 1. Após validar com floci, usar AWS real
cd terraform/environments/prod

# 2. Usar configurações de produção
terraform init -backend-config=backend.hcl
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars" -auto-approve
```

## 📚 Comparação: Floci vs AWS Real

| Característica | Floci | AWS Real |
|---------------|--------|----------|
| Custo | $0 | Pago por uso |
| Velocidade | Instantâneo | Minutos |
| Suporte EKS | Limitado | Completo |
| Suporte NAT | Não | Sim |
| Persistência | Local (container) | Cloud |
| Confiabilidade | Teste | Produção |
| Features | Básico | Completo |

## 🎓 Aprendizado com Floci

### O que você pode testar:
- ✅ Sintaxe Terraform
- ✅ Lógica condicional
- ✅ Dependências entre módulos
- ✅ Security scanning (Checkov)
- ✅ Estrutura de variáveis
- ✅ Módulos reutilizáveis

### O que você deve validar na AWS real:
- ✅ Funcionamento EKS completo
- ✅ Integração com pods
- ✅ Performance real
- ✅ Scaling automático
- ✅ Custos reais

## 🚀 Next Steps

Após validar com floci:
1. Rodar os mesmos testes em ambiente staging AWS
2. Validar checkov com recursos reais
3. Testar integração com aplicação
4. Deploy em produção com confiança

---

**Lembre-se:** Floci é para testes rápidos e validação de lógica. Sempre valide na AWS real antes de deploy em produção!
