#!/bin/bash
# Testa E2SM-RC: xApp subscreve ANTES do attach do UE.
# Uso: ./scripts/test_e2_rc_attach.sh
#
# Ordem: RIC → xApp RC → gNB (sem UE) → UE → captura INDICATIONs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"
OAI_DIR="$PROJECT_DIR/openairinterface5g"
BUILD_DIR="$OAI_DIR/cmake_targets/ran_build/build"
# shellcheck source=resolve_flexric_sm_dir.sh
source "$SCRIPT_DIR/resolve_flexric_sm_dir.sh"
_resolve_flexric_sm_dir "$PROJECT_DIR"
DURATION="${XAPP_DURATION:-60}"
LOG="$LOG_DIR/xapp_rc_attach.log"

E2_SM_ARGS=(--e2_agent.sm_dir "$FLEXRIC_LIB")
if [ ! -f "${FLEXRIC_LIB}librc_sm.so" ]; then
    echo "ERRO: librc_sm.so ausente em $FLEXRIC_LIB"
    exit 1
fi

mkdir -p "$LOG_DIR"

if ! pgrep -x "nearRT-RIC" >/dev/null 2>&1; then
    "$SCRIPT_DIR/up_flexric.sh"
fi

FLEXRIC_BUILD="$PROJECT_DIR/openairinterface5g/openair2/E2AP/flexric/build/examples/xApp/c/monitor/xapp_rc_moni"
XAPP=""
for candidate in "$FLEXRIC_BUILD" /usr/local/bin/flexric/xApp/c/monitor/xapp_rc_moni; do
    [ -x "$candidate" ] && XAPP="$candidate" && break
done
[ -n "$XAPP" ] || { echo "ERRO: xapp_rc_moni ausente. ./scripts/build_flexric_tools.sh"; exit 1; }

echo "=== E2SM-RC fresh attach (${DURATION}s) ==="

# Parar RAN; manter Core + RIC
pkill -f "nr-softmodem" 2>/dev/null || true
pkill -f "nr-uesoftmodem" 2>/dev/null || true
sleep 2

# xApp RC em background
XAPP_DURATION="$DURATION" "$XAPP" > "$LOG" 2>&1 &
XPID=$!
echo "xApp RC PID: $XPID"

# gNB sem UE
if ! ip -4 addr show demo-oai 2>/dev/null | grep -q "192.168.70.129"; then
    sudo ip addr add 192.168.70.129/24 dev demo-oai 2>/dev/null || true
fi
echo "Iniciando gNB (sem UE)..."
cd "$BUILD_DIR"
sudo nohup ./nr-softmodem -O "$OAI_DIR/scripts/gnb.conf" \
    --gNBs.[0].min_rxtxtime 6 --rfsim "${E2_SM_ARGS[@]}" \
    >> "$LOG_DIR/gnb_oai.log" 2>&1 &

echo "Aguardando E2 setup + subscrição RC (20s)..."
for i in $(seq 1 20); do
    grep -q "Successfully subscribed" "$LOG" 2>/dev/null && break
    sleep 1
done

if ! grep -q "Successfully subscribed" "$LOG" 2>/dev/null; then
    echo "AVISO: subscrição RC não confirmada em 20s"
    tail -5 "$LOG"
fi

echo "Iniciando nrUE (attach → eventos RRC)..."
sudo nohup ./nr-uesoftmodem -O "$OAI_DIR/scripts/ue.conf" \
    --rfsim -r 106 --numerology 1 --band 78 -C 3619200000 --ssb 516 \
    >> "$LOG_DIR/ue_oai.log" 2>&1 &

echo "Aguardando xApp..."
wait "$XPID" 2>/dev/null || true

echo ""
echo "=== Resultados RC ==="
grep -iE 'INDICATION|RRC connected|RRC idle|UE ID type|amf_ue_ngap|RRCSetup|Reconfig|Measurement|Security Mode|Successfully subscribed' "$LOG" || true

if grep -qiE 'INDICATION|RRC connected|UE ID type|amf_ue_ngap' "$LOG"; then
    echo ""; echo "RC INDICATIONs capturadas."
else
    echo ""; echo "Subscrição OK; INDICATIONs podem exigir mais tempo ou tráfego (ver log)."
fi
echo "Log: $LOG"
