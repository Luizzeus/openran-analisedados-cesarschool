#!/bin/bash
# Script para testar throughput do plano de usuário (VPP-UPF)
# Demonstra os benefícios do Vector Packet Processing via iperf3
#
# Requer: Core OAI (basic-vpp) e UERANSIM rodando
# Uso: ./scripts/test-vpp-throughput.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Containers OAI
DN_CONTAINER="oai-ext-dn"
UE_CONTAINER="ueransim"

# IP do Data Network (oai-ext-dn no docker-compose-basic-vpp-nrf)
DN_IP="${OAI_DN_IP:-192.168.73.135}"

# Duração do teste (segundos)
DURATION="${IPERF_DURATION:-10}"

# UE: ueransim (container) ou nrue (oaitun no host)
UE_SOURCE="${UE_SOURCE:-ueransim}"

# Modo: tcp (padrão) ou udp
MODE="${IPERF_MODE:-tcp}"
IPERF_EXTRA_ARGS=""
[ "$MODE" = "udp" ] && IPERF_EXTRA_ARGS="-u -b 100M"

# Timeout para evitar travamento se UE não conectar (segundos)
IPERF_TIMEOUT=$((DURATION + 25))

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Teste de Throughput VPP (iperf3)"
echo "=========================================="
echo ""
echo "Este teste mede o throughput do plano de usuário 5G"
echo "através do UPF-VPP (Vector Packet Processing)."
echo ""

# Verificar containers
echo "Verificando containers..."
if ! docker ps --format '{{.Names}}' | grep -q "^${DN_CONTAINER}$"; then
    echo -e "${RED}ERRO: Container '$DN_CONTAINER' não está rodando.${NC}"
    echo "  Inicie o Core: ./scripts/up_core.sh"
    exit 1
fi
if [ "$UE_SOURCE" = "ueransim" ]; then
    if ! docker ps --format '{{.Names}}' | grep -q "^${UE_CONTAINER}$"; then
        echo -e "${RED}ERRO: Container '$UE_CONTAINER' não está rodando.${NC}"
        echo "  Inicie UERANSIM: ./scripts/up_ueransim.sh"
        echo "  Ou use nrUE: UE_SOURCE=nrue ./scripts/test-vpp-throughput.sh"
        exit 1
    fi
fi
echo -e "${GREEN}✓ Containers OK${NC}"
echo ""

# Detectar interface oaitun para nrUE
OAITUN_IF=""
if [ "$UE_SOURCE" = "nrue" ]; then
    for iface in oaitun_ue0 oaitun_ue1 oaitun_ue2; do
        if ip -4 addr show "$iface" >/dev/null 2>&1; then
            OAITUN_IF="$iface"
            break
        fi
    done
    if [ -z "$OAITUN_IF" ]; then
        echo -e "${RED}ERRO: Nenhuma interface oaitun_ue encontrada.${NC}"
        echo "  Inicie o gNB OAI e nrUE: ./scripts/up_gnb_oai.sh"
        exit 1
    fi
    echo "Usando nrUE (interface $OAITUN_IF)"
fi

