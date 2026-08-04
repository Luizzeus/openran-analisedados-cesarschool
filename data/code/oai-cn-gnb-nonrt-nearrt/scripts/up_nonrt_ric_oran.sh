#!/bin/bash
# Sobe nonRT RIC perfil Fase 2 (PMS → A1 Mediator, sem simuladores).
# Requer nearRT O-RAN SC: ./scripts/up_oran_ric.sh
# Fase 1 inalterada: ./scripts/up_nonrt_ric.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NONRT_DIR="${NONRT_COMPOSE_DIR:-$PROJECT_DIR/config/nonrtric}"
COMPOSE_FILE="$NONRT_DIR/docker-compose.oran.yml"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"

if ! docker network inspect oran-sc-ric_ric_network >/dev/null 2>&1; then
    echo "ERRO: Rede oran-sc-ric_ric_network não existe."
    echo "      Inicie primeiro: ./scripts/up_oran_ric.sh"
    exit 1
fi

mkdir -p "$LOG_DIR"

if docker compose -f "$COMPOSE_FILE" --env-file "$NONRT_DIR/.env" ps -q 2>/dev/null | grep -q .; then
    echo "nonRT RIC (perfil oran) já em execução."
    docker compose -f "$COMPOSE_FILE" --env-file "$NONRT_DIR/.env" ps
    exit 0
fi

echo "=========================================="
echo "Iniciando nonRT RIC — perfil Fase 2 (A1 real)"
echo "=========================================="

cd "$NONRT_DIR"
docker compose -f docker-compose.oran.yml --env-file .env pull
docker compose -f docker-compose.oran.yml --env-file .env up -d 2>&1 | tee "$LOG_DIR/nonrt_ric_oran_up.log"

for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:${NONRT_PMS_HTTP_PORT:-8081}/status" 2>/dev/null | grep -qi "hunky dory"; then
        echo "PMS OK."
        break
    fi
    sleep 3
done

echo ""
echo "Control Panel: http://127.0.0.1:${NONRT_CONTROL_PANEL_PORT:-8181}/"
echo "Teste: ./scripts/test_oran_ric.sh"
