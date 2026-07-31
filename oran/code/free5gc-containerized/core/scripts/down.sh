#!/bin/bash
#
# Script para encerrar o sistema free5GC
# Autor: Jonas Augusto Kunzler
# Data: 2026-01-20

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Encerrando free5GC"
echo "=========================================="
echo ""
echo "Dica: se a RAN ainda estiver ativa (gNB_traditional / gNB_disaggregated), pode encerrá-la antes para evitar erros de N2 nos logs."
echo ""

# Verificar se há containers rodando
if ! docker compose ps | grep -q "Up"; then
    echo -e "${YELLOW}⚠️  Nenhum container está rodando${NC}"
    exit 0
fi

# Perguntar se deseja remover volumes
if [ "$1" = "--volumes" ] || [ "$1" = "-v" ]; then
    REMOVE_VOLUMES=true
    echo -e "${YELLOW}⚠️  ATENÇÃO: Volumes serão removidos (incluindo dados do MongoDB)${NC}"
    read -p "Continuar? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "Operação cancelada."
        exit 0
    fi
else
    REMOVE_VOLUMES=false
fi

# Parar containers
echo "🛑 Parando containers..."
if [ "$REMOVE_VOLUMES" = true ]; then
    docker compose down -v
    echo -e "${GREEN}✅ Containers parados e volumes removidos${NC}"
else
    docker compose down
    echo -e "${GREEN}✅ Containers parados (volumes preservados)${NC}"
fi
echo ""

# Mostrar status final
echo "=========================================="
echo "Status Final"
echo "=========================================="
docker compose ps
echo ""

if [ "$REMOVE_VOLUMES" = false ]; then
    echo "💡 Para remover volumes também, execute: ./scripts/down.sh --volumes"
fi

echo "✅ Encerramento concluído!"
echo ""

