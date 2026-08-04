#!/bin/bash
# Script para iniciar o Core OAI (5G CN)
# Uso: ./scripts/up_core.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="$PROJECT_DIR/oai-cn5g-fed/docker-compose"

echo "=========================================="
echo "Iniciando Core OAI (5G CN)"
echo "=========================================="
echo ""

# Verificar se Docker está rodando
if ! docker info > /dev/null 2>&1; then
    echo "ERRO: Docker não está rodando. Por favor, inicie o Docker primeiro."
    exit 1
fi

# Verificar se o diretório do compose existe
if [ ! -d "$COMPOSE_DIR" ]; then
    echo "ERRO: Diretório não encontrado: $COMPOSE_DIR"
    echo "      Execute o sync do oai-cn5g-fed primeiro."
    exit 1
fi

# Verificar se core-network.py existe
if [ ! -f "$COMPOSE_DIR/core-network.py" ]; then
    echo "ERRO: core-network.py não encontrado em $COMPOSE_DIR"
    exit 1
fi

# Habilitar IP forwarding no host (necessário para roteamento)
echo "Habilitando IP forwarding no host..."
sudo sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true
sudo sysctl -w net.ipv6.conf.all.forwarding=1 2>/dev/null || true
sudo iptables -P FORWARD ACCEPT 2>/dev/null || true

echo ""
echo "Iniciando Core OAI (AMF, SMF, NRF, UPF-VPP, UDM, UDR, AUSF, MySQL, DN)..."
cd "$COMPOSE_DIR"
python3 core-network.py --type start-basic-vpp --scenario 1

echo ""
echo "=========================================="
echo "Core OAI iniciado com sucesso!"
echo "=========================================="
echo ""
echo "Próximo passo sugerido:"
echo "  - Iniciar o RAN (UERANSIM): ./scripts/up_ueransim.sh"
echo "  - Iniciar o RAN (gNB OAI): ./scripts/up_gnb_oai.sh"
echo ""
