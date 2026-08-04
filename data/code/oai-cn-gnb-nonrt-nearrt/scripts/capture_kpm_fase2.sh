#!/bin/bash
# Captura KPM via xApp OAI (Fase 2) por N segundos e grava log textual.
# Uso: ./scripts/capture_kpm_fase2.sh <output.log> [duration_sec]
#
# Importante: o xApp escreve o log DENTRO do container e o host só faz docker cp.
# Evita o caso em que timeout/SIGKILL no cliente `docker compose exec` deixa o
# log do host vazio enquanto o Python continua órfão no container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORAN_VENDOR="${ORAN_VENDOR_DIR:-$PROJECT_DIR/vendor/oran-sc-ric}"
ORAN_CFG="${ORAN_CFG_DIR:-$PROJECT_DIR/config/oran-ric}"

OUT_LOG="${1:?uso: $0 <output.log> [duration_sec]}"
DURATION="${2:-${KPM_CAPTURE_SEC:-30}}"
E2_NODE_ID="${E2_NODE_ID:-$("$SCRIPT_DIR/get_oran_e2_node_id.sh" 2>/dev/null || echo gnb_208_095_00000e00)}"
METRICS="${XAPP_METRICS:-DRB.PdcpSduVolumeDL,DRB.PdcpSduVolumeUL,DRB.RlcSduDelayDl,DRB.UEThpDl,DRB.UEThpUl,RRU.PrbTotDl,RRU.PrbTotUl}"
HTTP_PORT="${XAPP_HTTP_PORT:-8093}"
RMR_PORT="${XAPP_RMR_PORT:-4562}"
RETRIES="${KPM_CAPTURE_RETRIES:-2}"
CONTAINER="${XAPP_CONTAINER:-python_xapp_runner}"
REMOTE_LOG="${XAPP_REMOTE_LOG:-/tmp/kpm_capture_fase2.log}"

mkdir -p "$(dirname "$OUT_LOG")"
: > "$OUT_LOG"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "ERRO: $CONTAINER não está rodando (suba a Fase 2)." >&2
    exit 1
fi

# Tráfego leve (ping) ajuda UEThp > 0. Desligar com KPM_TRAFFIC=0 (baseline calmo).
DN_IP="${OAI_DN_IP:-192.168.73.135}"
TRAFFIC_PID=""
KPM_TRAFFIC="${KPM_TRAFFIC:-1}"
if [ "$KPM_TRAFFIC" = "1" ]; then
    for cand in oaitun_ue1 oaitun_ue0 oaitun_ue2; do
        if ip link show "$cand" >/dev/null 2>&1; then
            ue_ip=$(ip -4 addr show "$cand" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
            if [ -n "$ue_ip" ]; then
                ping -I "$ue_ip" -i 0.2 "$DN_IP" >/dev/null 2>&1 &
                TRAFFIC_PID=$!
                break
            fi
        fi
    done
else
    echo "  KPM_TRAFFIC=0 — captura sem ping auxiliar (baseline calmo)"
fi

cleanup() {
    if [ -n "${TRAFFIC_PID:-}" ]; then
        kill "$TRAFFIC_PID" 2>/dev/null || true
    fi
    "$SCRIPT_DIR/stop_xapp_oai_kpm.sh" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

attempt_capture() {
    local attempt="$1"
    "$SCRIPT_DIR/stop_xapp_oai_kpm.sh" 2>/dev/null || true
    sleep 1

    docker exec "$CONTAINER" sh -c "rm -f '$REMOTE_LOG'; : > '$REMOTE_LOG'"

    echo "Capturando KPM Fase 2 (${DURATION}s, tentativa $attempt/$RETRIES) → $OUT_LOG"
    # -d: detached no container; stdout/stderr vão para arquivo remoto (não depende do cliente).
    docker exec -d -e PYTHONUNBUFFERED=1 "$CONTAINER" \
        sh -c "python3 ./simple_xapp_oai.py \
            --e2_node_id='$E2_NODE_ID' \
            --http_server_port='$HTTP_PORT' \
            --rmr_port='$RMR_PORT' \
            --metrics='$METRICS' \
            --first-indication-timeout=15 \
            --heartbeat-interval=0 \
            >'$REMOTE_LOG' 2>&1"

    # Espera indicações + margem de subscribe
    sleep "$DURATION"

    "$SCRIPT_DIR/stop_xapp_oai_kpm.sh" 2>/dev/null || true
    sleep 0.5

    if ! docker cp "${CONTAINER}:${REMOTE_LOG}" "$OUT_LOG" 2>/dev/null; then
        echo "AVISO: falha ao copiar $REMOTE_LOG de $CONTAINER" >&2
        : > "$OUT_LOG"
        return 1
    fi

    # Exige valores de Indication (NAME: 1.23), não só a lista no "Subscribe ... metrics=['DRB.']".
    if grep -qE 'RIC Indication|DRB\.[A-Za-z0-9]+:[[:space:]]*[0-9]|RRU\.[A-Za-z0-9]+:[[:space:]]*[0-9]' \
        "$OUT_LOG" 2>/dev/null; then
        return 0
    fi
    return 1
}

ok=0
for i in $(seq 1 "$RETRIES"); do
    if attempt_capture "$i"; then
        ok=1
        break
    fi
    echo "AVISO: tentativa $i sem RIC Indication; retry..." >&2
    tail -n 20 "$OUT_LOG" >&2 || true
done

if [ "$ok" != "1" ]; then
    echo "AVISO: captura sem RIC Indication em $OUT_LOG" >&2
    echo "--- últimas linhas ---" >&2
    tail -n 30 "$OUT_LOG" >&2 || true
    if grep -q 'nenhuma RIC Indication' "$OUT_LOG" 2>/dev/null; then
        echo "Causa provável: xApp assinou E2, mas o gNB não enviou KPM (sobrecarga UL / E2)." >&2
        echo "  Tente: ./scripts/up_gnb_oai_oran.sh" >&2
        echo "  Ou:    CLOSED_LOOP_STRESS_RATE=40M ./scripts/run_closed_loop_lab.sh --live-fase2" >&2
    else
        echo "Dica: se houve Ctrl+C em xApp anterior, reinicie o gNB:" >&2
        echo "  ./scripts/up_gnb_oai_oran.sh" >&2
    fi
    exit 2
fi

echo "OK: $(grep -cE 'RIC Indication' "$OUT_LOG" || true) indications; $(grep -cE 'DRB\.[A-Za-z0-9]+:[[:space:]]*[0-9]|RRU\.[A-Za-z0-9]+:[[:space:]]*[0-9]' "$OUT_LOG" || true) linhas de métrica"
