#!/bin/bash
# Script para iniciar o RAN gNB OAI (gNB + nrUE nativos, modo RFSIM)
# Uso: ./scripts/up_gnb_oai.sh
#
# Requer: openairinterface5g compilado (./build_oai --gNB --nrUE -w SIMU -c)
# O Core deve estar rodando antes (./scripts/up_core.sh)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OAI_DIR="$PROJECT_DIR/openairinterface5g"
BUILD_DIR="$OAI_DIR/cmake_targets/ran_build/build"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"
FLEXRIC_LIB="${FLEXRIC_LIB_DIR:-$PROJECT_DIR/flexric-lib}"
[[ "$FLEXRIC_LIB" == */ ]] || FLEXRIC_LIB="${FLEXRIC_LIB}/"
E2_SM_ARGS=()
if [ -d "$FLEXRIC_LIB" ] && [ -f "$FLEXRIC_LIB/libkpm_sm.so" ]; then
    E2_SM_ARGS=(--e2_agent.sm_dir "$FLEXRIC_LIB")
fi
GNB_LOG="$LOG_DIR/gnb_oai.log"
UE_LOG="$LOG_DIR/ue_oai.log"

echo "=========================================="
echo "Iniciando RAN gNB OAI (gNB + nrUE)"
echo "=========================================="
echo ""

# Verificar se o build existe
if [ ! -f "$BUILD_DIR/nr-softmodem" ] || [ ! -f "$BUILD_DIR/nr-uesoftmodem" ]; then
    echo "ERRO: Binários não encontrados em $BUILD_DIR"
    echo "      Compile primeiro:"
    echo "        cd openairinterface5g/cmake_targets"
    echo "        ./build_oai --ninja -I"
    echo "        ./build_oai --ninja --gNB --nrUE -w SIMU -c"
    exit 1
fi

# Verificar se gnb.conf e ue.conf existem
if [ ! -f "$OAI_DIR/scripts/gnb.conf" ]; then
    echo "ERRO: gnb.conf não encontrado em $OAI_DIR/scripts/"
    exit 1
fi
if [ ! -f "$OAI_DIR/scripts/ue.conf" ]; then
    echo "ERRO: ue.conf não encontrado em $OAI_DIR/scripts/"
    exit 1
fi

mkdir -p "$LOG_DIR"

# Configurar IP no host para o gNB alcançar o AMF (obrigatório)
# A interface demo-oai é criada pelo Docker quando o Core sobe
if ! ip -4 addr show demo-oai 2>/dev/null | grep -q "192.168.70.129"; then
    echo "Configurando IP 192.168.70.129 na interface demo-oai..."
    if ip link show demo-oai >/dev/null 2>&1; then
        sudo ip addr add 192.168.70.129/24 dev demo-oai 2>/dev/null || true
    else
        echo "ERRO: Interface demo-oai não encontrada."
        echo "      Inicie o Core primeiro: ./scripts/up_core.sh"
        exit 1
    fi
fi

# Parar instâncias anteriores se existirem
pkill -f "nr-softmodem" 2>/dev/null || true
pkill -f "nr-uesoftmodem" 2>/dev/null || true
sleep 2

echo "Iniciando gNB em background..."
cd "$BUILD_DIR"
sudo nohup ./nr-softmodem -O "$OAI_DIR/scripts/gnb.conf" \
    --gNBs.[0].min_rxtxtime 6 \
    --rfsim \
    "${E2_SM_ARGS[@]}" \
    > "$GNB_LOG" 2>&1 &
GNB_PID=$!
echo "  gNB PID: $GNB_PID (logs: $GNB_LOG)"

echo "Aguardando gNB estabilizar..."
sleep 10

echo "Iniciando nrUE em background..."
sudo nohup ./nr-uesoftmodem -O "$OAI_DIR/scripts/ue.conf" \
    --rfsim -r 106 --numerology 1 --band 78 -C 3619200000 --ssb 516 \
    > "$UE_LOG" 2>&1 &
UE_PID=$!
echo "  nrUE PID: $UE_PID (logs: $UE_LOG)"

echo ""
echo "=========================================="
echo "gNB OAI iniciado com sucesso!"
echo "=========================================="
echo ""
echo "PIDs: gNB=$GNB_PID, nrUE=$UE_PID"
echo "Logs: $GNB_LOG, $UE_LOG"
echo ""
echo "Para parar: ./scripts/down_gnb_oai.sh"
echo ""
