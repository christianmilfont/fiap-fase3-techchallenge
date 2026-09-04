# Changelog

All notable changes to the ToggleMaster project will be documented in this file.

## [Fase 3] - 2026-09-04

### 🚀 Infrastructure as Code (Terraform)

#### Nova Estrutura
- **Modularização completa**: 8 módulos reutilizáveis (networking, eks, rds, elasticache, dynamodb, sqs, ecr, argocd)
- **Backend remoto S3**: Estado do Terraform armazenado em bucket S3 com versionamento e criptografia
- **Lock nativo S3**: `use_lockfile = true` dispensa tabela DynamoDB de lock (Terraform >= 1.11)
- **Bootstrap separado**: Projeto `bootstrap/` cria bucket de estado antes da infra principal

#### Módulos Implementados
- **networking**: VPC, 2 subnets públicas, 2 subnets privadas, IGW, NAT Gateway, route tables
- **eks**: Cluster EKS + node groups com IAM roles automáticas
- **rds**: 3 instâncias PostgreSQL (auth, flag, targeting) com senhas geradas automaticamente
- **elasticache**: Cluster Redis para cache do evaluation-service
- **dynamodb**: Tabela ToggleMasterAnalytics para analytics
- **sqs**: Fila principal + Dead Letter Queue (DLQ)
- **ecr**: 5 repositórios para as imagens dos serviços
- **argocd**: Helm chart do ArgoCD instalado via provider

#### IAM Roles Automáticas
- **Cluster Role**: AmazonEKSClusterPolicy + AmazonEKSVPCResourceController
- **Node Groups Role**: AmazonEKSWorkerNodePolicy + AmazonEKS_CNI_Policy + AmazonEC2ContainerRegistryReadOnly
- **OIDC Provider**: Habilitado para IRSA (IAM Roles for Service Accounts)
- **Removida dependência LabRole**: Adaptação específica do AWS Academy removida para funcionar em contas pessoais

#### Segurança
- **Arquivos locais**: `terraform.tfvars` e `backend.hcl` criados localmente (não versionados)
- **Zero dados sensíveis no Git**: Credenciais e configurações específicas ficam fora do repositório
- **.gitignore configurado**: Bloqueia commit de arquivos .tfvars e backend.hcl
- **Senhas geradas**: `random_password` para RDS, armazenadas apenas no estado (criptografado)

### 🔒 DevSecOps (CI/CD)

#### GitHub Actions Workflows
- **Workflow reutilizável**: `_service-ci.yml` base para todos os serviços
- **5 workflows específicos**: `ci-auth-service.yml`, `ci-flag-service.yml`, `ci-targeting-service.yml`, `ci-evaluation-service.yml`, `ci-analytics-service.yml`
- **Filtro de path**: Cada workflow só dispara quando o serviço correspondente muda

#### Pipeline de Segurança
- **Build & Test**: Go build/test, Python uv sync/pytest
- **Lint**: Go vet/golangci-lint, Python flake8
- **Security Scan**: 
  - **SCA**: Trivy fs (dependências + secrets)
  - **SAST**: Gosec (Go), Bandit (Python)
  - **Image Scan**: Trivy image após build
- **Bloqueio automático**: Vulnerabilidades CRITICAL bloqueiam o pipeline

#### Docker & ECR
- **Build automatizado**: Multi-stage builds otimizados
- **Tags semânticas**: `v1.0.0-<commit-hash>` + `latest`
- **Scan de imagem**: Trivy image scan antes do push
- **Push condicional**: Apenas em push na main (PR valida sem publicar)

### 🚢 GitOps (ArgoCD)

#### Estrutura GitOps
- **App-of-apps**: Aplicação raiz aponta para `gitops/argocd/`
- **5 Applications**: Uma por serviço (auth, flag, targeting, evaluation, analytics)
- **Sync automático**: `selfHeal: true` + `prune: true`
- **Kustomize**: Gestão de imagens via overlays por ambiente

#### Integração CI/CD
- **Job update-gitops**: Commit automático da tag da imagem no kustomization.yaml
- **Serialização**: `concurrency: gitops-write` evita conflitos
- **Rebase automático**: Tentativas automáticas em caso de conflito

