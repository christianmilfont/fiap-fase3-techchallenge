# ToggleMaster — Fase 3

Feature flags em 5 microsserviços (`auth`, `flag`, `targeting`, `evaluation`, `analytics`),
com infraestrutura, integração contínua e deploy inteiramente automatizados.

Este documento explica o que foi criado, **por quê** e como cada peça funciona.

| Entrega | Pasta |
| --- | --- |
| Infraestrutura como código | `terraform/` |
| CI + DevSecOps | `.github/workflows/` |
| CD com GitOps | `gitops/` |
| Documentação de tarefas | `terraform/tasks-terraform.md` |

O fio condutor: na Fase 2 você clicava no console e rodava `kubectl apply` na mão. Agora **nada** é criado à mão — nem a infra (Terraform), nem a imagem (CI), nem o que roda no cluster (ArgoCD). **Segurança e validação** são aplicadas em cada etapa: Checkov valida a infra, Trivy escaneia dependências e imagens, e OIDC elimina credenciais estáticas.

---

## 1. Terraform — `terraform/`

### Por quê

O enunciado pede a substituição da criação manual. Terraform descreve o estado desejado da AWS; o que existe na conta passa a ser consequência do que está no Git, e não de cliques.

### Como está organizado

```
terraform/
├── main.tf          # compõe os módulos e liga um no outro (uso direto)
├── variables.tf     # tudo que é parametrizável (região, CIDRs, tamanhos...)
├── outputs.tf       # o que sai do apply (endpoints, senhas, comandos prontos)
├── providers.tf     # aws + random + tls (apenas para OIDC)
├── backend.tf       # estado remoto no S3
├── bootstrap/       # cria o bucket do estado (o ovo antes da galinha)
├── environments/   # ambientes separados (dev, prod)
│   ├── dev/         # configurações de desenvolvimento
│   └── prod/        # configurações de produção
├── .checkov.yaml    # configuração de security scanning
├── tasks-terraform.md # documentação completa de tarefas implementadas
└── modules/
    ├── networking/  ├── eks/   ├── rds/    ├── elasticache/
    ├── dynamodb/    ├── sqs/   ├── ecr/    ├── github-oidc/
    ├── external-secrets/ └── secrets-manager/
```

**Por que módulos:** cada recurso vira uma caixa com entrada (variables) e saída (outputs). O `main.tf` só liga as caixas — por exemplo, o `vpc_id` que sai do `networking` entra no `eks` e no `rds`. Isso é o que garante a ordem de criação: o Terraform monta o grafo de dependências sozinho a partir dessas referências, sem você dizer "cria a VPC primeiro".

**Nota sobre ArgoCD:** O módulo ArgoCD foi removido do Terraform para separar responsabilidades. O ArgoCD agora é instalado separadamente via `kubectl` ou Helm no cluster EKS (ver seção "ArgoCD - Instalação Separada").

### O que cada módulo faz

- **networking** — VPC, subnets públicas e privadas em 2 AZs, Internet Gateway, NAT Gateway, route tables e associações.
  As subnets recebem as tags `kubernetes.io/role/elb` (pública) e `internal-elb` (privada): é assim que o AWS Load Balancer Controller descobre onde criar o ALB do Ingress. Sem elas o Ingress fica pendurado.
  Os bancos ficam **só** em subnet privada; o NAT existe para os pods conseguirem puxar imagem do ECR sem estarem expostos.

- **eks** — control plane + node group (`t3.medium`, desired 2, min 1, max 4) nas subnets privadas.
  *IAM roles automáticas:* O módulo cria as IAM roles necessárias (cluster, nodes) com trust conditions restritas.
  *IRSA específicas por serviço:* Roles IAM dedicadas para analytics-service, evaluation-service, e keda-operator com permissões corretas (SQS/DynamoDB em vez de S3).
  *Trust conditions:* Namespaces corretos (analytics-service, evaluation-service, keda) em vez de namespace genérico.
  *Security:* Condições `aws:SourceAccount` em assume role policies para evitar cross-account access.
  *OIDC Provider:* Habilitado automaticamente para suporte a IRSA (usa `tls_certificate` data source apenas para thumbprint).

- **rds** — 3 PostgreSQL (auth, flag, targeting), um por serviço, em subnet privada, com security group que só aceita conexão vinda do security group do cluster.
  As senhas são geradas por `random_password` — não existe senha digitada no código.

- **elasticache** — Redis, usado pelo evaluation-service como cache de avaliação de flags.

- **dynamodb** — tabela `ToggleMasterAnalytics`, on-demand.

- **sqs** — fila que desacopla o evaluation (produtor de eventos) do analytics (consumidor).