# Obter IP da interface do túnel para forçar tráfego pelo plano de usuário
# UERANSIM: uesimtun0 (12.1.1.x) | nrUE: oaitun_ue* (12.1.1.x)
UE_BIND_IP=""
if [ "$UE_SOURCE" = "ueransim" ]; then
    UE_BIND_IP=$(docker exec "$UE_CONTAINER" ip -4 addr show uesimtun0 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    if [ -z "$UE_BIND_IP" ]; then
        UE_BIND_IP=$(docker exec "$UE_CONTAINER" ip addr show 2>/dev/null | grep -oP 'inet \K12\.1\.1\.\d+' | head -1)
    fi
    if [ -z "$UE_BIND_IP" ]; then
        echo -e "${RED}ERRO: Interface uesimtun0 não encontrada no UERANSIM.${NC}"
        echo "  Verifique se a sessão PDU foi estabelecida (docker logs $UE_CONTAINER)"
        exit 1
    fi
    echo "UERANSIM: usando uesimtun0 ($UE_BIND_IP)"
    echo "Verificando conectividade UE -> DN ($DN_IP)..."
    if ! docker exec "$UE_CONTAINER" ping -c 1 -W 2 -I uesimtun0 "$DN_IP" >/dev/null 2>&1; then
        echo -e "${YELLOW}Aviso: ping ao DN falhou. Tentando iperf3 com -B $UE_BIND_IP...${NC}"
    else
        echo -e "${GREEN}✓ Conectividade OK${NC}"
    fi
fi
echo ""

# Instalar iperf3 se necessário (containers)
install_iperf() {
    local container=$1
    if docker exec "$container" which iperf3 >/dev/null 2>&1; then
        return 0
    fi
    echo "Instalando iperf3 em $container..."
    if docker exec "$container" sh -c "command -v apt-get >/dev/null 2>&1"; then
        docker exec "$container" apt-get update -qq && docker exec "$container" apt-get install -y -qq iperf3 >/dev/null 2>&1 || true
    elif docker exec "$container" sh -c "command -v apk >/dev/null 2>&1"; then
        docker exec "$container" apk add --no-cache iperf3 >/dev/null 2>&1 || true
    fi
    if ! docker exec "$container" which iperf3 >/dev/null 2>&1; then
        echo -e "${RED}ERRO: Não foi possível instalar iperf3 em $container${NC}"
        return 1
    fi
    return 0
}

install_iperf "$DN_CONTAINER" || exit 1
[ "$UE_SOURCE" = "ueransim" ] && install_iperf "$UE_CONTAINER" || true
echo ""

# Verificar iperf3 no host para nrUE
if [ "$UE_SOURCE" = "nrue" ]; then
    if ! command -v iperf3 >/dev/null 2>&1; then
        echo -e "${YELLOW}Aviso: iperf3 não encontrado no host. Instale: sudo apt install iperf3${NC}"
        exit 1
    fi
fi

# Iniciar servidor iperf3 no DN
echo "Iniciando servidor iperf3 no DN ($DN_CONTAINER)..."
docker exec "$DN_CONTAINER" pkill -f iperf3 2>/dev/null || true
sleep 1
docker exec -d "$DN_CONTAINER" iperf3 -s
sleep 2

# Executar cliente iperf3 (sempre com -B para forçar tráfego pela interface do túnel)
echo "Executando teste de throughput (${DURATION}s, modo ${MODE})..."
echo "--------------------------------------------"
if [ "$UE_SOURCE" = "nrue" ]; then
    UE_BIND_IP=$(ip -4 addr show "$OAITUN_IF" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    timeout "$IPERF_TIMEOUT" iperf3 -c "$DN_IP" -t "$DURATION" -f m -B "$UE_BIND_IP" $IPERF_EXTRA_ARGS 2>&1 || true
else
    timeout "$IPERF_TIMEOUT" docker exec "$UE_CONTAINER" iperf3 -c "$DN_IP" -t "$DURATION" -f m -B "$UE_BIND_IP" $IPERF_EXTRA_ARGS 2>&1 || true
fi
echo "--------------------------------------------"

# Parar servidor
docker exec "$DN_CONTAINER" pkill -f iperf3 2>/dev/null || true

echo ""
echo "=========================================="
echo "Teste concluído"
echo "=========================================="
echo ""
echo "O throughput medido reflete o desempenho do UPF-VPP no caminho"
echo "UE -> gNB (N3/GTP-U) -> UPF-VPP -> DN (N6)."
echo ""
echo "Opções: UE_SOURCE=nrue (nrUE/OAI) | ueransim (padrão)"
echo "        IPERF_DURATION=15 | IPERF_MODE=udp"
echo ""
echo "Para comparar com SPGWU-Tiny, use a stack basic-nrf e repita o teste."
echo ""
