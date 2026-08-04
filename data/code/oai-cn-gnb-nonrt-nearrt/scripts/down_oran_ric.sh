#!/bin/bash
# Para nearRT O-RAN SC (Fase 2).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORAN_VENDOR="${ORAN_VENDOR_DIR:-$PROJECT_DIR/vendor/oran-sc-ric}"
ORAN_CFG="${ORAN_CFG_DIR:-$PROJECT_DIR/config/oran-ric}"

docker compose \
    -f "$ORAN_VENDOR/docker-compose.yml" \
    -f "$ORAN_CFG/docker-compose.override.yml" \
    --env-file "$ORAN_VENDOR/.env" \
    --env-file "$ORAN_CFG/.env" \
    down 2>/dev/null || true

echo "nearRT O-RAN SC parado."
