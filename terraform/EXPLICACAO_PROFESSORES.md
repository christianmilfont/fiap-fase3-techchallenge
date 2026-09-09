# Infraestrutura como Código (IaC) - ToggleMaster
## Explicação para Professores - Fase 3

## 🎯 Responsabilidade da Parte de IaC

Esta parte do projeto é responsável por **provisionar toda a infraestrutura cloud na AWS** através de código declarativo usando Terraform. O foco é demonstrar como substituir a criação manual de recursos (como foi feito na Fase 2) por uma abordagem automatizada, versionada e replicável.

## 🏗️ Arquitetura de Separação de Responsabilidades

Decidimos arquiteturalmente separar **Infraestrutura como Código** das **Esteiras CI/CD** da seguinte forma:

### O que fica no Terraform (IaC):
- ✅ **Recursos Cloud AWS**: VPC, Subnets, EKS, RDS, ElastiCache, DynamoDB, SQS, ECR
- ✅ **Instalação do ArgoCD**: Via Helm chart no cluster EKS
- ✅ **Configuração de Networking**: Security Groups, Route Tables, NAT Gateway
- ✅ **IAM Roles**: Permissões necessárias para o cluster EKS e pods

### O que fica nos Workflows CI/CD:
- ✅ **Build e Testes**: Compilação dos microsserviços
- ✅ **Security Scanning**: SCA, SAST, Container Scanning
- ✅ **Docker Build & Push**: Criação e push de imagens para ECR
- ✅ **GitOps**: Atualização de tags no repositório de manifests
- ✅ **Validação do Terraform**: Formatação, sintaxe, security scanning do código IaC

### ❌ O que NÃO fica no CI/CD:
- ❌ **Execução de `terraform apply`**: Aplicação de mudanças na infraestrutura
- ❌ **Criação de recursos cloud**: Isso é responsabilidade do Terraform
- ❌ **Gerenciamento de estado**: O state fica no S3, gerenciado pelo Terraform

## 📋 Por que essa Separação Faz Sentido

### 1. **Separação de Concerns**
- **IaC** gerencia a **infraestrutura** (recursos cloud)
- **CI/CD** gerencia o **software** (código das aplicações)
- Cada um tem seu ciclo de vida e responsabilidades distintas

### 2. **Segurança**
- Mudanças de infraestrutura requerem aprovação manual
- CI/CD pode rodar automaticamente em cada commit
- Evita que um commit de código destrua a infraestrutura acidentalmente

### 3. **Auditoria e Rastreabilidade**
- Mudanças de infra: `terraform plan` + aprovação humana
- Mudanças de código: pipeline automático com validações
- Histórico separado e mais claro

### 4. **Flexibilidade**
- Infraestrutura pode ser atualizada sem mudar código da aplicação
- Aplicações podem ser deployadas sem mudar infraestrutura
- Times podem trabalhar em paralelo sem conflitos

## 🔧 Estrutura do Projeto Terraform

```
terraform/
├── bootstrap/              # Cria bucket S3 para estado remoto (roda 1x)
├── environments/          # Ambientes separados (dev, prod)
│   ├── dev/              # Configurações de desenvolvimento
│   └── prod/             # Configurações de produção
├── modules/              # Módulos reutilizáveis
│   ├── networking/       # VPC, subnets, IGW, NAT
│   ├── eks/              # Cluster EKS + node groups
│   ├── rds/              # Bancos PostgreSQL
│   ├── elasticache/      # Redis cluster
│   ├── dynamodb/         # Tabela NoSQL
│   ├── sqs/              # Filas de mensageria
│   ├── ecr/              # Repositórios Docker
│   └── argocd/           # Instalação do ArgoCD
├── main.tf               # Composição dos módulos
├── variables.tf          # Variáveis de entrada
├── outputs.tf            # Saídas para uso nos manifests
└── .checkov.yaml         # Configuração de security scanning
```

## 🎥 Preparação para o Vídeo de Demonstração

### Passo 1: Bootstrap do Backend Remoto
```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output backend_config
```

### Passo 2: Configurar Backend
```bash
cd ..
cp backend.hcl.example backend.hcl
# Editar backend.hcl com o output do bootstrap
```

### Passo 3: Terraform Plan (Demonstração)
```bash
cd terraform
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
```

### Passo 4: Terraform Apply (Demonstração)
```bash
terraform apply tfplan
```

### Passo 5: Verificar Recursos Criados
```bash
# Verificar outputs importantes
terraform output -json database_urls
terraform output -raw redis_url
terraform output -raw sqs_queue_url
terraform output -json ecr_repository_urls

# Acessar o cluster
terraform output -raw kubeconfig_command | bash
kubectl get nodes
```

## 🎯 Foco do Vídeo: IaC com Terraform

### O que mostrar no vídeo (até 20 minutos):

1. **Estrutura do Código Terraform** (2-3 min)
   - Mostrar organização dos módulos
   - Explicar separação por ambientes (dev/prod)
   - Destacar módulos principais (networking, eks, rds, etc.)

2. **Terraform Plan** (3-4 min)
   - Executar `terraform plan`
   - Explicar o que será criado/alterado
   - Mostrar recursos que serão provisionados