- **ecr** — os 5 repositórios de imagem, com `scan_on_push` ligado e tags imutáveis para GitOps compliance.

- **github-oidc** — OIDC provider do GitHub Actions + IAM role para autenticação federada na pipeline CI/CD.
  *Elimina credenciais estáticas:* GitHub Actions usa tokens temporários via OIDC em vez de AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY.
  *Trust policy restrita:* Apenas os 5 repositórios de serviço (alansenairj/*) podem assumir a role.
  *Permissões ECR:* Push restrito aos repositórios específicos do projeto.

- **external-secrets** — IAM role IRSA para External Secrets Operator.
  *Secrets Management:* Permite que o ESO leia secrets do AWS Secrets Manager via IRSA.
  *Service Account:* Trust policy configurada para external-secrets:external-secrets.
  *Permissões:* GetSecretValue e DescribeSecret nos secrets específicos do projeto.

- **secrets-manager** — Secrets no AWS Secrets Manager para as credenciais dos serviços.
  *Centralização:* DATABASE_URL, MASTER_KEY, SERVICE_API_KEY armazenados de forma segura.
  *Geração automática:* MASTER_KEY e SERVICE_API_KEY gerados com random_password.
  *Integração:* Usa outputs do RDS e ElastiCache para construir as connection strings.

### O estado remoto

```hcl
# backend.tf
backend "s3" {
  key          = "togglemaster/infra.tfstate"
  encrypt      = true
  use_lockfile = true
}
```

**Por quê:** o `.tfstate` é o mapa entre o código e o que existe de verdade na AWS. Local, ele se perde e some com o histórico; e se duas pessoas (ou o CI) rodarem ao mesmo tempo, os dois apply se atropelam.

`use_lockfile = true` é o lock nativo do S3 (aula 2) — cria um arquivo `.tflock` ao lado do estado. É o que substitui a tabela DynamoDB de lock que se usava antes.

**O `bootstrap/`:** o bucket que guarda o estado não pode ser criado pelo Terraform que já usa esse bucket. Então `bootstrap/` é um projetinho separado, com estado local, que roda uma vez só e cria o bucket (versionado e criptografado). Depois disso, o projeto principal aponta para ele.

---

## 🎯 Melhorias Implementadas (Feedback)

### 🔒 Segurança Aprimorada
- **Checkov integration**: Configuração `.checkov.yaml` com 35+ security checks automatizados (IAM, EKS, RDS, S3, VPC)
- **GitHub Actions OIDC**: Autenticação federada elimina credenciais estáticas no CI/CD
- **IRSA específicas por serviço**: Roles dedicadas com permissões corretas (SQS/DynamoDB)
- **Trust conditions**: Condições restritas em assume role policies
- **Least privilege**: Políticas IAM específicas por recurso (sem wildcards "*")
- **Account isolation**: Condições `aws:SourceAccount` para evitar cross-account access
- **Secrets Manager**: Credenciais centralizadas no AWS Secrets Manager via External Secrets Operator
- **ECR Immutable Tags**: Tags imutáveis garantem auditabilidade GitOps
- **Remoção de checks inaplicáveis**: `CKV_AWS_276` (IAM user access keys) e `CKV_AWS_140` (MFA for IAM users) removidos (uso de roles, não usuários)

### 🏗️ Arquitetura
- **Separação de responsabilidades**: ArgoCD removido do Terraform, instalado separadamente
- **Single Responsibility**: Terraform focado em infraestrutura cloud, ArgoCD em deployment
- **Flexibilidade**: ArgoCD pode ser atualizado/gerenciado independentemente
- **Menos complexidade**: Código Terraform mais limpo e focado
- **OIDC Provider**: Habilitado automaticamente no EKS (usa `tls_certificate` apenas para thumbprint)

### 🏗️ Estrutura de Ambientes
- **Ambientes separados**: `environments/dev/` e `environments/prod/` com configurações específicas
- **Módulos reutilizáveis**: Mesmos módulos usados em ambos ambientes (DRY principle)
- **Backends S3**: Estados remotos em ambos ambientes (dev e prod) com lock nativo
- **Variáveis específicas**: `dev.tfvars` e `prod.tfvars` com configurações otimizadas
- **Documentação completa**: README.md em `environments/` com guia de uso
- **Novos módulos integrados**: github-oidc, external-secrets, secrets-manager em todos ambientes

### 💡 Benefícios
- **Isolamento completo**: Dev e prod completamente separados
- **Escalabilidade**: Fácil adicionar novos ambientes (staging, uat)
- **Segurança**: Zero dados sensíveis no Git, arquivos .tfvars locais
- **Manutenibilidade**: Mudanças centralizadas nos módulos
- **Security scanning**: Verificação automatizada de vulnerabilidades

## 2. CI + DevSecOps — `.github/workflows/`

### Por quê

Cada commit precisa provar que compila, que passa no lint e que não introduz vulnerabilidade — antes de virar imagem publicada.

### A estrutura: 1 reutilizável + 5 chamadores

São 5 serviços em 2 stacks diferentes. Copiar o mesmo pipeline 5 vezes significaria corrigir bug em 5 lugares. Então existe **um** `_service-ci.yml` com toda a lógica, e cada `ci-<serviço>.yml` só o chama dizendo quem ele é:

```yaml
jobs:
  ci:
    uses: ./.github/workflows/_service-ci.yml
    with:
      service: auth-service
      language: go                      # go | python
      ecr_repository: togglemaster/auth-service
```

O input `language` liga/desliga os passos: `if: inputs.language == 'go'`. Um único arquivo atende Go e Python sem duplicação.

**Filtro de path:** o workflow do auth só dispara quando `auth-service/**` muda. Sem isso, mudar um README rodaria 5 pipelines completos.

### Os estágios

```
build-test ─┐
lint ───────┼─→ docker ─→ update-gitops
security ───┘
```

Os três primeiros rodam **em paralelo** (independentes entre si); o `docker` tem `needs: [build-test, lint, security-scan]`, então só começa quando os três passam. É exatamente esse `needs` que implementa a regra de bloqueio do enunciado: **uma CRITICAL em qualquer estágio impede o build e o push da imagem** — não tem como uma vulnerabilidade crítica chegar ao ECR.

**1. Build & Unit Test**
- Go: `go build ./...` e `go test ./...`
- Python: `uv sync --frozen` (respeita o `uv.lock`, então o CI instala exatamente o que você instalou), `compileall` e `pytest`

Nenhum dos 5 serviços tem teste unitário hoje. O estágio reporta isso ("no test files") em vez de eu inventar teste para fingir cobertura.

**2. Linter**
- Go: `go vet` + `golangci-lint`
- Python: `flake8` em dois passos — erro de sintaxe/nome indefinido (`E9,F63,F7,F82`) **bloqueia**; estilo/linha longa é só relatório. Estilo quebrar deploy é atrito sem ganho de segurança.

**3. Security Scan**
- **SCA** (dependências): `trivy fs --scanners vuln,secret` — pega CVE em biblioteca de terceiros e credencial esquecida no código.
- **SAST** (seu código): `gosec` no Go, `bandit` no Python — pega padrão inseguro escrito por você (SQL concatenado, bind em `0.0.0.0`, etc.).

São coisas diferentes: SCA olha o que você importou, SAST olha o que você escreveu. O enunciado pede os dois.

Todo scan roda **duas vezes**: uma com `severity: CRITICAL` + `exit-code: 1` (falha o job) e outra com `HIGH,MEDIUM` só informativa. Assim o pipeline bloqueia no que é crítico mas você continua enxergando o resto.

**Duas exceções, ambas documentadas no README:**
- `gosec -exclude=G704`: a regra de SSRF marca as chamadas do evaluation ao flag/targeting-service. As URLs base vêm de ConfigMap, não de input do usuário — não é SSRF. As outras regras HIGH continuam bloqueando.
- `.trivyignore`: endpoint público do EKS e egress `0.0.0.0/0` no scan de IaC. Cada exceção tem a justificativa escrita no arquivo.

**4. Docker Build & Push**

Build da imagem → `trivy image` (scan do que foi construído, incluindo o sistema operacional da imagem base, que o `trivy fs` não vê) → login no ECR → push.

```
<account>.dkr.ecr.us-east-1.amazonaws.com/togglemaster/auth-service:v1.0.0-a1b2c3d
```

A tag carrega o commit hash: dado um pod rodando no cluster, você sabe exatamente qual commit gerou aquele binário. `latest` também é publicado, por conveniência.

O push só acontece em **push na main**. Em Pull Request o pipeline vai até o scan da imagem e para — PR valida, mas não publica.

---

## 3. CD com GitOps — `gitops/`

### Por que abandonar o `kubectl apply` no CI

No modelo antigo (push direto), o CI tem credencial de admin do cluster, e o que está rodando lá dentro é resultado de uma sequência de comandos que já passou — não dá para olhar um arquivo e saber o estado atual. Se alguém mexer no cluster na mão, ninguém percebe.

### ArgoCD - Instalação Separada

O ArgoCD **não** é mais instalado pelo Terraform. Esta decisão foi tomada para separar responsabilidades:
- **Terraform**: Focado apenas em infraestrutura cloud (AWS)
- **ArgoCD**: Gerenciado separadamente via `kubectl` ou Helm no cluster

**Benefícios:**
- Single Responsibility: Cada ferramenta faz o que faz melhor
- Flexibilidade: ArgoCD pode ser atualizado/gerenciado independentemente
- Segurança: Terraform não precisa de acesso ao cluster Kubernetes
- Manutenibilidade: Menos complexidade no código Terraform

### Secrets fora do Git

Os `secret.yaml` da Fase 2 não foram para `gitops/`: `DATABASE_URL` e `MASTER_KEY` são credenciais, e tudo em `gitops/` é público no repositório.

Com a nova implementação, os secrets são gerenciados via **External Secrets Operator** e **AWS Secrets Manager**:

1. **Terraform cria secrets** no AWS Secrets Manager (togglemaster/auth, togglemaster/flag, etc.)
2. **External Secrets Operator** lê esses secrets via IRSA
3. **Secrets do Kubernetes** são criados automaticamente no namespace correto
4. **Zero manual**: Credenciais geradas automaticamente, nenhum comando manual necessário

Benefícios:
- 100% GitOps: Nada precisa ser criado manualmente no cluster
- Segurança: Credenciais ficam no AWS Secrets Manager, não no Git
- Auditoria: Mudanças em secrets são rastreáveis via Terraform state
- Escalabilidade: Fácil adicionar novos secrets conforme necessário
- IRSA integration: External Secrets Operator usa IRSA para autenticação segura


## Ordem de execução

```bash
# 1. bucket do estado (uma vez só)
cd terraform/bootstrap
terraform init
terraform apply -var="project_name=togglemaster-prod"
ADICIONAR ARQUIVO BACKEND.HCL COM AS KEYS REFERENTES AOS OUTPUTS DO BUCKET
EXEMPLO:
bucket = "togglemaster-prod-XXXXX"
key = "togglemaster-prod/infra.tfstate"
region = "us-east-1"

# 2. security scanning (Checkov)
cd .. && checkov -d . --config-file .checkov.yaml

# 3. infra (Terraform)
cd terraform/environments/prod ou dev
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan

# 4. acesso ao cluster
terraform output -raw kubeconfig_command | bash

# 5. instalação do ArgoCD (separado do Terraform)

# 6. acesso à UI do ArgoCD

# 7. entregar o cluster ao ArgoCD

```

**Nota sobre Security Scanning:**
- O Checkov roda **antes** do `terraform apply` para validar que a infraestrutura atende aos requisitos de segurança
- Se houver violações CRITICAL, o scan falha e você deve corrigir antes de prosseguir
- A configuração `.checkov.yaml` está otimizada para o projeto (checks inaplicáveis para IAM users removidos)
- O IRSA (IAM Roles for Service Accounts) é configurado automaticamente pelo módulo EKS

**Nota sobre Secrets:**
- Os secrets são gerenciados automaticamente via External Secrets Operator e AWS Secrets Manager
- Nenhum script manual é necessário para criar secrets
- O Terraform gera as credenciais automaticamente via `random_password`

No GitHub, antes de o CI rodar:
- Configurar OIDC provider no GitHub Settings (se ainda não existir)
- Settings → Actions → General → **Workflow permissions: Read and write** (sem isso o `update-gitops` não commita)
- **Importante:** Com GitHub Actions OIDC, não é mais necessário configurar `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` no GitHub Secrets. A autenticação é federada via OIDC.

---

## Como o ciclo fica no fim

1. Você faz merge de uma mudança no `auth-service`.
2. O CI compila, linta, escaneia dependências e código.
3. Constrói a imagem, escaneia a imagem, publica no ECR como `v1.0.0-<sha>`.
4. Commita essa tag em `gitops/apps/auth-service/kustomization.yaml`.
5. O ArgoCD percebe o commit e aplica o Deployment novo no EKS.
6. A UI mostra o serviço `Synced`/`Healthy`.

Nenhum passo tem alguém digitando comando. Rollback é `git revert` do commit do passo 4.

**Segurança throughout:**
- OIDC Provider habilitado automaticamente no EKS para suporte a IRSA
- Roles IRSA específicas por serviço (analytics, evaluation, keda) com permissões mínimas
- Secrets gerenciados via External Secrets Operator + AWS Secrets Manager
- Checkov valida segurança da infraestrutura antes do deploy
- GitHub Actions usa autenticação federada (OIDC) em vez de credenciais estáticas
- TLS provider usado apenas para thumbprint do OIDC (não para certificados/keys manuais)
