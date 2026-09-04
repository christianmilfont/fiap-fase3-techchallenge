# Ambientes ToggleMaster

Estrutura de ambientes separados para desenvolvimento e produção, seguindo as melhores práticas de Infrastructure as Code.

## 📁 Estrutura

```
terraform/
├── environments/
│   ├── dev/
│   │   ├── main.tf           # Invoca módulos com configurações de dev
│   │   ├── variables.tf      # Variáveis comuns (herdadas dos módulos)
│   │   └── dev.tfvars        # Variáveis específicas do ambiente dev
│   └── prod/
│       ├── main.tf           # Invoca módulos com configurações de prod
│       ├── variables.tf      # Variáveis comuns (herdadas dos módulos)
│       └── prod.tfvars       # Variáveis específicas do ambiente prod
├── modules/                 # Módulos reutilizáveis
│   ├── networking/
│   ├── eks/
│   ├── rds/
│   └── ...
└── bootstrap/               # Cria bucket S3 para estado remoto
```

## 🚀 Como Usar

### Ambiente de Desenvolvimento

```bash
cd terraform/environments/dev

# 1. Criar backend.hcl (usando o output do bootstrap)
cp ../../backend.hcl.example backend.hcl
# Edite backend.hcl com as credenciais do bucket

# 2. Inicializar Terraform
terraform init -backend-config=backend.hcl

# 3. Planejar (simulação)
terraform plan -var-file="dev.tfvars"

# 4. Aplicar
terraform apply -var-file="dev.tfvars" -auto-approve
```

### Ambiente de Produção

```bash
cd terraform/environments/prod

# 1. Criar backend.hcl (usando key diferente para estado separado)
cp ../../backend.hcl.example backend.hcl
# Edite backend.hcl:
# key = "togglemaster/prod.tfstate"  # Estado separado do dev

# 2. Inicializar Terraform
terraform init -backend-config=backend.hcl

# 3. Planejar (simulação)
terraform plan -var-file="prod.tfvars"

# 4. Aplicar
terraform apply -var-file="prod.tfvars" -auto-approve
```

## 🔧 Diferenças Entre Ambientes

### Desenvolvimento
- **Recursos menores**: t3.medium, db.t3.micro, cache.t3.micro
- **Single NAT Gateway**: Menor custo
- **2 AZs**: Para economia
- **Sufixo -dev**: Nos nomes dos recursos
- **Storage reduzido**: 20GB para RDS
- **1 nó Redis**: Sem replicação

### Produção
- **Recursos maiores**: t3.large, db.t3.small, cache.t3.small
- **Multi-NAT Gateway**: Alta disponibilidade
- **3 AZs**: Para resiliência
- **Sem sufixo**: Nomes de produção
- **Storage aumentado**: 50GB+ para RDS
- **Multi-AZ RDS**: Alta disponibilidade
- **2 nós Redis**: Replicação e failover
- **Tags extras**: Compliance, cost center

## 🔄 Backend Separado por Ambiente

Cada ambiente usa um estado separado no S3:

- **Dev**: `togglemaster/dev.tfstate`
- **Prod**: `togglemaster/prod.tfstate`

Isso permite:
- Mudanças independentes entre ambientes
- Rollback seguro em produção
- Testes em dev sem afetar prod
- Histórico separado por ambiente

## 🛡️ Segurança

- **Arquivos .tfvars locais**: Não versionados (contêm dados sensíveis)
- **Backend.hcl local**: Não versionado (contém credenciais do bucket)
- **Variáveis separadas**: Cada ambiente com suas próprias configurações
- **Least privilege**: Permissões IAM mínimas por ambiente

## 📊 Benefícios desta Estrutura

1. **Isolamento**: Ambientes completamente separados
2. **Reutilização**: Módulos compartilhados entre ambientes
3. **Escalabilidade**: Fácil adicionar novos ambientes (staging, uat)
4. **Manutenibilidade**: Mudanças em módulos afetam todos os ambientes
5. **Segurança**: Configurações sensíveis fora do Git
6. **Custo**: Dev otimizado para custo, prod para disponibilidade

## 🎯 Próximos Passos

- [ ] Adicionar ambiente staging
- [ ] Implementar workspaces Terraform
- [ ] Configurar remote state sharing entre ambientes
- [ ] Adicionar checks de segurança com Checkov
- [ ] Implementar IRSA (IAM Roles for Service Accounts)
