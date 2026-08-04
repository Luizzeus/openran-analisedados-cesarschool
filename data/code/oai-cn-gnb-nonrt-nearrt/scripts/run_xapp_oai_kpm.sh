#!/bin/bash
# xApp KPM para gNB OAI + nearRT O-RAN SC (Style 4, S-NSSAI, RMR :4562).
# Uso: ./scripts/run_xapp_oai_kpm.sh [e2_node_id]
#
# Pré-requisitos: ./scripts/up_oran_ric.sh && ./scripts/up_gnb_oai_oran.sh
#
# Variáveis:
#   KPM_TRAFFIC=1   (padrão) ping contínuo UE→DN para métricas UEThp > 0
#   OAI_DN_IP=192.168.73.135
#   XAPP_UNSUBSCRIBE_ON_EXIT=0 (padrão) preserva gNB OAI ao sair
#   XAPP_FIRST_INDICATION_TIMEOUT=15
#   XAPP_HEARTBEAT_INTERVAL=30

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORAN_VENDOR="${ORAN_VENDOR_DIR:-$PROJECT_DIR/vendor/oran-sc-ric}"
ORAN_CFG="${ORAN_CFG_DIR:-$PROJECT_DIR/config/oran-ric}"

E2_NODE_ID="${1:-$( "$SCRIPT_DIR/get_oran_e2_node_id.sh" 2>/dev/null || echo gnb_208_095_00000e00 )}"
HTTP_PORT="${XAPP_HTTP_PORT:-8093}"
RMR_PORT="${XAPP_RMR_PORT:-4562}"
METRICS="${XAPP_METRICS:-DRB.UEThpDl,DRB.UEThpUl}"
KPM_TRAFFIC="${KPM_TRAFFIC:-1}"
DN_IP="${OAI_DN_IP:-192.168.73.135}"
UNSUBSCRIBE_ON_EXIT="${XAPP_UNSUBSCRIBE_ON_EXIT:-0}"
FIRST_INDICATION_TIMEOUT="${XAPP_FIRST_INDICATION_TIMEOUT:-15}"
HEARTBEAT_INTERVAL="${XAPP_HEARTBEAT_INTERVAL:-30}"

TRAFFIC_PID=""

cleanup() {
    if [ -n "$TRAFFIC_PID" ]; then
        kill "$TRAFFIC_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

start_ue_traffic() {
    local ue_ip="" iface=""
    for cand in oaitun_ue1 oaitun_ue0 oaitun_ue2; do
        if ip link show "$cand" >/dev/null 2>&1; then
            ue_ip=$(ip -4 addr show "$cand" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
            if [ -n "$ue_ip" ]; then
                iface="$cand"
                break
            fi
        fi
    done
    if [ -z "$ue_ip" ]; then
        ue_ip=$(ip -4 addr show 2>/dev/null | awk '/inet 12\.1\.1\./ {print $2}' | cut -d/ -f1 | head -1)
        iface="(auto)"
    fi
    if [ -z "$ue_ip" ]; then
        echo "AVISO: sem interface oaitun_ue — UEThp pode ficar 0 (sem tráfego IP na DRB)."
        echo "        Confirme PDU session: grep -i pdu $PROJECT_DIR/logs/ue_oai_oran.log | tail -3"
        return 1
    fi
    if ! ping -c 1 -W 2 -I "$ue_ip" "$DN_IP" >/dev/null 2>&1; then
        echo "AVISO: ping $DN_IP via $ue_ip falhou — métricas podem ser 0."
        return 1
    fi
    echo "Tráfego UE: $iface $ue_ip → ping $DN_IP (KPM_TRAFFIC=1)"
    ping -I "$ue_ip" -i 0.2 "$DN_IP" >/dev/null 2>&1 &
    TRAFFIC_PID=$!
}

compose() {
    docker compose \
        -f "$ORAN_VENDOR/docker-compose.yml" \
        -f "$ORAN_CFG/docker-compose.override.yml" \
        --env-file "$ORAN_VENDOR/.env" \
        --env-file "$ORAN_CFG/.env" \
        "$@"
}

# Libera portas ocupadas por execs anteriores (docker compose exec sem TTY deixa órfãos).
"$SCRIPT_DIR/stop_xapp_oai_kpm.sh"

if [ "$KPM_TRAFFIC" = "1" ]; then
    start_ue_traffic || true
fi

extra_args=()
if [ "$UNSUBSCRIBE_ON_EXIT" = "1" ]; then
    extra_args+=(--unsubscribe-on-exit)
fi

compose exec -e PYTHONUNBUFFERED=1 python_xapp_runner \
    python3 ./simple_xapp_oai.py \
    --e2_node_id="$E2_NODE_ID" \
    --http_server_port="$HTTP_PORT" \
    --rmr_port="$RMR_PORT" \
    --metrics="$METRICS" \
    --first-indication-timeout="$FIRST_INDICATION_TIMEOUT" \
    --heartbeat-interval="$HEARTBEAT_INTERVAL" \
    "${extra_args[@]}"
