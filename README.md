# ToggleMaster — Fase 3

Feature flags em 5 microsserviços (`auth`, `flag`, `targeting`, `evaluation`, `analytics`),
com infraestrutura, integração contínua e deploy inteiramente automatizados.

Este documento explica o que foi criado, **por quê** e como cada peça funciona.

| Entrega | Pasta |
| --- | --- |
| Infraestrutura como código | `terraform/` |
| CI + DevSecOps | `.github/workflows/` |
| CD com GitOps | `gitops/` + `terraform/modules/argocd` |

O fio condutor: na Fase 2 você clicava no console e rodava `kubectl apply` na mão. Agora **nada** é criado à mão — nem a infra (Terraform), nem a imagem (CI), nem o que roda no cluster (ArgoCD).

---

## 1. Terraform — `terraform/`

### Por quê

O enunciado pede a substituição da criação manual. Terraform descreve o estado desejado da AWS; o que existe na conta passa a ser consequência do que está no Git, e não de cliques.

### Como está organizado

```
terraform/
├── main.tf          # compõe os módulos e liga um no outro
├── variables.tf     # tudo que é parametrizável (região, CIDRs, tamanhos...)
├── outputs.tf       # o que sai do apply (endpoints, senhas, comandos prontos)
├── providers.tf     # aws + helm
├── backend.tf       # estado remoto no S3
├── bootstrap/       # cria o bucket do estado (o ovo antes da galinha)
└── modules/
    ├── networking/  ├── eks/   ├── rds/    ├── elasticache/
    ├── dynamodb/    ├── sqs/   ├── ecr/    └── argocd/
```

**Por que módulos:** cada recurso vira uma caixa com entrada (variables) e saída (outputs). O `main.tf` só liga as caixas — por exemplo, o `vpc_id` que sai do `networking` entra no `eks` e no `rds`. Isso é o que garante a ordem de criação: o Terraform monta o grafo de dependências sozinho a partir dessas referências, sem você dizer "cria a VPC primeiro".

### O que cada módulo faz

- **networking** — VPC, subnets públicas e privadas em 2 AZs, Internet Gateway, NAT Gateway, route tables e associações.
  As subnets recebem as tags `kubernetes.io/role/elb` (pública) e `internal-elb` (privada): é assim que o AWS Load Balancer Controller descobre onde criar o ALB do Ingress. Sem elas o Ingress fica pendurado.
  Os bancos ficam **só** em subnet privada; o NAT existe para os pods conseguirem puxar imagem do ECR sem estarem expostos.

- **eks** — control plane + node group (`t3.medium`, desired 2, min 1, max 4) nas subnets privadas.
  *Detalhe do Academy:* a conta não deixa criar IAM role. Então o módulo faz `data "aws_iam_role" { name = "LabRole" }` — ele **lê** a role que já existe e associa ao cluster e aos nodes, em vez de tentar criar.

- **rds** — 3 PostgreSQL (auth, flag, targeting), um por serviço, em subnet privada, com security group que só aceita conexão vinda do security group do cluster.
  As senhas são geradas por `random_password` — não existe senha digitada no código.

- **elasticache** — Redis, usado pelo evaluation-service como cache de avaliação de flags.

- **dynamodb** — tabela `ToggleMasterAnalytics`, on-demand.

- **sqs** — fila que desacopla o evaluation (produtor de eventos) do analytics (consumidor).

- **ecr** — os 5 repositórios de imagem, com `scan_on_push` ligado.

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
- `.trivyignore`: endpoint público do EKS e egress `0.0.0.0/0` no scan de IaC. No Academy não há VPN/bastion para o `kubectl` nem VPC endpoints para o ECR; cada exceção tem a justificativa escrita no arquivo.

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

No GitOps a direção se inverte: o Git é a verdade, e um agente **dentro** do cluster puxa dele.

```
push na main → CI → ECR → commit da tag em gitops/ → ArgoCD vê → cluster
```

Ganhos concretos: o CI não precisa de credencial do cluster; `git log` vira o histórico de deploy; rollback é `git revert`; e desvio manual é corrigido sozinho.

### A pasta

```
gitops/
├── apps/<serviço>/     # namespace, configmap, deployment, service, ingress
│                       # (+ hpa no evaluation, scaledobject/KEDA no analytics)
├── argocd/
│   ├── project.yaml           # AppProject togglemaster
│   ├── applications/          # 1 Application por serviço
│   └── root-app.yaml          # app-of-apps
└── scripts/                   # placeholders e secrets
```

### Kustomize e o truque da tag

O Deployment referencia só o **nome lógico** da imagem, e o registry/tag ficam no `kustomization.yaml`:

```yaml
# deployment.yaml
image: togglemaster/auth-service

# kustomization.yaml
images:
  - name: togglemaster/auth-service
    newName: <account>.dkr.ecr.us-east-1.amazonaws.com/togglemaster/auth-service
    newTag: v1.0.0-a1b2c3d
```

Na hora do `kustomize build` isso vira a imagem completa. **Por que assim:** o commit automático do CI mexe em uma linha só, sempre na mesma. Se cinco pipelines terminarem juntos, o rebase resolve sem conflito — o que não aconteceria com `sed` no meio do `deployment.yaml`.

