#!/bin/bash
# Inicia gNB + nrUE com E2 agent O-RAN SC (porta 36422).
# Uso: ./scripts/up_gnb_oai_oran.sh
# Requer: ./scripts/build_e2_oran_sc.sh e ./scripts/up_oran_ric.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=resolve_flexric_sm_dir.sh
source "$SCRIPT_DIR/resolve_flexric_sm_dir.sh"
_resolve_flexric_sm_dir "$PROJECT_DIR"

OAI_DIR="$PROJECT_DIR/openairinterface5g"
ORAN_BIN_DIR="$OAI_DIR/cmake_targets/ran_build/build-oran-sc"
BUILD_DIR="$ORAN_BIN_DIR"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"
GNB_BIN="$BUILD_DIR/nr-softmodem-oran-sc"
UE_BIN="$BUILD_DIR/nr-uesoftmodem"
GNB_LOG="$LOG_DIR/gnb_oai_oran.log"
UE_LOG="$LOG_DIR/ue_oai_oran.log"
E2_PORT="${ORAN_E2_HOST_PORT:-36422}"
E2_ADDR="${ORAN_E2_ADDR:-10.0.2.10}"

E2_SM_ARGS=(--e2_agent.sm_dir "$FLEXRIC_LIB")

# Linux trunca /proc/<pid>/comm a 15 chars → pgrep -x nr-softmodem-oran-sc
# nunca casa (vira nr-softmodem-or). Usar cmdline, excluindo este script.
_gnb_running() {
    pgrep -f '[.]/nr-softmodem-oran-sc -O' >/dev/null 2>&1
}

echo "=========================================="
echo "gNB OAI + nrUE — E2 O-RAN SC (:$E2_PORT)"
echo "=========================================="
echo "  sm_dir: $FLEXRIC_LIB (${#FLEXRIC_LIB} chars, limite E2=128)"

if [ ! -x "$GNB_BIN" ]; then
    echo "ERRO: $GNB_BIN não encontrado. Execute: ./scripts/build_e2_oran_sc.sh"
    exit 1
fi

if [ ! -x "$UE_BIN" ]; then
    echo "ERRO: $UE_BIN não encontrado. Execute: ./scripts/build_e2_oran_sc.sh"
    exit 1
fi

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q ric_e2term; then
    echo "ERRO: ric_e2term não está rodando. Execute: ./scripts/up_oran_ric.sh"
    exit 1
fi

if pgrep -x "nearRT-RIC" >/dev/null 2>&1; then
    echo "ERRO: FlexRIC em execução — pare com ./scripts/down_flexric.sh"
    exit 1
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^ueransim$'; then
    echo "Nota: ueransim ativo (OK no AMF — gNB/IMSI distintos do OAI)."
    echo "      KPMs E2 vêm só do gNB OAI + nrUE (oaitun), não do tráfego UERANSIM."
fi

if ! ip -4 addr show demo-oai 2>/dev/null | grep -q "192.168.70.129"; then
    if ip link show demo-oai >/dev/null 2>&1; then
        sudo ip addr add 192.168.70.129/24 dev demo-oai 2>/dev/null || true
    else
        echo "ERRO: Core não iniciado. Execute: ./scripts/up_core.sh"
        exit 1
    fi
fi

mkdir -p "$LOG_DIR"
E2_COOLDOWN="${E2_RECONNECT_WAIT:-60}"
E2_STAMP="$LOG_DIR/.e2_last_disconnect"

# O-RAN SC e2term: time-to-wait ~60s após desconexão. Reconnect antes disso
# → E2 SETUP FAILURE → assert no decoder OAI (gNB aborta).
_wait_e2_cooldown() {
    local now elapsed wait_s
    now=$(date +%s)
    if [ ! -f "$E2_STAMP" ]; then
        return 0
    fi
    elapsed=$((now - $(cat "$E2_STAMP" 2>/dev/null || echo 0)))
    if [ "$elapsed" -lt "$E2_COOLDOWN" ]; then
        wait_s=$((E2_COOLDOWN - elapsed))
        echo "Aguardando ${wait_s}s (RIC E2 time-to-wait ${E2_COOLDOWN}s após desconexão)..."
        sleep "$wait_s"
    fi
}

if _gnb_running; then
    date +%s > "$E2_STAMP"
fi

# killall: nome longo também trunca — cobrir forma curta (15 chars)
sudo killall -9 nr-softmodem-or nr-softmodem-oran-sc nr-softmodem nr-uesoftmodem 2>/dev/null || true
sleep 2
_wait_e2_cooldown

cd "$BUILD_DIR"
: > "$GNB_LOG"
: > "$UE_LOG"
echo "Iniciando gNB (E2 → $E2_ADDR:$E2_PORT)..."
# disown evita que "Aborted" do job em background derrube o script (set -e)
sudo nohup ./nr-softmodem-oran-sc -O "$OAI_DIR/scripts/gnb.conf" \
    --gNBs.[0].min_rxtxtime 6 \
    --rfsim \
    --e2_agent.near_ric_ip_addr "$E2_ADDR" \
    "${E2_SM_ARGS[@]}" \
    > "$GNB_LOG" 2>&1 &
disown $! 2>/dev/null || true
echo "  log: $GNB_LOG"

# Aguardar estabilização e detectar abort do agente E2 (sm_dir inválido, etc.)
for _ in $(seq 1 20); do
    sleep 1
    if ! _gnb_running; then
        echo "ERRO: gNB abortou. Últimas linhas do log:"
        tail -n 40 "$GNB_LOG" || true
        if grep -q "Error opening the input directory" "$GNB_LOG" 2>/dev/null; then
            echo ""
            echo "Causa: sm_dir inacessível ao root ou truncado (>=128). Path: $FLEXRIC_LIB"
            echo "Dica: ./scripts/resolve_flexric_sm_dir.sh  # deve apontar para /var/tmp/oai-flexric-lib/"
        elif grep -qE 'e2ap_dec_setup_failure|SETUP FAILURE' "$GNB_LOG" 2>/dev/null; then
            date +%s > "$E2_STAMP"
            echo ""
            echo "Causa: E2 SETUP FAILURE do nearRT (time-to-wait ~${E2_COOLDOWN}s após desconexão)."
            echo "Dica: aguarde ${E2_COOLDOWN}s e rode: ./scripts/up_gnb_oai_oran.sh"
        fi
        exit 1
    fi
    if grep -q "E2 SETUP RESPONSE rx" "$GNB_LOG" 2>/dev/null; then
        break
    fi
done

if ! _gnb_running; then
    echo "ERRO: gNB não está em execução."
    exit 1
fi

if grep -q "E2 SETUP RESPONSE rx" "$GNB_LOG" 2>/dev/null; then
    echo "  E2 SETUP RESPONSE rx — OK"
elif grep -qE 'NGSetupResponse' "$GNB_LOG" 2>/dev/null; then
    echo "AVISO: NGSetup OK, mas E2 SETUP ainda não confirmado (RIC/e2term?)."
else
    echo "AVISO: ainda sem NGSetupResponse no log — conferir AMF/core."
fi

echo "Iniciando nrUE..."
sudo nohup ./nr-uesoftmodem -O "$OAI_DIR/scripts/ue.conf" \
    --rfsim -r 106 --numerology 1 --band 78 -C 3619200000 --ssb 516 \
    > "$UE_LOG" 2>&1 &
disown $! 2>/dev/null || true
echo "  log: $UE_LOG"

echo ""
echo "Verificar E2 SETUP:"
echo "  grep -iE 'E2|RIC|setup|Opening plugin' $GNB_LOG | tail -20"
