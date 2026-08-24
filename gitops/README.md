# GitOps — ToggleMaster

Estado desejado do cluster. O CI **não** faz `kubectl apply`: ele publica a
imagem no ECR e commita a nova tag aqui; o ArgoCD observa `main` e reconcilia o
EKS.

```
CI (push na main) → ECR → commit da tag em gitops/apps/<serviço> → ArgoCD sync → EKS
```

## Estrutura

| Caminho | Conteúdo |
| --- | --- |
| `apps/<serviço>/` | Overlay Kustomize do serviço: namespace, ConfigMap, Deployment, Service, Ingress (+ HPA/KEDA/ServiceAccount onde se aplica) |
| `argocd/project.yaml` | AppProject `togglemaster` |
| `argocd/applications/` | Uma Application por microsserviço |
| `argocd/root-app.yaml` | App-of-apps: aplica os arquivos de `argocd/` |
| `scripts/` | Preenchimento de placeholders e criação dos Secrets |

## Como a tag chega aqui

O `kustomization.yaml` de cada serviço tem um bloco `images` e o Deployment
referencia só o nome lógico (`togglemaster/auth-service`). O job `update-gitops`
do CI roda:

```bash
kustomize edit set image togglemaster/auth-service=<registry>/togglemaster/auth-service:v1.0.0-<sha>
```

Assim o commit do CI mexe em uma linha só, o que evita conflito quando dois
serviços terminam o pipeline ao mesmo tempo.

## Ordem de execução

1. `terraform apply` (cria EKS, RDS, Redis, SQS, ECR e instala o ArgoCD).
2. `./gitops/scripts/preencher-placeholders.sh` — troca `<ACCOUNT_ID>` e o
   endpoint do Redis pelos valores reais e commita.
3. `./gitops/scripts/criar-secrets.sh` — cria os Secrets no cluster.
4. `kubectl apply -f gitops/argocd/root-app.yaml` — a partir daqui o ArgoCD
   assume as 5 Applications.

## Secrets

`DATABASE_URL`, `MASTER_KEY` e `SERVICE_API_KEY` não estão versionados. Os
Deployments os consomem via `envFrom.secretRef`, e o
`scripts/criar-secrets.sh` os cria a partir dos outputs do Terraform. Se quiser
gerenciá-los também por GitOps depois, o caminho é External Secrets Operator ou
SealedSecrets — nenhum dos dois exige mudança nos Deployments.

## Sync automático

Todas as Applications usam:

```yaml
syncPolicy:
  automated: { prune: true, selfHeal: true }
```

`prune` remove do cluster o que sai do Git; `selfHeal` desfaz alteração manual
feita direto no cluster. `spec/replicas` fica em `ignoreDifferences` porque quem
manda nesse campo é o HPA (evaluation) e o KEDA (analytics), não o Git.
