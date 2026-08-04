#!/bin/bash
# Script de diagnóstico para conexão UE (OAI + UERANSIM)
# Uso: ./scripts/diagnose-ue-connection.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Diagnóstico de Conexão UE"
echo "=========================================="
echo ""

# 1. Containers
echo "1. Status dos containers"
echo "----------------------------"
for c in mysql oai-nrf oai-amf oai-smf vpp-upf ueransim; do
    if docker ps --format '{{.Names}} {{.Status}}' | grep -q "^${c} "; then
        status=$(docker ps --format '{{.Status}}' --filter "name=^${c}$")
        echo -e "  ${GREEN}✓${NC} $c: $status"
    else
        echo -e "  ${RED}✗${NC} $c: não está rodando"
    fi
done
echo ""

# 2. UE nos logs do AMF
echo "2. Estado do UE no AMF"
echo "----------------------------"
if docker ps --format '{{.Names}}' | grep -q "^oai-amf$"; then
    UE_STATE=$(docker logs oai-amf 2>&1 | grep -i "SGMM" | tail -3 || echo "")
    if [ -n "$UE_STATE" ]; then
        echo "$UE_STATE"
        if echo "$UE_STATE" | grep -q "REGISTERED"; then
            echo -e "  ${GREEN}✓ UE registrado${NC}"
        elif echo "$UE_STATE" | grep -q "REG-INITIATED"; then
            echo -e "  ${YELLOW}⚠ UE em REG-INITIATED (registro incompleto)${NC}"
        fi
    else
        echo "  (nenhum log de UE encontrado)"
    fi
else
    echo "  AMF não está rodando"
fi
echo ""

# 3. UERANSIM (UE)
echo "3. Logs do UERANSIM (últimas linhas)"
echo "----------------------------"
if docker ps --format '{{.Names}}' | grep -q "^ueransim$"; then
    docker logs ueransim 2>&1 | tail -15
else
    echo "  UERANSIM não está rodando"
fi
echo ""

# 4. Subscriber no banco
echo "4. Subscriber no banco de dados"
echo "----------------------------"
if docker ps --format '{{.Names}}' | grep -q "^mysql$"; then
    AUTH=$(docker exec mysql mysql -u test -ptest oai_db -N -e "SELECT ueid FROM AuthenticationSubscription WHERE ueid='208950000000031';" 2>/dev/null || echo "")
    MOB=$(docker exec mysql mysql -u test -ptest oai_db -N -e "SELECT ueid FROM AccessAndMobilitySubscriptionData WHERE ueid='208950000000031';" 2>/dev/null || echo "")
    if [ -n "$AUTH" ]; then
        echo -e "  ${GREEN}✓${NC} AuthenticationSubscription: 208950000000031 presente"
    else
        echo -e "  ${RED}✗${NC} AuthenticationSubscription: 208950000000031 ausente"
    fi
    if [ -n "$MOB" ]; then
        echo -e "  ${GREEN}✓${NC} AccessAndMobilitySubscriptionData: 208950000000031 presente"
    else
        echo -e "  ${RED}✗${NC} AccessAndMobilitySubscriptionData: 208950000000031 ausente"
        echo "  Para corrigir: docker exec mysql mysql -u test -ptest oai_db -e \"INSERT INTO AccessAndMobilitySubscriptionData (ueid, servingPlmnid, nssai) VALUES ('208950000000031', '20895', '{\\\"defaultSingleNssais\\\": [{\\\"sst\\\": 222, \\\"sd\\\": \\\"123\\\"}]}');\""
    fi
else
    echo "  MySQL não está rodando"
fi
echo ""

# 5. AMF - algoritmos de segurança
echo "5. Configuração AMF (UERANSIM)"
echo "----------------------------"
if grep -q "INT_ALGO_LIST" "$PROJECT_DIR/oai-cn5g-fed/docker-compose/docker-compose-basic-vpp-nrf.yaml" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} INT_ALGO_LIST e CIPH_ALGO_LIST configurados (NIA1/NIA2, NEA1/NEA2)"
else
    echo -e "  ${RED}✗${NC} INT_ALGO_LIST/CIPH_ALGO_LIST ausentes - UERANSIM requer NIA1/NIA2, NEA1/NEA2"
fi
echo ""

# 6. Resumo
echo "=========================================="
echo "Resumo"
echo "=========================================="
echo ""
echo "Se o UE está em REG-INITIATED, as correções aplicadas foram:"
echo "  1. INT_ALGO_LIST e CIPH_ALGO_LIST no AMF (docker-compose)"
echo "  2. Subscriber 208950000000031 em AccessAndMobilitySubscriptionData"
echo ""
echo "Para aplicar as correções:"
echo "  1. Reinicie o Core: ./scripts/down_core.sh && ./scripts/up_core.sh"
echo "  2. Se o banco já existia, adicione o subscriber manualmente (comando acima)"
echo "  3. Reinicie o UERANSIM: ./scripts/down_ueransim.sh && ./scripts/up_ueransim.sh"
echo ""
