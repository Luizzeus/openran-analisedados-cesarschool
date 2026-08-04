#!/bin/bash
# Script para parar o RAN UERANSIM (gNB + UE)
# Uso: ./scripts/down_ueransim.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="$PROJECT_DIR/oai-cn5g-fed/docker-compose"

echo "=========================================="
echo "Parando RAN UERANSIM (gNB + UE)"
echo "=========================================="
echo ""

if [ ! -f "$COMPOSE_DIR/docker-compose-ueransim-vpp.yaml" ]; then
    echo "ERRO: docker-compose-ueransim-vpp.yaml não encontrado em $COMPOSE_DIR"
    exit 1
fi

cd "$COMPOSE_DIR"
if command -v docker &> /dev/null && docker compose version &>/dev/null; then
    docker compose -f docker-compose-ueransim-vpp.yaml down
else
    docker-compose -f docker-compose-ueransim-vpp.yaml down
fi

echo ""
echo "=========================================="
echo "UERANSIM parado com sucesso!"
echo "=========================================="
echo ""
echo "💡 Para reiniciar: ./scripts/up_ueransim.sh"
echo ""
