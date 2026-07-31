#!/bin/bash
#
# Script para verificar a saúde dos serviços free5GC
# Autor: Jonas Augusto Kunzler
# Data: 2026-01-20

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# shellcheck source=lib/ran-docker.sh
. "$SCRIPT_DIR/lib/ran-docker.sh"

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Healthcheck - free5GC"
echo "=========================================="
echo ""

# Verificar status dos containers
echo "📋 Status dos Containers:"
docker compose ps
echo ""

# Verificar processos dos serviços principais
echo "🔍 Verificando processos dos serviços..."
declare -A SERVICES=(
    ["MongoDB"]="db"
    ["NRF"]="free5gc-nrf"
    ["AMF"]="free5gc-amf"
    ["SMF"]="free5gc-smf"
    ["UPF"]="free5gc-upf"
    ["AUSF"]="free5gc-ausf"
    ["UDM"]="free5gc-udm"
    ["UDR"]="free5gc-udr"
    ["PCF"]="free5gc-pcf"
    ["NSSF"]="free5gc-nssf"
)

HEALTHY=0
UNHEALTHY=0

for name in "${!SERVICES[@]}"; do
    service="${SERVICES[$name]}"
    if docker compose ps "$service" 2>/dev/null | grep -q "Up"; then
        echo -e "${GREEN}✓ $name está rodando${NC}"
        ((HEALTHY++))
    else
        echo -e "${RED}✗ $name não está rodando${NC}"
        ((UNHEALTHY++))
    fi
done

echo "🔍 RAN (compose separado em gNB_traditional / gNB_disaggregated)..."
if list_ran_n2_containers; then
    echo -e "${GREEN}✓ RAN N2 ativo(s): ${RAN_N2_CONTAINERS[*]}${NC}"
    ((HEALTHY++))
else
    echo -e "${YELLOW}⚠ Nenhum container RAN N2 ativo (esperado se ainda não subiu gNB_traditional/gNB_disaggregated)${NC}"
fi
echo ""

# Verificar conectividade de rede
echo "🌐 Verificando conectividade de rede..."
echo ""

# Testar NRF
echo "Testando NRF..."
if docker compose exec -T free5gc-nrf wget -q --spider http://localhost:8000/ 2>/dev/null || \
   docker compose exec -T free5gc-nrf pgrep -f "nrf" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ NRF está acessível${NC}"
else
    echo -e "${RED}✗ NRF não está acessível${NC}"
fi

# Testar AMF
echo "Testando AMF..."
if docker compose exec -T free5gc-amf pgrep -f "amf" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ AMF está rodando${NC}"
else
    echo -e "${RED}✗ AMF não está rodando${NC}"
fi

# Testar SMF
echo "Testando SMF..."
if docker compose exec -T free5gc-smf pgrep -f "smf" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ SMF está rodando${NC}"
else
    echo -e "${RED}✗ SMF não está rodando${NC}"
fi

# Testar UPF
echo "Testando UPF..."
# O container UPF não tem pgrep/ps, então verificamos de outras formas:
# 1. Verificar se o processo principal é o UPF (/proc/1/exe)
# 2. Verificar se a interface upfgtp existe (criada pelo UPF com gtp5g)
# 3. Verificar se há logs recentes do UPF indicando que está rodando
UPF_RUNNING=false

# Verificar se o processo principal é o UPF (mais confiável que pgrep)
if docker compose exec -T free5gc-upf sh -c 'test -f /proc/1/exe && readlink /proc/1/exe 2>/dev/null | grep -q "upf"' 2>/dev/null; then
    UPF_RUNNING=true
fi

# Verificar interface upfgtp (criada quando UPF inicia com gtp5g)
if docker compose exec -T free5gc-upf ip link show upfgtp >/dev/null 2>&1; then
    UPF_RUNNING=true
fi

# Verificar logs recentes (últimos 60 segundos) para confirmação
if docker compose logs free5gc-upf --since 60s 2>&1 | grep -qiE "UPF started|pfcp server started|Gtp5g.*Forwarder started"; then
    UPF_RUNNING=true
