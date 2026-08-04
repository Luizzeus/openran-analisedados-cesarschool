#!/bin/bash
# Sobe nonRT RIC O-RAN SC (Fase 1): PMS + A1 Simulators + Gateway + Control Panel.
# Uso: ./scripts/up_nonrt_ric.sh
#
# Não interfere com nearRT FlexRIC (portas distintas).
# Pré-requisito: Docker em execução.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NONRT_DIR="${NONRT_COMPOSE_DIR:-$PROJECT_DIR/config/nonrtric}"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"

if ! docker info >/dev/null 2>&1; then
    echo "ERRO: Docker não está rodando."
    exit 1
fi

if [ ! -f "$NONRT_DIR/docker-compose.yml" ]; then
    echo "ERRO: Compose não encontrado em $NONRT_DIR"
    exit 1
fi

mkdir -p "$LOG_DIR"

if docker compose -f "$NONRT_DIR/docker-compose.yml" --env-file "$NONRT_DIR/.env" ps -q 2>/dev/null | grep -q .; then
    echo "nonRT RIC já está em execução."
    docker compose -f "$NONRT_DIR/docker-compose.yml" --env-file "$NONRT_DIR/.env" ps
    exit 0
fi

echo "=========================================="
echo "Iniciando nonRT RIC (O-RAN SC) — Fase 1"
echo "=========================================="
echo "Compose: $NONRT_DIR"
echo ""

cd "$NONRT_DIR"

echo "A descarregar imagens O-RAN SC (primeira vez pode demorar)..."
docker compose --env-file .env pull

echo ""
echo "A iniciar containers..."
docker compose --env-file .env up -d 2>&1 | tee "$LOG_DIR/nonrt_ric_up.log"

echo ""
echo "Aguardando Policy Management Service (até 90s)..."
for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:${NONRT_PMS_HTTP_PORT:-8081}/status" 2>/dev/null | grep -qi "hunky dory"; then
        echo "PMS OK."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "AVISO: PMS ainda não respondeu. Ver: docker compose -f $NONRT_DIR/docker-compose.yml logs policy-agent"
    fi
    sleep 3
done

echo ""
echo "=========================================="
echo "nonRT RIC iniciado"
echo "=========================================="
echo ""
echo "  Control Panel:  http://127.0.0.1:${NONRT_CONTROL_PANEL_PORT:-8181}/"
echo "  API Gateway:    http://127.0.0.1:${NONRT_GATEWAY_PORT:-9090}/"
echo "  PMS (HTTP):     http://127.0.0.1:${NONRT_PMS_HTTP_PORT:-8081}/status"
echo "  A1 Sim OSC:     http://127.0.0.1:30001/counter/interface"
echo "  A1 Sim STD v2:  http://127.0.0.1:30005/counter/interface"
echo ""
echo "Teste:  ./scripts/test_nonrt_ric.sh"
echo "Parar:  ./scripts/down_nonrt_ric.sh"
echo "Log:    $LOG_DIR/nonrt_ric_up.log"
