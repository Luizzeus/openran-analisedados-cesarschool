#!/bin/bash
#
# Script para inicializar o sistema free5GC
# Autor: Jonas Augusto Kunzler
# Data: 2026-01-20

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Inicializando free5GC"
echo "=========================================="
echo ""

# Verificar se Docker está rodando
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker não está rodando${NC}"
    exit 1
fi

# Garantir rede compartilhada com as RANs.
NET_NAME="free5gc-privnet"
NET_SUBNET="10.100.200.0/24"
NET_BRIDGE="br-free5gc"
echo "🌐 Verificando rede Docker compartilhada (${NET_NAME})..."
if ! docker network inspect "${NET_NAME}" >/dev/null 2>&1; then
    docker network create \
      --driver bridge \
      --subnet "${NET_SUBNET}" \
      --opt "com.docker.network.bridge.name=${NET_BRIDGE}" \
      "${NET_NAME}" >/dev/null
    echo -e "${GREEN}✅ Rede ${NET_NAME} criada (${NET_SUBNET}, bridge ${NET_BRIDGE})${NC}"
else
    echo -e "${GREEN}✅ Rede ${NET_NAME} já existe${NC}"
fi
echo ""

# Criar diretórios de logs se não existirem
echo "📁 Criando diretórios de logs..."
mkdir -p logs/{amf,ausf,nrf,smf,upf}
echo -e "${GREEN}✅ Diretórios criados${NC}"
echo ""

# Habilitar IP forwarding (necessário para UPF)
echo "🔧 Configurando IP forwarding..."
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo "1" | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    echo -e "${GREEN}✅ IP forwarding habilitado${NC}"
else
    echo -e "${YELLOW}⚠️  IP forwarding já estava habilitado${NC}"
fi
echo ""

# Iniciar serviços na ordem correta
echo "🚀 Iniciando serviços..."
echo ""

# 1. Banco de dados (base para NRF, UDR, UDM, CHF)
echo "1️⃣  Iniciando MongoDB..."
docker compose up -d db
echo "   Aguardando MongoDB ficar pronto..."
sleep 2

# 2. NRF (necessário para registro de todos os NFs)
echo "2️⃣  Iniciando NRF..."
docker compose up -d free5gc-nrf
echo "   Aguardando NRF ficar pronto..."
sleep 2

# 3. Control Plane (em paralelo, pois dependem apenas do NRF)
echo "3️⃣  Iniciando Control Plane (AMF, AUSF, NSSF, PCF, UDM, UDR)..."
docker compose up -d free5gc-amf free5gc-ausf free5gc-nssf free5gc-pcf free5gc-udm free5gc-udr
echo "   Aguardando Control Plane ficar pronto..."
sleep 2

# 4. User Plane
echo "4️⃣  Iniciando UPF..."
docker compose up -d free5gc-upf
echo "   Aguardando UPF ficar pronto..."
sleep 2

# Verificar se UPF iniciou corretamente
if ! docker compose ps free5gc-upf | grep -q "Up"; then
    echo -e "${YELLOW}⚠️  UPF não iniciou. Tentando corrigir...${NC}"
    docker compose restart free5gc-upf
    sleep 5
    if docker compose ps free5gc-upf | grep -q "Up"; then
        echo -e "${GREEN}✅ UPF corrigido e rodando${NC}"
    else
        echo -e "${RED}❌ UPF ainda não está rodando. Verifique logs: docker compose logs free5gc-upf${NC}"
    fi
else
    # UPF iniciou, mas precisa configurar a interface upfgtp
    echo "   Configurando interface upfgtp..."
    if [ -f "./scripts/fix-upf.sh" ]; then
        ./scripts/fix-upf.sh > /dev/null 2>&1
    fi
fi

# 5. SMF (depende de NRF e UPF)
echo "5️⃣  Iniciando SMF..."
docker compose up -d free5gc-smf
echo "   Aguardando SMF ficar pronto..."
sleep 2

# 6. RAN: gNB em gNB_traditional/ ou gNB_disaggregated/ (rede free5gc-privnet compartilhada)
echo "6️⃣  RAN (srsRAN) não faz parte deste compose."
echo "   Com core ativo, suba a RAN desejada:"
echo "   • Tradicional: cd ../gNB_traditional && ./scripts/up.sh"
echo "   • Desagregada (CU/DU): cd ../gNB_disaggregated && ./scripts/up.sh"

# 7. Serviços opcionais (WebUI, NEF, CHF)
echo "7️⃣  Iniciando serviços opcionais (WebUI, NEF, CHF)..."
docker compose up -d free5gc-webui free5gc-nef free5gc-chf
echo ""

# 8. Adicionar subscriber (se necessário)
echo "8️⃣  Verificando subscriber..."
SUPI="imsi-208930000000001"
if docker compose exec -T db sh -c 'command -v mongosh >/dev/null 2>&1'; then
    MONGO_BIN=mongosh
else
    MONGO_BIN=mongo
fi
SUBSCRIBER_EXISTS=$(docker compose exec -T db "$MONGO_BIN" free5gc --quiet --eval "db.subscribers.countDocuments({supi: '$SUPI'})" 2>/dev/null | tr -d '\n\r ' || echo "0")
SUBSCRIBER_EXISTS=${SUBSCRIBER_EXISTS:-0}

if [ "$SUBSCRIBER_EXISTS" -eq 0 ] 2>/dev/null; then
    echo "   Subscriber não encontrado. Adicionando..."
    if [ -f "./scripts/add-subscriber.sh" ]; then
        ./scripts/add-subscriber.sh
    else
        echo -e "${YELLOW}⚠️  Script add-subscriber.sh não encontrado${NC}"
    fi
else
    echo -e "${GREEN}✅ Subscriber já existe${NC}"
fi
echo ""

# Mostrar status
echo "=========================================="
echo "Status dos Containers"
echo "=========================================="
docker compose ps
echo ""

# Verificar saúde dos serviços principais
echo "🔍 Verificando saúde dos serviços..."
sleep 2

HEALTHY=0
UNHEALTHY=0

for service in db free5gc-nrf free5gc-amf free5gc-smf free5gc-upf; do
    if docker compose ps "$service" | grep -q "Up"; then
        echo -e "${GREEN}✅ $service está rodando${NC}"
        ((HEALTHY++))
    else
        echo -e "${RED}❌ $service não está rodando${NC}"
        ((UNHEALTHY++))
    fi
done

echo ""
echo "=========================================="
echo "Resumo"
echo "=========================================="
echo -e "Serviços rodando: ${GREEN}$HEALTHY${NC}"
if [ $UNHEALTHY -gt 0 ]; then
    echo -e "Serviços com problemas: ${RED}$UNHEALTHY${NC}"
    echo ""
    echo "💡 Para ver logs: docker compose logs <servico>"
    echo "💡 Para verificar status: ./scripts/healthcheck.sh"
fi
echo ""
echo "✅ Inicialização concluída!"
echo ""
echo "📋 Próximos passos:"
echo "  - Subir RAN: cd ../gNB_traditional && ./scripts/up.sh  |  ou  cd ../gNB_disaggregated && ./scripts/up.sh"
echo "  - Verificar saúde: ./scripts/healthcheck.sh"
echo "  - Testar sistema: ./scripts/test.sh"
echo "  - Ver logs: docker compose logs -f <servico>"
echo ""

