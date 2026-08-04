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
# shellcheck source=resolve_flexric_sm_dir.sh
source "$SCRIPT_DIR/resolve_flexric_sm_dir.sh"
_resolve_flexric_sm_dir "$PROJECT_DIR"
DURATION="${XAPP_DURATION:-30}"
LOG="$LOG_DIR/xapp_kpm_lab.log"

export KPM_SST="${KPM_SST:-222}"
export KPM_SD="${KPM_SD:-123}"

E2_SM_ARGS=(--e2_agent.sm_dir "$FLEXRIC_LIB")

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

    # Reutilizar stack saudável (não matar FlexRIC/gNB a cada teste)
    if pgrep -x "nearRT-RIC" >/dev/null 2>&1 \
        && pgrep -x "nr-softmodem" >/dev/null 2>&1 \
        && grep -q "E2 SETUP RESPONSE rx" "$LOG_DIR/gnb_oai.log" 2>/dev/null; then
        echo "Stack E2 já ativo (FlexRIC + gNB) — reutilizando."
        return 0
    fi

    if pgrep -x "nearRT-RIC" >/dev/null 2>&1; then
        pkill -x "nearRT-RIC" 2>/dev/null || true
        sleep 2
    fi
    "$SCRIPT_DIR/up_flexric.sh"
    sleep 2

    "$SCRIPT_DIR/down_gnb_oai.sh" >/dev/null 2>&1 || true
    sleep 1
    "$SCRIPT_DIR/up_gnb_oai.sh"

    echo "Aguardando E2 setup + attach UE..."
    if ! wait_e2_node; then
        echo "AVISO: E2 setup não confirmado em 40s (continuando mesmo assim)"
        grep -iE 'E2 SETUP|E2-AGENT' "$LOG_DIR/gnb_oai.log" 2>/dev/null | tail -5 || true
        grep -iE 'E2 SETUP|Registered' "$LOG_DIR/nearRT-RIC.log" 2>/dev/null | tail -5 || true
    fi
    sleep 5
}

FORCE_RESTART="${FORCE_RESTART:-0}"
if [ "$FORCE_RESTART" = "1" ]; then
    "$SCRIPT_DIR/down_gnb_oai.sh" >/dev/null 2>&1 || true
    "$SCRIPT_DIR/down_flexric.sh" >/dev/null 2>&1 || true
fi
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
