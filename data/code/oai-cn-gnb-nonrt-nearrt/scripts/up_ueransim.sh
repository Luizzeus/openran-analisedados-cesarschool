#!/bin/bash
# Script para iniciar o RAN UERANSIM (gNB + UE em container)
# Uso: ./scripts/up_ueransim.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="$PROJECT_DIR/oai-cn5g-fed/docker-compose"

echo "=========================================="
echo "Iniciando RAN UERANSIM (gNB + UE)"
echo "=========================================="
echo ""

# Verificar se Docker está rodando
if ! docker info > /dev/null 2>&1; then
    echo "ERRO: Docker não está rodando. Por favor, inicie o Docker primeiro."
    exit 1
fi

# Verificar se docker compose está disponível
if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo "ERRO: docker compose não está disponível. Instale Docker Compose."
    exit 1
fi

# Verificar se as redes necessárias existem (criadas pelo Core)
echo "Verificando redes Docker (demo-oai-public-net, oai-public-access)..."
for NET in demo-oai-public-net oai-public-access; do
    if ! docker network inspect "$NET" >/dev/null 2>&1; then
        echo "ERRO: Rede Docker '$NET' não encontrada."
        echo "      Certifique-se de iniciar o Core primeiro com: ./scripts/up_core.sh"
        exit 1
    fi
done

# Verificar se o compose existe
if [ ! -f "$COMPOSE_DIR/docker-compose-ueransim-vpp.yaml" ]; then
    echo "ERRO: docker-compose-ueransim-vpp.yaml não encontrado em $COMPOSE_DIR"
    exit 1
fi

echo ""
echo "Iniciando UERANSIM..."
cd "$COMPOSE_DIR"
if command -v docker &> /dev/null && docker compose version &>/dev/null; then
    docker compose -f docker-compose-ueransim-vpp.yaml up -d
else
    docker-compose -f docker-compose-ueransim-vpp.yaml up -d
fi

echo ""
echo "Aguardando UERANSIM iniciar..."
sleep 10

echo ""
echo "Status do UERANSIM:"
docker ps --filter "name=ueransim" --format "table {{.Names}}\t{{.Status}}"

echo ""
echo "=========================================="
echo "UERANSIM iniciado com sucesso!"
echo "=========================================="
echo ""
echo "Dicas:"
echo "  - Ver logs: docker logs -f ueransim"
echo "  - Testar conectividade: docker exec ueransim ping -c 3 -I uesimtun0 8.8.8.8"
echo ""
