#!/usr/bin/env bash
# Substitui os placeholders dos manifests pelos valores reais da conta AWS e
# pelos outputs do Terraform. Rode uma vez, depois do apply, e commite o
# resultado: a partir dai o unico campo que muda sozinho e a tag da imagem,
# escrita pelo job update-gitops do CI.
#
#   ./gitops/scripts/preencher-placeholders.sh
#
# Requer aws-cli e terraform autenticados na conta do lab.
set -euo pipefail

cd "$(dirname "$0")/../.."

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REDIS_HOST="$(terraform -chdir=terraform output -raw redis_primary_endpoint)"

echo "Account ID: $ACCOUNT_ID"
echo "Redis:      $REDIS_HOST"

find gitops/apps -name '*.yaml' -print0 |
  xargs -0 sed -i \
    -e "s|<ACCOUNT_ID>|$ACCOUNT_ID|g" \
    -e "s|<ELASTICACHE-ENDPOINT>|$REDIS_HOST|g"

# O registry das imagens tambem sai do account id; o CI sobrescreve a tag depois.
for dir in gitops/apps/*/; do
  service="$(basename "$dir")"
  (cd "$dir" && kustomize edit set image \
    "togglemaster/$service=$ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/togglemaster/$service:latest")
done

echo
echo "Placeholders restantes (devem ser zero):"
grep -rn '<ACCOUNT_ID>\|<ELASTICACHE-ENDPOINT>\|^\s*newName: ACCOUNT_ID' gitops/apps || echo "nenhum"
