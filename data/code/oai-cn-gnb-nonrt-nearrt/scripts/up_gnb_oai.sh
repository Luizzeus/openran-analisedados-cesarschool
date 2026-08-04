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
# shellcheck source=resolve_flexric_sm_dir.sh
source "$SCRIPT_DIR/resolve_flexric_sm_dir.sh"
_resolve_flexric_sm_dir "$PROJECT_DIR"
E2_SM_ARGS=(--e2_agent.sm_dir "$FLEXRIC_LIB")
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

if ! pgrep -x "nearRT-RIC" >/dev/null 2>&1; then
    echo "AVISO: nearRT-RIC (FlexRIC) não está em execução."
    echo "       E2 SETUP pode falhar. Inicie: ./scripts/up_flexric.sh"
fi

# Sanity: porta passada a e2_init_agent (mov $imm,%esi) deve ser 36421, não 36422.
# Atenção: só o printf pode já estar em 36421 enquanto o connect ainda usa 36422.
if ! python3 - "$BUILD_DIR/nr-softmodem" <<'PY'
import sys
from pathlib import Path
b = Path(sys.argv[1]).read_bytes()
# Região aproximada de init_agent_api (PIE VA==file offset neste binário)
reg = b[0xCEE810:0xCEEC80]
n22_esi = reg.count(bytes.fromhex("be468e0000"))  # mov $36422,%esi → e2_init_agent
n21_esi = reg.count(bytes.fromhex("be458e0000"))  # mov $36421,%esi
if n22_esi > 0 or n21_esi < 1:
    sys.exit(1)
sys.exit(0)
PY
then
    echo "ERRO: nr-softmodem ainda conecta E2 na porta 36422 (build O-RAN SC sobrescreveu a Fase 1)."
    echo "      Restaure com: ./scripts/build_e2.sh"
    echo "      (build_e2_oran_sc.sh agora preserva o binário FlexRIC automaticamente)"
    exit 1
fi

: > "$GNB_LOG"
echo "Iniciando gNB em background (E2 → FlexRIC :36421)..."
cd "$BUILD_DIR"
sudo nohup ./nr-softmodem -O "$OAI_DIR/scripts/gnb.conf" \
    --gNBs.[0].min_rxtxtime 6 \
    --rfsim \
    "${E2_SM_ARGS[@]}" \
    > "$GNB_LOG" 2>&1 &
GNB_PID=$!
echo "  gNB PID: $GNB_PID (logs: $GNB_LOG)"

echo "Aguardando gNB / E2 SETUP..."
E2_OK=0
for _ in $(seq 1 30); do
    if ! kill -0 "$GNB_PID" 2>/dev/null; then
        echo "ERRO: gNB abortou ao iniciar. Ver: $GNB_LOG"
        tail -30 "$GNB_LOG" 2>/dev/null || true
        exit 1
    fi
    if grep -q 'E2 SETUP RESPONSE rx' "$GNB_LOG" 2>/dev/null; then
        echo "  E2 SETUP RESPONSE rx — OK"
        E2_OK=1
        break
    fi
    if grep -qE 'Assertion `|E2 SETUP FAILURE' "$GNB_LOG" 2>/dev/null; then
        echo "ERRO: falha no agente E2. Ver: $GNB_LOG"
        grep -E 'Assertion `|E2 SETUP|PORT =' "$GNB_LOG" | tail -20 || true
        exit 1
    fi
    sleep 1
done
if [ "$E2_OK" != "1" ]; then
    echo "AVISO: E2 SETUP ainda não confirmado (FlexRIC / porta 36421?)."
    grep -E 'E2 SETUP|PORT =|nearRT-RIC' "$GNB_LOG" 2>/dev/null | tail -10 || true
fi

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
