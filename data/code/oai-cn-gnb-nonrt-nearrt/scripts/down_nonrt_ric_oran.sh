#!/bin/bash
# Para nonRT RIC perfil Fase 2.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NONRT_DIR="${NONRT_COMPOSE_DIR:-$PROJECT_DIR/config/nonrtric}"

docker compose -f "$NONRT_DIR/docker-compose.oran.yml" --env-file "$NONRT_DIR/.env" down 2>/dev/null || true
echo "nonRT RIC (perfil oran) parado."
