# CI/CD & DevSecOps

> Esta pasta precisa ser renomeada para `.github/workflows/` para o GitHub Actions
> reconhecer os pipelines (`git mv .github/workflows-propostos .github/workflows`).
> Os arquivos já referenciam esse caminho final. O nome provisório existe porque o token
> usado para abrir este PR não tem o escopo `workflow` do GitHub e o push de
> `.github/workflows/` é rejeitado.

Um workflow por microserviço (`ci-<serviço>.yml`), todos chamando o pipeline reutilizável
`_service-ci.yml`, mais `ci-terraform.yml` para a infraestrutura.

| Workflow | Serviço | Stack | ECR |
| --- | --- | --- | --- |
| `ci-auth-service.yml` | auth-service | Go 1.25 | `togglemaster/auth-service` |
| `ci-flag-service.yml` | flag-service | Python 3.11 + uv | `togglemaster/flag-service` |
| `ci-targeting-service.yml` | targeting-service | Python 3.11 + uv | `togglemaster/targeting-service` |
| `ci-evaluation-service.yml` | evaluation-service | Go 1.25 | `togglemaster/evaluation-service` |
| `ci-analytics-service.yml` | analytics-service | Python 3.11 + uv | `togglemaster/analytics-service` |
| `ci-terraform.yml` | infra | Terraform 1.12 | — |
| `ci-gitops.yml` | manifests | Kustomize + kubeconform | — |

Disparo: `pull_request` e `push` na `main`, filtrados pelo path do serviço (+ `workflow_dispatch`).

As pastas dos 5 serviços eram gitlinks de submódulo (vazias no clone) e passaram a ser
commitadas diretamente neste repo, para que os pipelines consigam compilar e buildar.

## Estágios (`_service-ci.yml`)

1. **Build & Unit Test** — Go: `go build ./...` + `go test ./...`. Python: `uv sync --frozen`,
   `compileall` e `pytest`. Hoje nenhum dos 5 serviços tem testes unitários: em Go o
   `go test` passa com "no test files" e em Python a etapa é explicitamente ignorada.
2. **Linter / Static Analysis** — Go: `go vet` + `golangci-lint`. Python: `flake8`
   (erros de sintaxe/nome indefinido bloqueiam; estilo é informativo).
3. **Security Scan (SCA + SAST)** — `trivy fs` nas dependências (`vuln,secret`) e
   `gosec` (Go) / `bandit` (Python) no código fonte, ambos bloqueando em severidade HIGH
   e com uma segunda execução informativa nas severidades menores.
4. **Docker Build & Push** — build da imagem, `trivy image` e push no ECR.
5. **Atualizar tag no GitOps** — `kustomize edit set image` em `gitops/apps/<serviço>`
   e commit na `main`. Só roda em `push` na `main`.

Os três primeiros jobs rodam em paralelo; o `docker` depende dos três (`needs`) e o
`update-gitops` depende do `docker`.

### Regra de bloqueio

Todo scan Trivy roda duas vezes: uma com `severity: CRITICAL` e `exit-code: 1` (falha o
pipeline) e outra com `HIGH,MEDIUM` apenas informativa. Isso vale para dependências
(SCA), imagem (container scan) e, no Terraform, misconfigurations de IaC. `gosec`
(`-severity high`) e `bandit` (`-lll`) também falham o job.

Como o job `docker` depende dos anteriores, uma CRITICAL em qualquer estágio impede o
build e o push da imagem.

No scan de IaC, as exceções ficam em `.trivyignore` na raiz (endpoint público do EKS e
egress `0.0.0.0/0`, ambos necessários no ambiente do AWS Academy), cada uma com
justificativa no próprio arquivo.

Exceção documentada: `gosec` roda com `-exclude=G704` (SSRF por taint analysis). No
`evaluation-service` a regra aponta as chamadas ao flag/targeting-service, cujas URLs base
vêm de variável de ambiente/ConfigMap e não de entrada do usuário. As demais regras HIGH
continuam bloqueando.

### Push no ECR

Só acontece em `push` na `main` — em Pull Request o pipeline vai até o container scan
(build sem push). Tags publicadas:

```
<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/togglemaster/auth-service:v1.0.0-a1b2c3d
<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/togglemaster/auth-service:latest
```

O prefixo `v1.0.0` vem do input `image_version` do workflow reutilizável; o sufixo é o
commit hash curto.

### Entrega contínua (GitOps)

Não há `kubectl apply` no CI. Depois do push da imagem, o job `update-gitops` escreve a
mesma tag em `gitops/apps/<serviço>/kustomization.yaml` e commita na `main` — o ArgoCD
vê o commit e sincroniza o cluster. Detalhes em `gitops/README.md`.

Os commits dos 5 pipelines disputam a mesma branch, então o job usa
`concurrency: gitops-write` (serializa) e, se ainda assim o push for rejeitado, refaz o
`git pull --rebase` e tenta de novo, até 5 vezes.

## Secrets necessários

Em **Settings → Secrets and variables → Actions**:

| Secret | Observação |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | credenciais do AWS Academy |
| `AWS_SECRET_ACCESS_KEY` | |
| `AWS_SESSION_TOKEN` | obrigatório no Academy (credenciais temporárias, expiram a cada sessão do lab) |
| `GITOPS_TOKEN` | opcional. Com o GitOps neste mesmo repo, o `GITHUB_TOKEN` já basta (o job pede `contents: write`); só é necessário se você mover `gitops/` para outro repositório |

Os repositórios ECR são criados pelo módulo `ecr` do Terraform (`terraform/`), com os
mesmos nomes usados aqui.