#### Segurança
- **Secrets fora do Git**: DATABASE_URL, MASTER_KEY criados via script local
- **Placeholders resolvidos**: Script substitui `<ACCOUNT_ID>`, `<ELASTICACHE-ENDPOINT>` etc.
- **Validação**: CI valida manifests YAML com kubeconform

### 📦 Deployments

#### Kubernetes Manifests
- **Namespaces separados**: Um namespace por serviço
- **ConfigMaps**: Configurações externalizadas
- **Services**: ClusterIP para comunicação interna
- **Ingress**: Exposição via ALB (quando aplicável)
- **HPA**: Horizontal Pod Autoscaler no evaluation-service
- **KEDA**: Event-based autoscaling no analytics-service

#### Imagens Docker
- **Base alpine**: Imagens leves e seguras
- **Multi-stage**: Separação de build e runtime
- **Non-root user**: Execução como usuário não-root
- **Health checks**: Liveness e readiness probes

### 📝 Documentação

#### Terraform
- **README.md terraform/**: Guia completo de execução
- **README.md módulos**: Documentação de cada módulo
- **Exemplos**: `terraform.tfvars.example`, `backend.hcl.example`

#### GitOps
- **README.md gitops/**: Estrutura e fluxo GitOps
- **Scripts**: `preencher-placeholders.sh`, `criar-secrets.sh`

#### Geral
- **README.md principal**: Visão geral da Fase 3
- **plano-de-execucao.md**: Cronograma e objetivos

### 🔧 Ferramentas e Tecnologias

#### Nova Stack
- **Terraform 1.15.8**: Infrastructure as Code
- **GitHub Actions**: CI/CD automatizado
- **ArgoCD 7.7.11**: GitOps deployment
- **Kustomize**: Gestão de manifests
- **Trivy**: Security scanning
- **Kubernetes 1.30**: Orquestração

#### Serviços AWS
- **EKS**: Kubernetes gerenciado
- **RDS PostgreSQL**: Bancos relacionais
- **ElastiCache Redis**: Cache distribuído
- **DynamoDB**: NoSQL serverless
- **SQS**: Mensageria
- **ECR**: Registry de containers
- **S3**: Storage (estado Terraform)

### 🎯 Melhorias Implementadas (Feedback)

#### Segurança (Checkov + IRSA)
- ✅ **Checkov integration**: Configuração `.checkov.yaml` com 40+ security checks
- ✅ **IRSA implementado**: IAM Roles for Service Accounts para pods
- ✅ **Trust conditions**: Condições de trust restritas nas IAM roles
- ✅ **Least privilege**: Polítias IAM mais restritivas e específicas
- ✅ **Account isolation**: Condições `aws:SourceAccount` em assume role policies

#### Arquitetura (Ambientes)
- ✅ **Estrutura separada**: `environments/dev/` e `environments/prod/`
- ✅ **Módulos reutilizáveis**: Mesmos módulos usados em ambos ambientes
- ✅ **Variáveis específicas**: `dev.tfvars` e `prod.tfvars` por ambiente
- ✅ **Backend separado**: Estados S3 diferentes por ambiente
- ✅ **Documentação**: README.md em environments/ com guia de uso

### 🎯 Melhorias Planejadas

#### Observabilidade
- [ ] Metrics e dashboards
- [ ] Centralized logging
- [ ] Distributed tracing
- [ ] Alerting

#### Compliance
- [ ] Implementar compliance checks adicionais
- [ ] Adicionar monitoring de custos
- [ ] Implementar políticas de retenção de dados

#### Observabilidade
- [ ] Metrics e dashboards
- [ ] Centralized logging
- [ ] Distributed tracing
- [ ] Alerting

---

## [Fase 2] - 2026-08-07

### 🚀 Kubernetes Deployment
- Cluster EKS criado via eksctl
- 5 microsserviços em containers
- PostgreSQL, Redis, DynamoDB provisionados
- Manifests Kubernetes criados manualmente

### 📦 Serviços Implementados
- auth-service: Autenticação e autorização
- flag-service: Gestão de feature flags
- targeting-service: Segmentação de usuários
- evaluation-service: Avaliação de flags
- analytics-service: Coleta de métricas

---

## [Fase 1] - 2026-07-13

### 🎯 Projeto Inicial
- Arquitetura de microsserviços definida
- Stack tecnológica selecionada (Go, Python, PostgreSQL, Redis)
- Modelo de dados desenhado
