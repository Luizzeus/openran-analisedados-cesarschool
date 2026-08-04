#!/bin/bash
# Para nonRT RIC O-RAN SC (containers Docker).
# Uso: ./scripts/down_nonrt_ric.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NONRT_DIR="${NONRT_COMPOSE_DIR:-$PROJECT_DIR/config/nonrtric}"

echo "Parando nonRT RIC (O-RAN SC)..."

if [ -f "$NONRT_DIR/docker-compose.yml" ]; then
    cd "$NONRT_DIR"
    docker compose --env-file .env down --remove-orphans 2>/dev/null || true
fi

echo "nonRT RIC parado."
