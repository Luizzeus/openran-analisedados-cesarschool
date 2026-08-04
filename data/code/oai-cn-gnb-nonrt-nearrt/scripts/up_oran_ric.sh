#!/bin/bash
# Sobe nearRT O-RAN SC (oran-sc-ric) — Fase 2.
# Base: vendor/oran-sc-ric + overlay config/oran-ric/
# E2 SCTP exposto em :36422 (não conflita com FlexRIC :36421).
#
# Uso: ./scripts/up_oran_ric.sh
# Pré-requisito: Docker; FlexRIC parado (./scripts/down_flexric.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORAN_VENDOR="${ORAN_VENDOR_DIR:-$PROJECT_DIR/vendor/oran-sc-ric}"
ORAN_CFG="${ORAN_CFG_DIR:-$PROJECT_DIR/config/oran-ric}"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"

if ! docker info >/dev/null 2>&1; then
    echo "ERRO: Docker não está rodando."
    exit 1
fi

if [ ! -f "$ORAN_VENDOR/docker-compose.yml" ]; then
    echo "ERRO: vendor/oran-sc-ric não encontrado."
    exit 1
fi

if pgrep -x "nearRT-RIC" >/dev/null 2>&1; then
    echo "AVISO: FlexRIC nearRT-RIC em execução — porta E2 em conflito."
    echo "       Execute: ./scripts/down_flexric.sh"
    exit 1
fi

mkdir -p "$LOG_DIR"

compose() {
    docker compose \
        -f "$ORAN_VENDOR/docker-compose.yml" \
        -f "$ORAN_CFG/docker-compose.override.yml" \
        --env-file "$ORAN_VENDOR/.env" \
        --env-file "$ORAN_CFG/.env" \
        "$@"
}

if compose ps -q 2>/dev/null | grep -q .; then
    if compose ps --status running 2>/dev/null | grep -q ric_e2term; then
        echo "nearRT O-RAN SC já está em execução."
        compose ps
        exit 0
    fi
    echo "nearRT O-RAN SC está parcialmente iniciado (ric_e2term ausente)."
    echo "Recriando stack para limpar containers parciais..."
    compose down --remove-orphans 2>/dev/null || true
fi

echo "=========================================="
echo "Iniciando nearRT O-RAN SC (Fase 2)"
echo "=========================================="
echo "Vendor: $ORAN_VENDOR"
echo "Overlay: $ORAN_CFG"
echo ""

cd "$ORAN_VENDOR"
echo "A descarregar/construir imagens (primeira vez demora)..."
compose pull 2>/dev/null || true
compose up -d --build 2>&1 | tee "$LOG_DIR/oran_ric_up.log"

echo ""
echo "Aguardando containers (até 120s)..."
for i in $(seq 1 40); do
    if compose ps --status running 2>/dev/null | grep -q ric_e2term; then
        break
    fi
    sleep 3
done

echo ""
echo "=========================================="
echo "nearRT O-RAN SC iniciado"
echo "=========================================="
echo ""
echo "  E2 Termination (SCTP): 127.0.0.1:${ORAN_E2_HOST_PORT:-36422}"
echo "  A1 Mediator:           http://127.0.0.1:${A1MEDIATOR_HOST_PORT:-10000}/a1-p/healthcheck"
echo ""
echo "  xApp (exemplo):"
echo "    docker compose -f $ORAN_VENDOR/docker-compose.yml -f $ORAN_CFG/docker-compose.override.yml \\"
echo "      --env-file $ORAN_VENDOR/.env --env-file $ORAN_CFG/.env \\"
echo "      exec python_xapp_runner ./simple_mon_xapp.py --metrics=DRB.UEThpDl,DRB.UEThpUl"
echo ""
echo "Teste:  ./scripts/test_oran_ric.sh"
echo "Parar:  ./scripts/down_oran_ric.sh"