fi

if [ "$UPF_RUNNING" = true ]; then
    echo -e "${GREEN}✓ UPF está rodando${NC}"
else
    echo -e "${RED}✗ UPF não está rodando${NC}"
    echo "   💡 Verifique: docker compose logs free5gc-upf"
fi

# Testar conectividade entre AMF e RAN (N2)
echo "Testando conectividade N2 (AMF <-> RAN)..."
AMF_IP=$(docker compose exec -T free5gc-amf ip addr show eth0 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo "")
if [ -n "$AMF_IP" ] && list_ran_n2_containers; then
    for GNB_IP in $(ran_n2_all_ips); do
        if docker compose exec -T free5gc-amf ping -c 1 -W 1 "$GNB_IP" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ AMF pode alcançar RAN N2 ($GNB_IP)${NC}"
        else
            echo -e "${YELLOW}⚠ AMF não alcança $GNB_IP (ICMP pode estar bloqueado)${NC}"
        fi
    done
else
    echo -e "${YELLOW}⚠ Não foi possível testar ping AMF↔RAN (AMF=$AMF_IP ou sem RAN N2)${NC}"
fi
echo ""

# Verificar logs recentes para erros críticos
echo "📊 Verificando logs recentes..."
echo ""

# Verificar NG Setup no AMF
echo "Verificando NG Setup (gNB <-> AMF)..."
NG_SETUP=$(docker compose logs free5gc-amf 2>&1 | grep -c "NGSetupRequest\|NG-Setup response" 2>/dev/null | head -1 || echo "0")
NG_SETUP=$(echo "$NG_SETUP" | tr -d '\n\r ' | grep -oE '^[0-9]+' || echo "0")
NG_SETUP=${NG_SETUP:-0}
if [ "$NG_SETUP" -gt 0 ] 2>/dev/null; then
    echo -e "${GREEN}✓ NG Setup detectado ($NG_SETUP ocorrência(s))${NC}"
else
    echo -e "${YELLOW}⚠ NG Setup não encontrado nos logs${NC}"
fi

# Verificar registro de NFs no NRF
echo "Verificando registro de NFs no NRF..."
NF_REGISTERED=$(docker compose logs free5gc-nrf 2>&1 | grep -c "Create NF Profile" 2>/dev/null | head -1 || echo "0")
NF_REGISTERED=$(echo "$NF_REGISTERED" | tr -d '\n\r ' | grep -oE '^[0-9]+' || echo "0")
NF_REGISTERED=${NF_REGISTERED:-0}
if [ "$NF_REGISTERED" -gt 0 ] 2>/dev/null; then
    echo -e "${GREEN}✓ NFs registradas no NRF ($NF_REGISTERED ocorrência(s))${NC}"
else
    echo -e "${YELLOW}⚠ Nenhum registro de NF encontrado${NC}"
fi

# Verificar associação PFCP (SMF <-> UPF)
echo "Verificando associação PFCP (SMF <-> UPF)..."
PFCP=$(docker compose logs free5gc-smf 2>&1 | grep -c "PFCP.*Accepted" 2>/dev/null | head -1 || echo "0")
PFCP=$(echo "$PFCP" | tr -d '\n\r ' | grep -oE '^[0-9]+' || echo "0")
PFCP=${PFCP:-0}
if [ "$PFCP" -gt 0 ] 2>/dev/null; then
    echo -e "${GREEN}✓ Associação PFCP detectada ($PFCP ocorrência(s))${NC}"
else
    echo -e "${YELLOW}⚠ Associação PFCP não encontrada${NC}"
fi
echo ""

# Resumo
echo "=========================================="
echo "Resumo"
echo "=========================================="
echo -e "Serviços saudáveis: ${GREEN}$HEALTHY${NC}"
if [ $UNHEALTHY -gt 0 ]; then
    echo -e "Serviços com problemas: ${RED}$UNHEALTHY${NC}"
fi
echo ""
echo "💡 Para ver logs detalhados: docker compose logs <servico>"
echo "💡 Para testar funcionalidade: ./scripts/test.sh"
echo ""

