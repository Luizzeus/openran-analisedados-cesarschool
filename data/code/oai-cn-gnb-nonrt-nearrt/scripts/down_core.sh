#!/bin/bash
# Script para parar o Core OAI (5G CN)
# Uso: ./scripts/down_core.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="$PROJECT_DIR/oai-cn5g-fed/docker-compose"

echo "=========================================="
echo "Parando Core OAI (5G CN)"
echo "=========================================="
echo ""

if [ ! -f "$COMPOSE_DIR/core-network.py" ]; then
    echo "ERRO: core-network.py não encontrado em $COMPOSE_DIR"
    exit 1
fi

cd "$COMPOSE_DIR"
python3 core-network.py --type stop-basic-vpp --scenario 1

echo ""
echo "=========================================="
echo "Core OAI parado com sucesso!"
echo "=========================================="
echo ""
echo "💡 Para reiniciar: ./scripts/up_core.sh"
echo "   (O RAN/UERANSIM, se estiver rodando, continua ativo. Para pará-lo: ./scripts/down_ran.sh)"
echo ""