3. **Terraform Apply** (3-4 min)
   - Executar `terraform apply`
   - Mostrar progresso da criação de recursos
   - Destacar recursos principais sendo criados

4. **Verificação na AWS** (3-4 min)
   - Mostrar VPC criada
   - Mostrar subnets públicas e privadas
   - Mostrar cluster EKS criado
   - Mostrar instâncias RDS PostgreSQL
   - Mostrar cluster ElastiCache Redis
   - Mostrar tabela DynamoDB
   - Mostrar fila SQS
   - Mostrar repositórios ECR

5. **ArgoCD via Terraform** (2-3 min)
   - Explicar que ArgoCD é instalado via módulo Terraform
   - Mostrar helm_release no código
   - Explicar que isso é infraestrutura, não pipeline

6. **Segurança no Terraform** (2-3 min)
   - Mostrar IAM roles automáticas
   - Explicar security groups
   - Mostrar Checkov/Trivy configuration

## 🔐 Recursos que Serão Demonstrados

| Recurso | Descrição | Quantidade |
|--------|-----------|------------|
| **VPC** | Virtual Private Cloud | 1 |
| **Subnets** | 2 públicas + 2 privadas | 4 |
| **NAT Gateway** | Para subnets privadas | 1 |
| **EKS** | Cluster Kubernetes gerenciado | 1 |
| **Node Groups** | Grupos de nós EKS | Configurável |
| **RDS** | PostgreSQL (3 bancos) | 3 |
| **ElastiCache** | Redis cluster | 1 |
| **DynamoDB** | Tabela NoSQL | 1 |
| **SQS** | Fila principal + DLQ | 2 |
| **ECR** | Repositórios Docker | 5 |

## 🎓 Pontos-Chave para Explicação aos Professores

### 1. **Declarativo vs Imperativo**
- Terraform é **declarativo**: descreve o estado desejado
- Não precisa dizer "como criar", apenas "o que criar"
- Terraform calcula automaticamente as mudanças necessárias

### 2. **Idempotência**
- Executar `terraform apply` múltiplas vezes é seguro
- Se o recurso já existe com as configurações corretas, nada muda
- Garante consistência do estado

### 3. **State Management**
- Estado fica no S3 (backend remoto)
- Permite colaboração em equipe
- Evita conflitos de estado

### 4. **Modularidade**
- Cada recurso em um módulo separado
- Reutilização entre ambientes
- Manutenção simplificada

### 5. **Security as Code**
- Scanning automático com Checkov/Trivy
- Validação de security policies
- Detecção de misconfigurations

## 📝 Integração com as Outras Partes

### Parte do Amigo (CI/CD e Deploy):
- **CI dos serviços**: Build, testes, security scanning
- **Push no ECR**: Imagens Docker criadas e enviadas
- **GitOps**: Atualização de tags no repositório de manifests
- **ArgoCD**: Detecta mudanças e sincroniza automaticamente

### Integração:
1. **Terraform** cria ECR e cluster EKS
2. **CI/CD** builda imagens e push para ECR criado pelo Terraform
3. **GitOps** atualiza manifests
4. **ArgoCD** (instalado pelo Terraform) sincroniza no cluster

## 🚀 Benefícios da Abordagem

### Comparação com Fase 2 (Manual):
- **Fase 2**: Criação manual via console AWS
- **Fase 3**: Código versionado, replicável, auditável

### Vantagens:
- ✅ **Versionamento**: Infraestrutura no Git
- ✅ **Reprodutibilidade**: Mesmo resultado sempre
- ✅ **Auditabilidade**: Histórico completo de mudanças
- ✅ **Colaboração**: Trabalho em equipe
- ✅ **Automação**: Processos automatizados
- ✅ **Segurança**: Validações automáticas
- ✅ **Escalabilidade**: Múltiplos ambientes facilmente

## 🔍 Considerações Importantes

### Por que ArgoCD no Terraform?
- ArgoCD é **infraestrutura** (software que roda no cluster)
- Precisa estar instalado antes do GitOps funcionar
- Terraform garante que a instalação seja parte do setup inicial
- Separação clara: Terraform instala, GitOps usa

### Por que CI do Terraform não executa apply?
- **Segurança**: Mudanças de infra requerem aprovação manual
- **Controle**: Evita mudanças acidentais via commit
- **Boa prática**: Separação entre validação e aplicação
- **Flexibilidade**: Permite revisão antes de aplicar

### Por que Security Scanning no Terraform?
- **IaC Security**: Infraestrutura segura desde o design
- **Shift Left**: Detecta problemas antes do deploy
- **Compliance**: Valida policies automaticamente
- **Documentação**: Security como código

## 📊 Conclusão

Esta parte do projeto demonstra uma abordagem moderna de **Infrastructure as Code** que:

1. **Elimina configuração manual** da infraestrutura AWS
2. **Garante consistência** entre ambientes
3. **Permite colaboração** em equipe
4. **Integra-se perfeitamente** com CI/CD e GitOps
5. **Incorpora segurança** desde o design

A separação arquitetural entre IaC e pipelines é **fundamental** para manter responsabilidades claras, segurança e flexibilidade no processo de desenvolvimento e deploy.