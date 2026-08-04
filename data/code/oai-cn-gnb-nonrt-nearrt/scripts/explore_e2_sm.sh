#!/bin/bash
# Explora Service Models E2 no OAI: RC, KPM, custom layers, combinações.
# Uso: ./scripts/explore_e2_sm.sh [suite]
#
# Suites:
#   quick   - cust + rc (padrão, ~1 min)
#   rc      - E2SM-RC aprofundado (monitor + PoC KPM+RC)
#   oran    - KPM + RC via xapp_oran_moni
#   layers  - MAC/RLC/PDCP/GTP detalhado
#   full    - todas as suites acima
#
# Pré-requisitos: ./scripts/up_e2_lab.sh (Core + RIC + gNB + UE)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"
FLEXRIC_BUILD="$PROJECT_DIR/openairinterface5g/openair2/E2AP/flexric/build/examples/xApp/c"
DURATION="${XAPP_DURATION:-25}"
SUITE="${1:-quick}"

mkdir -p "$LOG_DIR"

ensure_lab() {
    if ! pgrep -x "nearRT-RIC" >/dev/null 2>&1; then
        echo "Iniciando nearRT-RIC..."
        "$SCRIPT_DIR/up_flexric.sh"
    fi
    if ! pgrep -f "nr-softmodem" >/dev/null 2>&1; then
        echo "ERRO: gNB não está rodando. Execute: ./scripts/up_e2_lab.sh"
        exit 1
    fi
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^oai-amf$'; then
        echo "AVISO: Core OAI não detectado. UE pode não registrar."
    fi
}

build_xapps_if_needed() {
    local rc="$FLEXRIC_BUILD/monitor/xapp_rc_moni"
    if [ -x "$rc" ]; then
        export FLEXRIC_XAPP_DIR="$FLEXRIC_BUILD/monitor"
        return 0
    fi
    echo "Compilando xApps FlexRIC (primeira vez, ~1 min)..."
    local flexric="$PROJECT_DIR/openairinterface5g/openair2/E2AP/flexric"
    mkdir -p "$flexric/build"
    (cd "$flexric/build" && cmake .. -GNinja -DE2AP_VERSION=E2AP_V2 -DKPM_VERSION=KPM_V2_03 >/dev/null \
        && ninja xapp_rc_moni xapp_kpm_moni xapp_kpm_rc xapp_gtp_mac_rlc_pdcp_moni)
    export FLEXRIC_XAPP_DIR="$FLEXRIC_BUILD/monitor"
}

summarize_log() {
    local log="$1"
    local label="$2"
    echo ""
    echo "--- Resumo: $label ---"
    if [ ! -f "$log" ]; then
        echo "  (sem log)"
        return
    fi
    local ind rc_state rrc_msg ue_id success fail
    ind=$(grep -ciE 'RIC INDICATION|ric indication|indication received' "$log" 2>/dev/null || echo 0)
    rc_state=$(grep -ciE 'RRC connected|RRC idle|RRC inactive|RRC State' "$log" 2>/dev/null || echo 0)
    rrc_msg=$(grep -ciE 'RRCReconfiguration|RRC Setup|Measurement Report|Security Mode' "$log" 2>/dev/null || echo 0)
    ue_id=$(grep -ciE 'UE ID type|amf_ue_ngap_id|ran_ue_id' "$log" 2>/dev/null || echo 0)
    success=$(grep -ci 'SUCCESS' "$log" 2>/dev/null || echo 0)
    fail=$(grep -ciE 'error|failed|FAIL' "$log" 2>/dev/null || echo 0)
    echo "  INDICATIONs: $ind | RRC state events: $rc_state | RRC msgs: $rrc_msg | UE ID logs: $ue_id"
    grep -iE 'Registered node|ran func id|Connected E2 nodes|Test xApp run' "$log" 2>/dev/null | tail -5 | sed 's/^/  /'
    if [ "$success" -gt 0 ]; then
        echo "  Status: OK"
    elif [ "$ind" -gt 0 ] || [ "$rc_state" -gt 0 ] || [ "$ue_id" -gt 0 ]; then
        echo "  Status: parcial (eventos E2 detectados)"
    else
        echo "  Status: sem INDICATIONs visíveis (ver $log)"
    fi
}

