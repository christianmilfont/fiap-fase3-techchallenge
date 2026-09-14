# Issues e Resoluções - Terraform IaC

Este documento documenta os problemas identificados no feedback e suas respectivas soluções implementadas.

---

## Issue #1: GitHub Actions OIDC Provider e Role

### 🚨 **Problema (CRÍTICO - BLOQUEIA PIPELINE)**

**Status**: ✅ **RESOLVIDO**  
**Prioridade**: 🔴 ALTA  
**Origem**: Feedback do responsável pela pipeline CI/CD

#### Descrição
Hoje a pipeline CI/CD precisa de `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` estáticos nos secrets do GitHub. Credencial de longa duração em CI é exatamente o que a Fase 3 visa eliminar.

#### Impacto
- **Segurança**: Credenciais estáticas em CI representam risco de segurança
- **Pipeline**: Não consegue seguir o padrão de GitOps sem isso
- **Compliance**: Viola princípios de segurança da Fase 3

#### Requisitos
1. Criar OIDC provider do GitHub Actions na AWS
2. Criar IAM role para GitHub Actions assumir via OIDC
3. Configurar trust policy restrita aos 5 repositórios de serviço:
   - `alansenairj/auth-service`
   - `alansenairj/evaluation-service`
   - `alansenairj/flag-service`
   - `alansenairj/targeting-service`
   - `alansenairj/analytics-service`
4. Dar permissões apenas de push nos 5 repositórios ECR

#### Solução Implementada
- ✅ Criado módulo `terraform/modules/github-oidc/`
- ✅ Implementado `aws_iam_openid_connect_provider` para GitHub (thumbprint: 6938fd4d98bab03faadb97b34396831e3780aea1)
- ✅ Implementado `aws_iam_role` com trust policy condicional restrita aos repositórios
- ✅ Policy de permissões ECR restrita aos repositórios específicos
- ✅ Integrado no `main.tf` principal
- ✅ Adicionado output `github_actions_role_arn`

#### Validação
- ✅ `terraform validate` - sucesso
- ✅ `terraform fmt` - sem alterações necessárias
- ✅ Sintaxe correta
- ✅ Trust policy com condições corretas
- ✅ Permissões ECR restritas aos ARNs específicos

