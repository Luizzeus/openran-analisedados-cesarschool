#!/bin/bash
# Testa E2SM-KPM com slice do laboratório (SST=222, SD=123).
# Uso: ./scripts/test_e2_kpm.sh
#
# Variáveis:
#   KPM_SST=222  KPM_SD=123   (padrão, alinhado ao Core/AMF)
#   KPM_SD=any   filtro só por SST (SD wildcard 0xffffff no agente)
#   XAPP_DURATION=30
#   KPM_TRAFFIC=1  gera ping durante o teste (melhora métricas throughput)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OAI_DIR="$PROJECT_DIR/openairinterface5g"
BUILD_DIR="$OAI_DIR/cmake_targets/ran_build/build"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"
FLEXRIC_LIB="${FLEXRIC_LIB_DIR:-$PROJECT_DIR/flexric-lib}"
[[ "$FLEXRIC_LIB" == */ ]] || FLEXRIC_LIB="${FLEXRIC_LIB}/"
DURATION="${XAPP_DURATION:-30}"
LOG="$LOG_DIR/xapp_kpm_lab.log"

export KPM_SST="${KPM_SST:-222}"
export KPM_SD="${KPM_SD:-123}"

E2_SM_ARGS=()
if [ -d "$FLEXRIC_LIB" ] && [ -f "$FLEXRIC_LIB/libkpm_sm.so" ]; then
    E2_SM_ARGS=(--e2_agent.sm_dir "$FLEXRIC_LIB")
fi

mkdir -p "$LOG_DIR"

kill_stale_xapps() {
    pkill -f "/xapp_" 2>/dev/null || true
    pkill -f "xapp_kpm_moni" 2>/dev/null || true
    pkill -f "xapp_rc_moni" 2>/dev/null || true
    pkill -f "xapp_oran_moni" 2>/dev/null || true
    sleep 1
}

wait_e2_node() {
    local gnb_log="$LOG_DIR/gnb_oai.log"
    for _ in $(seq 1 40); do
        if grep -q "E2 SETUP RESPONSE rx" "$gnb_log" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

ensure_e2_stack() {
    kill_stale_xapps

    if [ ! -f "$FLEXRIC_LIB/libkpm_sm.so" ]; then
        echo "Compilando/sincronizando SMs FlexRIC (dev)..."
        "$SCRIPT_DIR/build_flexric_tools.sh" >/dev/null
    fi

    if pgrep -x "nearRT-RIC" >/dev/null 2>&1; then
        pkill -x "nearRT-RIC" 2>/dev/null || true
        sleep 2
    fi
    "$SCRIPT_DIR/up_flexric.sh"
    sleep 2

    pkill -f "nr-softmodem" 2>/dev/null || true
    pkill -f "nr-uesoftmodem" 2>/dev/null || true
    sleep 2

    if ! ip -4 addr show demo-oai 2>/dev/null | grep -q "192.168.70.129"; then
        sudo ip addr add 192.168.70.129/24 dev demo-oai 2>/dev/null || true
    fi

    echo "Iniciando gNB+UE (SMs: ${FLEXRIC_LIB})..."
    cd "$BUILD_DIR"
    sudo nohup ./nr-softmodem -O "$OAI_DIR/scripts/gnb.conf" \
        --gNBs.[0].min_rxtxtime 6 --rfsim "${E2_SM_ARGS[@]}" \
        >> "$LOG_DIR/gnb_oai.log" 2>&1 &
    sleep 12
    sudo nohup ./nr-uesoftmodem -O "$OAI_DIR/scripts/ue.conf" \
        --rfsim -r 106 --numerology 1 --band 78 -C 3619200000 --ssb 516 \
        >> "$LOG_DIR/ue_oai.log" 2>&1 &

    echo "Aguardando E2 setup + attach UE..."
    if ! wait_e2_node; then
        echo "AVISO: E2 setup não confirmado em 40s (continuando mesmo assim)"
        grep -iE 'E2 SETUP|E2-AGENT' "$LOG_DIR/gnb_oai.log" 2>/dev/null | tail -5 || true
        grep -iE 'E2 SETUP|Registered' "$LOG_DIR/nearRT-RIC.log" 2>/dev/null | tail -5 || true
    fi
    sleep 5
}

ensure_e2_stack

FLEXRIC_BUILD="$PROJECT_DIR/openairinterface5g/openair2/E2AP/flexric/build/examples/xApp/c/monitor/xapp_kpm_moni"
XAPP=""
for candidate in "$FLEXRIC_BUILD" /usr/local/bin/flexric/xApp/c/monitor/xapp_kpm_moni; do
    [ -x "$candidate" ] && XAPP="$candidate" && break
done

if [ ! -x "$XAPP" ]; then
    echo "Compilando xapp_kpm_moni (slice lab)..."
    "$SCRIPT_DIR/build_flexric_tools.sh" >/dev/null
    XAPP="$FLEXRIC_BUILD"
fi

echo "=== E2SM-KPM (SST=$KPM_SST SD=$KPM_SD, ${DURATION}s) ==="
echo "Log: $LOG"
: > "$LOG"

TRAFFIC_PID=""
if [ "${KPM_TRAFFIC:-1}" = "1" ]; then
    UE_IP=$(ip -4 addr show 2>/dev/null | grep -oP 'inet \K12\.1\.1\.\d+' | head -1 || true)
    DN_IP="${OAI_DN_IP:-192.168.73.135}"
    if [ -n "$UE_IP" ] && ping -c 1 -W 2 "$DN_IP" >/dev/null 2>&1; then
        echo "Gerando tráfego: ping $DN_IP via $UE_IP"
        ping -I "$UE_IP" -i 0.2 "$DN_IP" >/dev/null 2>&1 &
        TRAFFIC_PID=$!
    else
        echo "AVISO: sem túnel UE (oaitun) ou DN inacessível; métricas podem ser zero."
    fi
fi

kill_stale_xapps

XAPP_DURATION="$DURATION" KPM_SST="$KPM_SST" KPM_SD="$KPM_SD" \
    timeout "$((DURATION + 45))" "$XAPP" > "$LOG" 2>&1 &
XPID=$!
wait "$XPID" 2>/dev/null || true

[ -n "$TRAFFIC_PID" ] && kill "$TRAFFIC_PID" 2>/dev/null || true

echo ""
echo "=== Resultados KPM ==="
grep -iE 'Connected E2 nodes|Successfully subscribed|INDICATION|DRB\.|RRU\.|PrbTot|UEThp|PdcpSdu|Condition NSSAI' "$LOG" | head -40 || true

if grep -qiE 'INDICATION|DRB\.|RRU\.|PrbTot|UEThp|PdcpSdu' "$LOG"; then
    echo ""
    echo "KPM INDICATIONs recebidas."
elif grep -qi "Successfully subscribed" "$LOG"; then
    echo ""
    echo "Subscrição KPM OK; sem métricas no período (aumente XAPP_DURATION ou KPM_TRAFFIC=1)."
else
    echo ""
    echo "Sem métricas KPM visíveis. Verifique:"
    echo "  - flexric-lib/ com libkpm_sm.so do submodule (não /usr/local)"
    echo "  - UE com sessão PDU slice $KPM_SST/$KPM_SD"
    echo "  - grep 'E2SM-KPM\\|E2 SETUP' logs/gnb_oai.log logs/nearRT-RIC.log"
fi
echo "Log completo: $LOG"