run_sm() {
    local sm="$1"
    echo ""
    echo "=========================================="
    echo "Testando SM: $sm (${DURATION}s)"
    echo "=========================================="
    XAPP_DURATION="$DURATION" "$SCRIPT_DIR/test_e2_sm.sh" "$sm"
    summarize_log "$LOG_DIR/xapp_${sm//\//_}.log" "$sm" 2>/dev/null || true
    # test_e2_sm names logs by xapp binary name; map common ones
    for f in "$LOG_DIR"/xapp_*.log; do
        [ -f "$f" ] || continue
        if [ "$(find "$LOG_DIR" -name 'xapp_*.log' -newer "$LOG_DIR/.explore_marker" 2>/dev/null | wc -l)" -gt 0 ]; then
            break
        fi
    done
}

ensure_lab
build_xapps_if_needed
touch "$LOG_DIR/.explore_marker"

case "$SUITE" in
    quick)
        XAPP_DURATION="$DURATION" "$SCRIPT_DIR/test_e2_sm.sh" cust
        summarize_log "$LOG_DIR/xapp_cust_moni.log" "custom (MAC/RLC/PDCP/GTP)"
        XAPP_DURATION="$DURATION" "$SCRIPT_DIR/test_e2_sm.sh" rc
        summarize_log "$LOG_DIR/xapp_rc_moni.log" "E2SM-RC"
        ;;
    rc)
        echo "E2SM-RC: REPORT Style 1 (RRC message copy, UE ID)"
        echo "         REPORT Style 4 (UE RRC state change)"
        echo "         CONTROL Style 1 (QoS flow / DRB PoC via kpm_rc)"
        XAPP_DURATION="$DURATION" "$SCRIPT_DIR/test_e2_sm.sh" rc
        summarize_log "$LOG_DIR/xapp_rc_moni.log" "xapp_rc_moni"
        echo ""
        echo "PoC KPM + RC Control (xapp_kpm_rc)..."
        XAPP_DURATION="$DURATION" "$SCRIPT_DIR/test_e2_sm.sh" kpm_rc
        summarize_log "$LOG_DIR/xapp_kpm_rc.log" "xapp_kpm_rc"
        echo ""
        echo "RC com (re)attach sincronizado..."
        "$SCRIPT_DIR/test_e2_rc_attach.sh"
        summarize_log "$LOG_DIR/xapp_rc_attach.log" "RC attach test"
        ;;
    oran)
        XAPP_DURATION="$DURATION" "$SCRIPT_DIR/test_e2_sm.sh" oran
        summarize_log "$LOG_DIR/xapp_oran_moni.log" "O-RAN KPM+RC (SST=1 upstream)"
        ;;
    kpm)
        echo "=== E2SM-KPM (slice lab 222/123) ==="
        "$SCRIPT_DIR/test_e2_kpm.sh"
        summarize_log "$LOG_DIR/xapp_kpm_lab.log" "KPM lab"
        ;;
    layers)
        XAPP_DURATION="$DURATION" "$SCRIPT_DIR/test_e2_sm.sh" gtp
        summarize_log "$LOG_DIR/xapp_gtp_mac_rlc_pdcp_moni.log" "L2/L3 layers"
        XAPP_DURATION="$DURATION" "$SCRIPT_DIR/test_e2_sm.sh" cust
        summarize_log "$LOG_DIR/xapp_cust_moni.log" "custom aggregate"
        ;;
    full)
        "$0" rc
        "$0" oran
        "$0" layers
        XAPP_DURATION=15 "$SCRIPT_DIR/test_e2_sm.sh" all
        summarize_log "$LOG_DIR/xapp_all_moni.log" "all SMs"
        ;;
    *)
        echo "Uso: $0 [quick|rc|kpm|oran|layers|full]"
        exit 1
        ;;
esac

echo ""
echo "Exploração concluída. Logs em: $LOG_DIR/"
echo "Guia detalhado: docs/E2_SERVICE_MODELS.md"