#### Arquivos Criados/Modificados
- **Novos**: `terraform/modules/github-oidc/main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- **Modificados**: `terraform/main.tf`, `terraform/variables.tf`, `terraform/outputs.tf`

#### Referências
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- Feedback recebido do responsável pela pipeline

---

## Issue #2: External Secrets Operator IRSA Role

### 🚨 **Problema (CRÍTICO - BLOQUEIA DEPLOY)**

**Status**: 🔴 BLOQUEADOR  
**Prioridade**: 🔴 ALTA  
**Origem**: Feedback do responsável pela pipeline CI/CD

#### Descrição
O External Secrets Operator (ESO) precisa de uma role IRSA específica para ler secrets do AWS Secrets Manager. Sem isso, os pods não conseguem acessar as credenciais necessárias.

#### Impacto
- **Deploy**: Pods não conseguem acessar DATABASE_URL, MASTER_KEY, SERVICE_API_KEY
- **GitOps**: Quebra o ciclo de automação pois secrets precisam ser manuais
- **Segurança**: Credenciais ficam expostas em secrets do Kubernetes em vez de usar Secrets Manager

#### Requisitos
1. Criar IAM role específica para External Secrets Operator via IRSA
2. Configurar trust policy para o ServiceAccount `external-secrets:external-secrets`
3. Dar permissões de `secretsmanager:GetSecretValue` e `secretsmanager:DescribeSecret`
4. Restringir acesso aos secrets específicos do projeto

#### Solução Proposta
- Criar módulo `terraform/modules/external-secrets/`
- Implementar `aws_iam_role` com trust policy OIDC do EKS
- Policy de permissões Secrets Manager restrita

#### Referências
- [External Secrets Operator IRSA](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- Feedback recebido do responsável pela pipeline

---

## Issue #3: Secrets Manager com Secrets dos Serviços

### 🚨 **Problema (CRÍTICO - BLOQUEIA DEPLOY)**

**Status**: 🔴 BLOQUEADOR  
**Prioridade**: 🔴 ALTA  
**Origem**: Feedback do responsável pela pipeline CI/CD

#### Descrição
As senhas do RDS são geradas por `random_password` e só existem no state do Terraform. O script `gitops/scripts/criar-secrets.sh` atual faz `kubectl create secret` — passo manual, fora do Git, que é exatamente a dor #2 do enunciado.

#### Impacto
- **Manualidade**: Requer intervenção manual para criar secrets
- **GitOps**: Quebra o princípio de GitOps pois secrets não estão versionados
- **Segurança**: Senhas ficam expostas em secrets do Kubernetes

#### Requisitos
1. Criar secrets no AWS Secrets Manager para:
   - `togglemaster/auth`: DATABASE_URL, MASTER_KEY
   - `togglemaster/flag`: DATABASE_URL
   - `togglemaster/targeting`: DATABASE_URL
   - `togglemaster/evaluation`: REDIS_URL, SERVICE_API_KEY
2. Gerar MASTER_KEY e SERVICE_API_KEY com `random_password`
3. Usar os valores já disponíveis em `database_urls` do output

#### Solução Proposta
- Criar módulo `terraform/modules/secrets-manager/`
- Implementar `aws_secretsmanager_secret` para cada serviço
- Implementar `aws_secretsmanager_secret_version` com os valores
- Gerar chaves adicionais com `random_password`

#### Referências
- Feedback recebido do responsável pela pipeline
- Output `database_urls` já existe em `terraform/outputs.tf`

---

## Issue #4: Roles IRSA por Serviço (Refatorar EKS)

### 🟠 **Problema (FALHA EM RUNTIME)**

**Status**: 🟠 FUNCIONALIDADE QUEBRADA  
**Prioridade**: 🟠 MÉDIA  
**Origem**: Feedback do responsável pela pipeline CI/CD

#### Descrição
A role IRSA atual (`terraform/modules/eks/main.tf` linhas 78-130) tem dois problemas críticos:

**Problema (a)**: A policy é de S3, mas os serviços usam SQS e DynamoDB
- Linhas 112-125: Permissões S3 (`s3:GetObject`, `s3:PutObject`, `s3:ListBucket`)
- Realidade: `analytics-service` precisa ler SQS e gravar no DynamoDB
- Realidade: `evaluation-service` precisa publicar no SQS
- Nenhum dos dois toca em S3

**Problema (b)**: O trust condition aponta para namespace que não existe
- Linha ~94: `"system:serviceaccount:togglemaster:*"`
- Realidade: Manifestos usam um namespace por serviço
- Namespaces reais: `auth-service`, `analytics-service`, `evaluation-service`, etc.
- Namespace `togglemaster` não existe, role nunca seria assumida

#### Impacto
- **Runtime**: Apps sobem mas falham ao tentar acessar SQS/DynamoDB
- **Segurança**: Permissões erradas (S3 em vez de SQS/DynamoDB)
- **Deploy**: Role nunca seria assumida devido ao namespace errado

#### Requisitos
1. Criar roles IRSA específicas por serviço:
   - `analytics`: Permissões SQS (ReceiveMessage, DeleteMessage, GetQueueAttributes) + DynamoDB (PutItem)
   - `evaluation`: Permissões SQS (SendMessage)
   - `keda`: Permissões SQS (GetQueueAttributes)
2. Configurar trust conditions com namespaces corretos:
   - `system:serviceaccount:analytics-service:analytics-service-sa`
   - `system:serviceaccount:evaluation-service:evaluation-service-sa`
   - `system:serviceaccount:keda:keda-operator`
3. Usar ARNs específicos de recursos, nunca `"*"`

#### Solução Proposta
- Refatorar `terraform/modules/eks/main.tf`
- Remover role única `pod_role` genérica
- Criar roles específicas por serviço
- Usar ARNs específicos de SQS e DynamoDB

#### Referências
- Feedback recebido do responsável pela pipeline
- Políticas já existem na Fase 2: `manifests-eks/analytics-policy.json` e `manifests-eks/evaluation-policy.json`

---

## Issue #5: ECR Immutable Tags

### 🟡 **Problema (MELHORIA DE GITOPS)**

**Status**: 🟡 MELHORIA NECESSÁRIA  
**Prioridade**: 🟡 MÉDIA  
**Origem**: Feedback do responsável pela pipeline CI/CD

#### Descrição
A pipeline gera tag imutável por commit (`v1.0.0-a1b2c3d`) e o GitOps referencia essa tag exata. Se a tag puder ser sobrescrita, o Git deixa de descrever o que roda no cluster — quebra a auditabilidade que é o ponto do GitOps.

#### Impacto
- **GitOps**: Quebra a auditabilidade do GitOps
- **Deploy**: Tags podem ser sobrescritas, causando inconsistência
- **Segurança**: Não garante que o código no cluster é o que está no Git

#### Requisitos
1. Configurar `image_tag_mutability = "IMMUTABLE"` nos repositórios ECR
2. Manter `image_scanning_configuration { scan_on_push = true }`
3. Adicionar lifecycle policy (manter últimas ~20 imagens)
4. Nota: Com `IMMUTABLE` não dá para publicar `latest`

#### Solução Proposta
- Atualizar `terraform/modules/ecr/variables.tf`: mudar default para `IMMUTABLE`
- Atualizar `terraform/modules/ecr/main.tf`: garantir lifecycle policy adequada
- Verificar se há manifestos ainda apontando para `latest`

#### Referências
- Feedback recebido do responsável pela pipeline
- [ECR Image Tag Mutability](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html)

---

## Issue #6: Outputs Consolidados

### 🟡 **Problema (FALTA DE INTEGRAÇÃO)**

**Status**: 🟡 FALTA DE INTEGRAÇÃO  
**Prioridade**: 🟡 MÉDIA  
**Origem**: Feedback do responsável pela pipeline CI/CD

#### Descrição
Faltam outputs necessários para a integração com a pipeline CI/CD e GitOps. Sem esses outputs, a pipeline não consegue obter as informações necessárias para configurar os recursos.

#### Impacto
- **Pipeline**: Não consegue obter ARNs das roles criadas
- **GitOps**: Não consegue configurar External Secrets Operator
- **Deploy**: Requer intervenção manual para obter valores

#### Requisitos
Adicionar outputs:
- `github_actions_role_arn` (Item 1)
- `eso_role_arn` (Item 2)
- `app_secret_arns` - map(serviço => arn) (Item 3)
- `analytics_role_arn` (Item 4)
- `evaluation_role_arn` (Item 4)
- `keda_role_arn` (Item 4)

Outputs já existentes (manter):
- `ecr_repository_urls`
- `eks_cluster_name`
- `oidc_provider_arn`
- `sqs_queue_url`
- `dynamodb_table_name`

#### Solução Proposta
- Atualizar `terraform/outputs.tf`
- Adicionar novos outputs para roles e secrets
- Manter estrutura consistente

#### Referências
- Feedback recebido do responsável pela pipeline

---

## Issue #7: Backend S3 no Ambiente Dev

### 🔧 **Problema (INFRAESTRUTURA)**

**Status**: 🔧 CONFIGURAÇÃO INCORRETA  
**Prioridade**: 🔧 BAIXA  
**Origem**: Feedback do responsável pela pipeline CI/CD

#### Descrição
O arquivo `terraform/environments/dev/main.tf` usa `backend "local" {}` (linha 11). O PDF exige backend remoto em S3 ("o terraform.tfstate não pode ficar local"). A raiz e `prod` já estão corretos; só `dev` ficou de fora.

#### Impacto
- **Compliance**: Viola requisito do PDF
- **Colaboração**: State local dificulta trabalho em equipe
- **Backup**: State local não tem backup automático

#### Requisitos
1. Mudar backend de `local` para S3 em `environments/dev/main.tf`
2. Usar mesma configuração de backend que `environments/prod/`
3. Manter consistência entre ambientes

#### Solução Proposta
- Atualizar `terraform/environments/dev/main.tf`
- Mudar de `backend "local" {}` para `backend "s3" {}`
- Usar configuração similar ao ambiente prod

#### Referências
- Feedback recebido do responsável pela pipeline
- Requisito do PDF da Fase 3

---

## Issue #8: Estrutura de Módulos Duplicada

### 🔧 **Problema (ARQUITETURA)**

**Status**: 🔧 REFACTORING NECESSÁRIO  
**Prioridade**: 🔧 BAIXA  
**Origem**: Feedback do responsável pela pipeline CI/CD

#### Descrição
Módulos instanciados 3× — `terraform/`, `environments/dev/` e `environments/prod/` declaram os mesmos 8 módulos; mudança em um não propaga nos outros. Os scripts em `gitops/scripts/` leem `terraform -chdir=terraform` (a raiz), não os environments — não está claro qual é o root module oficial.

#### Impacto
- **Manutenção**: Mudanças precisam ser replicadas manualmente
- **Consistência**: Risco de inconsistência entre ambientes
- **Confusão**: Não está claro qual é o root module oficial

#### Requisitos
1. Decidir qual é o root module oficial
2. Eliminar duplicação de módulos
3. Garantir que scripts leem do root module correto

#### Solução Proposta
- Decidir root module oficial (provavelmente `terraform/` na raiz)
- Remover duplicação de módulos em environments
- Configurar environments para usar módulos da raiz
- Atualizar scripts se necessário

#### Referências
- Feedback recebido do responsável pela pipeline
- Scripts em `gitops/scripts/` leem `terraform -chdir=terraform`

---

## Resumo de Prioridades

| # | Issue | Prioridade | Status |
|---|-------|------------|--------|
| 1 | GitHub Actions OIDC Provider e Role | 🔴 ALTA | 🔴 BLOQUEADOR |
| 3 | Secrets Manager com secrets dos serviços | 🔴 ALTA | 🔴 BLOQUEADOR |
| 2 | External Secrets Operator IRSA Role | 🔴 ALTA | 🔴 BLOQUEADOR |
| 4 | Roles IRSA por serviço (refatorar EKS) | 🟠 MÉDIA | 🟠 FUNCIONALIDADE QUEBRADA |
| 5 | ECR Immutable Tags | 🟡 MÉDIA | 🟡 MELHORIA NECESSÁRIA |
| 6 | Outputs consolidados | 🟡 MÉDIA | 🟡 FALTA DE INTEGRAÇÃO |
| 7 | Backend S3 no ambiente dev | 🔧 BAIXA | 🔧 CONFIGURAÇÃO INCORRETA |
| 8 | Estrutura de módulos duplicada | 🔧 BAIXA | 🔧 REFACTORING NECESSÁRIO |

---

## Estratégia de Implementação

1. **Fase 1 - Bloqueadores Críticos**: Issues #1, #3, #2 (nessa ordem)
2. **Fase 2 - Funcionalidade**: Issue #4
3. **Fase 3 - Melhorias**: Issues #5, #6
4. **Fase 4 - Infraestrutura**: Issues #7, #8

Cada issue será:
1. Documentada (este arquivo)
2. Implementada com código
3. Validada com testes
4. Commitada com mensagem descritiva
5. Marcada como resolvida neste arquivo