### O job `update-gitops`

Novo último estágio do CI, depois do `docker` e só em push na main:

```yaml
kustomize edit set image "togglemaster/auth-service=$REGISTRY/$REPO:$TAG"
git commit -m "chore(gitops): auth-service -> $TAG"
git push origin HEAD:main
```

Os 5 pipelines escrevem na mesma branch, então:
- `concurrency: gitops-write` — serializa: um job de cada vez;
- se ainda assim o push for rejeitado, faz `git pull --rebase` e tenta de novo (até 5x).

As permissões ficam por job (`contents: write` só nesse) em vez de no workflow inteiro — princípio do menor privilégio.

### ArgoCD instalado pelo Terraform

`terraform/modules/argocd` faz `helm_release` do chart oficial. O provider Helm autentica assim:

```hcl
exec {
  command = "aws"
  args    = ["eks", "get-token", "--cluster-name", ...]
}
```

Ou seja, o token é pedido na hora do apply e **não é gravado no estado** — se fosse um token literal, ele viraria texto no `.tfstate`.

### App-of-apps

O Terraform cria **uma só** Application, a raiz, que aponta para `gitops/argocd/`. Essa pasta contém as 5 Applications, então o ArgoCD as descobre e cria sozinho.

**Por quê:** adicionar um sexto microsserviço amanhã não exige `terraform apply` nem `kubectl` — basta commitar o YAML na pasta. A fronteira entre "infra" e "aplicação" fica limpa.

### Sync automático

```yaml
syncPolicy:
  automated:
    prune: true      # o que sai do Git sai do cluster
    selfHeal: true   # alteração feita na mão é revertida
```

`selfHeal` é o que garante que o cluster nunca diverge do Git — se alguém editar um Deployment com `kubectl edit`, o ArgoCD desfaz em segundos.

Uma exceção necessária:

```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers: [/spec/replicas]
```

Sem isso, o HPA (evaluation) e o KEDA (analytics) escalariam para 5 réplicas e o `selfHeal` voltaria para 2 imediatamente — os dois brigariam para sempre. O campo `replicas` é o único que o Git **não** controla.

### Secrets fora do Git

Os `secret.yaml` da Fase 2 não foram para `gitops/`: `DATABASE_URL` e `MASTER_KEY` são credenciais, e tudo em `gitops/` é público no repositório.

Como os Deployments consomem via `envFrom.secretRef`, os Secrets só precisam existir no namespace. `gitops/scripts/criar-secrets.sh` os cria a partir dos outputs do Terraform — nada é digitado à mão:

```bash
AUTH_DB="$(terraform output -json database_urls | jq -r '."auth-db"')"
kubectl -n auth-service create secret generic auth-service-secret --from-literal=DATABASE_URL="$AUTH_DB" ...
```

Se quiser 100% GitOps depois, o caminho é External Secrets Operator ou SealedSecrets — nenhum dos dois exige mudar os Deployments.

### O script de placeholders

Os manifests da Fase 2 têm `<ACCOUNT_ID>` e `<ELASTICACHE-ENDPOINT>`, que só existem depois do apply. `gitops/scripts/preencher-placeholders.sh` os resolve via `aws sts get-caller-identity` e `terraform output`, e você commita uma vez. Daí em diante, o único campo que muda sozinho é a tag.

### Validação dos manifests

`ci-gitops.yml` roda `kustomize build | kubeconform -strict` em cada overlay a cada mudança em `gitops/`. **Por quê:** um YAML inválido commitado na main deixaria as Applications OutOfSync silenciosamente — o ArgoCD falha no cluster, longe do PR. Assim o erro aparece no PR.

---

## Ordem de execução (quando for rodar de verdade)

```bash
# 1. bucket do estado (uma vez só)
cd terraform/bootstrap && terraform init && terraform apply

# 2. infra + ArgoCD
cd .. && terraform init -backend-config=backend.hcl && terraform apply

# 3. acesso ao cluster
terraform output -raw kubeconfig_command | bash

# 4. preencher os manifests e criar os secrets
./gitops/scripts/preencher-placeholders.sh   # commite o resultado
./gitops/scripts/criar-secrets.sh

# 5. entregar o cluster ao ArgoCD
kubectl apply -f gitops/argocd/root-app.yaml

# 6. abrir a UI
terraform output -raw argocd_server_url_command | bash
terraform output -raw argocd_admin_password_command | bash
```

No GitHub, antes de o CI rodar:
- renomear `.github/workflows-propostos` → `.github/workflows`;
- secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` (o último expira a cada sessão do lab);
- Settings → Actions → General → **Workflow permissions: Read and write** (sem isso o `update-gitops` não commita).

---

## Como o ciclo fica no fim

1. Você faz merge de uma mudança no `auth-service`.
2. O CI compila, linta, escaneia dependências e código.
3. Constrói a imagem, escaneia a imagem, publica no ECR como `v1.0.0-<sha>`.
4. Commita essa tag em `gitops/apps/auth-service/kustomization.yaml`.
5. O ArgoCD percebe o commit e aplica o Deployment novo no EKS.
6. A UI mostra o serviço `Synced`/`Healthy`.

Nenhum passo tem alguém digitando comando. Rollback é `git revert` do commit do passo 4.
