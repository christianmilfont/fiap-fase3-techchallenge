#!/usr/bin/env bash
# Cria no cluster os Secrets que os Deployments consomem via envFrom.
#
# Eles ficam de fora do GitOps de proposito: DATABASE_URL e MASTER_KEY sao
# credenciais e nao entram no Git. Os valores saem dos outputs do Terraform,
# entao nada precisa ser digitado a mao.
#
#   ./gitops/scripts/criar-secrets.sh
#
# Requer kubectl apontando para o cluster e terraform autenticado.
set -euo pipefail

cd "$(dirname "$0")/../.."

tfout() { terraform -chdir=terraform output -json "$1"; }

AUTH_DB="$(tfout database_urls | jq -r '."auth-db"')"
FLAG_DB="$(tfout database_urls | jq -r '."flag-db"')"
TARGETING_DB="$(tfout database_urls | jq -r '."targeting-db"')"
MASTER_KEY="${MASTER_KEY:-$(openssl rand -hex 32)}"

criar() {
  local ns="$1" name="$2"
  shift 2
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$ns" create secret generic "$name" "$@" \
    --dry-run=client -o yaml | kubectl apply -f -
}

criar auth-service auth-service-secret \
  --from-literal=DATABASE_URL="$AUTH_DB" \
  --from-literal=MASTER_KEY="$MASTER_KEY"

criar flag-service flag-service-secret \
  --from-literal=DATABASE_URL="$FLAG_DB"

criar targeting-service targeting-service-secret \
  --from-literal=DATABASE_URL="$TARGETING_DB"

# SERVICE_API_KEY sai do bootstrap do auth-service (POST /admin/keys); ate la o
# secret existe vazio so para o envFrom do Deployment nao travar o pod.
criar evaluation-service evaluation-service-secret \
  --from-literal=SERVICE_API_KEY="${SERVICE_API_KEY:-}"

# analytics-service usa IRSA, sem credencial em variavel de ambiente.
criar analytics-service analytics-service-secret

echo
echo "MASTER_KEY usada: $MASTER_KEY"
echo "Guarde esse valor — ele nao esta versionado."
