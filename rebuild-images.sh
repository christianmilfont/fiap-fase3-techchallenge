#!/bin/bash
#  ./rebuild-images.sh                        # reconstrói tudo (Go + Python)
#  ./rebuild-images.sh auth-service           # só Go auth
#  ./rebuild-images.sh evaluation-service     # só Go evaluation
#  ./rebuild-images.sh flag-service           # só Python flag (roda uv lock primeiro)
#  ./rebuild-images.sh flag-service targeting-service  # dois de uma vez


set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PYTHON_SERVICES=("flag-service" "targeting-service" "analytics-service")
GO_SERVICES=("auth-service" "evaluation-service")
ALL_SERVICES=("${GO_SERVICES[@]}" "${PYTHON_SERVICES[@]}")

# Serviços a rebuildar: argumentos ou todos
TARGETS=("${@:-${ALL_SERVICES[@]}}")

echo ">>> Rebuilding: ${TARGETS[*]}"

# uv lock apenas nos serviços Python que estão nos targets
for svc in "${PYTHON_SERVICES[@]}"; do
    for target in "${TARGETS[@]}"; do
        if [[ "$target" == "$svc" ]]; then
            echo ">>> uv lock: $svc"
            (cd "$svc" && uv lock)
        fi
    done
done

# Build via docker compose (usa as imagens corretas do compose)
echo ">>> docker compose build --no-cache ${TARGETS[*]}"
docker compose build --no-cache "${TARGETS[@]}"

echo ">>> Pronto. Rode: docker compose up -d"
