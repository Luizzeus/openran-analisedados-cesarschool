#!/bin/bash
# UE stress test with nearRT xApp KPM observation and nonRT snapshots.
# Usage:
#   ./scripts/stress_ue_observe_apps.sh
#
# Common variables:
#   UE_SOURCE=nrue|ueransim      default: nrue
#   STRESS_DURATION=45           load phase duration in seconds
#   BASELINE_DURATION=20         light baseline phase duration
#   RECOVERY_DURATION=20         light recovery phase duration
#   STRESS_MODE=tcp|udp          default: tcp
#   PARALLEL_STREAMS=4           iperf3 parallel streams for TCP/UDP
#   UDP_RATE=100M                iperf3 UDP target rate
#   KPM_SST=222 KPM_SD=123       slice filter used by xapp_kpm_moni
#   NONRT_SEED=0|1               create sample nonRT policy data before test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$LOG_DIR/ue_stress_$RUN_ID"

DN_CONTAINER="${DN_CONTAINER:-oai-ext-dn}"
UE_CONTAINER="${UE_CONTAINER:-ueransim}"
DN_IP="${OAI_DN_IP:-192.168.73.135}"
UE_SOURCE="${UE_SOURCE:-nrue}"

BASELINE_DURATION="${BASELINE_DURATION:-20}"
STRESS_DURATION="${STRESS_DURATION:-45}"
RECOVERY_DURATION="${RECOVERY_DURATION:-20}"
STRESS_MODE="${STRESS_MODE:-tcp}"
PARALLEL_STREAMS="${PARALLEL_STREAMS:-4}"
UDP_RATE="${UDP_RATE:-100M}"

KPM_SST="${KPM_SST:-222}"
KPM_SD="${KPM_SD:-123}"
NONRT_SEED="${NONRT_SEED:-0}"

PMS_PORT="${NONRT_PMS_HTTP_PORT:-8081}"
GW_PORT="${NONRT_GATEWAY_PORT:-9090}"
CP_PORT="${NONRT_CONTROL_PANEL_PORT:-8181}"
OSC_PORT="${NONRT_OSC_PORT:-30001}"
STD_V2_PORT="${NONRT_STD_V2_PORT:-30005}"

FLEXRIC="$PROJECT_DIR/openairinterface5g/openair2/E2AP/flexric"
XAPP_KPM="$FLEXRIC/build/examples/xApp/c/monitor/xapp_kpm_moni"

mkdir -p "$RUN_DIR"

TRAFFIC_PID=""
XAPP_PID=""

section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

die() {
    echo "ERRO: $*" >&2
    exit 1
}

cleanup() {
    [ -n "$TRAFFIC_PID" ] && kill "$TRAFFIC_PID" 2>/dev/null || true
    [ -n "$XAPP_PID" ] && kill "$XAPP_PID" 2>/dev/null || true
    docker exec "$DN_CONTAINER" pkill -f iperf3 >/dev/null 2>&1 || true
}
trap cleanup EXIT

check_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "comando '$1' nao encontrado"
}

ensure_container_running() {
    local name="$1"
    docker ps --format '{{.Names}}' | grep -qx "$name" || die "container '$name' nao esta rodando"
}

ensure_iperf_container() {
    local container="$1"
    if docker exec "$container" which iperf3 >/dev/null 2>&1; then
        return 0
    fi

    echo "Instalando iperf3 em $container..."
    if docker exec "$container" sh -c "command -v apt-get >/dev/null 2>&1"; then
        docker exec "$container" apt-get update -qq >/dev/null
        docker exec "$container" apt-get install -y -qq iperf3 >/dev/null
    elif docker exec "$container" sh -c "command -v apk >/dev/null 2>&1"; then
        docker exec "$container" apk add --no-cache iperf3 >/dev/null
    else
        die "nao sei instalar iperf3 em $container"
    fi
}

detect_ue() {
    UE_BIND_IP=""
    UE_IF=""

    case "$UE_SOURCE" in
        nrue)
            check_cmd iperf3
            for iface in oaitun_ue0 oaitun_ue1 oaitun_ue2 oaitun_ue3; do
                if ip -4 addr show "$iface" >/dev/null 2>&1; then
                    UE_IF="$iface"
                    UE_BIND_IP="$(ip -4 addr show "$iface" | grep -oP 'inet \K[\d.]+' | head -1)"
                    break
                fi
            done
            [ -n "$UE_BIND_IP" ] || die "nenhuma interface oaitun_ue* encontrada; suba gNB/nrUE"
            ;;
        ueransim)
            ensure_container_running "$UE_CONTAINER"
            ensure_iperf_container "$UE_CONTAINER"
            UE_IF="uesimtun0"
            UE_BIND_IP="$(docker exec "$UE_CONTAINER" ip -4 addr show "$UE_IF" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || true)"
            [ -n "$UE_BIND_IP" ] || die "interface uesimtun0 nao encontrada no container $UE_CONTAINER"
            ;;
        *)
            die "UE_SOURCE deve ser 'nrue' ou 'ueransim'"
            ;;
    esac
}

ensure_prereqs() {
    check_cmd docker
    check_cmd curl
    check_cmd awk
    check_cmd grep
    check_cmd timeout

    ensure_container_running "$DN_CONTAINER"
    ensure_iperf_container "$DN_CONTAINER"
    detect_ue

    [ -x "$XAPP_KPM" ] || {
        echo "xapp_kpm_moni ausente; compilando FlexRIC tools..."
        "$SCRIPT_DIR/build_flexric_tools.sh"
    }
    [ -x "$XAPP_KPM" ] || die "xapp_kpm_moni nao encontrado em $XAPP_KPM"

    if ! pgrep -x "nearRT-RIC" >/dev/null 2>&1; then
        echo "nearRT-RIC nao esta rodando; iniciando FlexRIC..."
        "$SCRIPT_DIR/up_flexric.sh"
        sleep 2
    fi

    if ! pgrep -f "nr-softmodem" >/dev/null 2>&1; then
        echo "AVISO: nr-softmodem nao detectado. O xApp pode nao ver no E2."
    fi
}

snapshot_nonrt() {
    local label="$1"
    local out="$RUN_DIR/nonrt_${label}.txt"

    {
        echo "# nonRT snapshot: $label"
        date
        echo ""
        echo "## health"
        printf "PMS: "; curl -sf "http://127.0.0.1:$PMS_PORT/status" 2>/dev/null || echo "OFFLINE"
        printf "Gateway: "; curl -sf "http://127.0.0.1:$GW_PORT/actuator/health" 2>/dev/null || echo "OFFLINE"
        printf "Control Panel HTTP: "
        curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:$CP_PORT/" 2>/dev/null || echo "OFFLINE"
        printf "A1 OSC: "; curl -sf "http://127.0.0.1:$OSC_PORT/counter/interface" 2>/dev/null || echo "OFFLINE"
        printf "A1 STD v2: "; curl -sf "http://127.0.0.1:$STD_V2_PORT/counter/interface" 2>/dev/null || echo "OFFLINE"
        echo ""
        echo "## rics"
        curl -sf "http://127.0.0.1:$PMS_PORT/a1-policy/v2/rics" 2>/dev/null || true
        echo ""
        echo "## policy-types"
        curl -sf "http://127.0.0.1:$PMS_PORT/a1-policy/v2/policy-types" 2>/dev/null || true
        echo ""
        echo "## services"
        curl -sf "http://127.0.0.1:$PMS_PORT/a1-policy/v2/services" 2>/dev/null || true
        echo ""
        echo "## policies"
        curl -sf "http://127.0.0.1:$PMS_PORT/a1-policy/v2/policies" 2>/dev/null || true
    } > "$out"

    echo "Snapshot nonRT ($label): $out"
}

start_iperf_server() {
    docker exec "$DN_CONTAINER" pkill -f iperf3 >/dev/null 2>&1 || true
    sleep 1
    docker exec -d "$DN_CONTAINER" iperf3 -s >/dev/null
    sleep 2
}

run_traffic() {
    local kind="$1"
    local duration="$2"
    local log="$3"

    case "$UE_SOURCE:$kind" in
        nrue:ping)
            timeout "$duration" ping -I "$UE_BIND_IP" -i 0.2 "$DN_IP" > "$log" 2>&1 || true
            ;;
        ueransim:ping)
            timeout "$duration" docker exec "$UE_CONTAINER" ping -I "$UE_IF" -i 0.2 "$DN_IP" > "$log" 2>&1 || true
            ;;
        nrue:tcp)
            timeout "$((duration + 10))" iperf3 -c "$DN_IP" -t "$duration" -P "$PARALLEL_STREAMS" -f m -B "$UE_BIND_IP" > "$log" 2>&1 || true
            ;;
        ueransim:tcp)
            timeout "$((duration + 10))" docker exec "$UE_CONTAINER" iperf3 -c "$DN_IP" -t "$duration" -P "$PARALLEL_STREAMS" -f m -B "$UE_BIND_IP" > "$log" 2>&1 || true
            ;;
        nrue:udp)
            timeout "$((duration + 10))" iperf3 -c "$DN_IP" -u -b "$UDP_RATE" -t "$duration" -P "$PARALLEL_STREAMS" -f m -B "$UE_BIND_IP" > "$log" 2>&1 || true
            ;;
        ueransim:udp)
            timeout "$((duration + 10))" docker exec "$UE_CONTAINER" iperf3 -c "$DN_IP" -u -b "$UDP_RATE" -t "$duration" -P "$PARALLEL_STREAMS" -f m -B "$UE_BIND_IP" > "$log" 2>&1 || true
            ;;
        *)
            die "trafego desconhecido: $kind"
            ;;
    esac
}

summarize_kpm() {
    local phase="$1"
    local log="$2"
    local out="$RUN_DIR/kpm_${phase}_summary.txt"

    {
        echo "# KPM summary: $phase"
        echo "log=$log"
        echo "indications=$(grep -c 'KPM ind_msg' "$log" 2>/dev/null || true)"
        echo "connected_nodes=$(grep -m1 'Connected E2 nodes' "$log" 2>/dev/null || echo 'n/a')"
        echo ""
        awk '
            BEGIN {
                n=split("DRB.UEThpDl DRB.UEThpUl DRB.PdcpSduVolumeDL DRB.PdcpSduVolumeUL DRB.RlcSduDelayDl RRU.PrbTotDl RRU.PrbTotUl", order, " ")
                unit["DRB.UEThpDl"]="kbps"
                unit["DRB.UEThpUl"]="kbps"
                unit["DRB.PdcpSduVolumeDL"]="Mb"
                unit["DRB.PdcpSduVolumeUL"]="Mb"
                unit["DRB.RlcSduDelayDl"]="us"
                unit["RRU.PrbTotDl"]="%"
                unit["RRU.PrbTotUl"]="%"
            }
            /^(DRB|RRU)\./ {
                metric=$1
                value=$3 + 0
                count[metric]++
                sum[metric]+=value
                if (count[metric] == 1 || value < min[metric]) min[metric]=value
                if (count[metric] == 1 || value > max[metric]) max[metric]=value
            }
            END {
                printf "%-24s %8s %8s %12s %12s %12s\n", "metric", "unit", "samples", "avg", "min", "max"
                for (i=1; i<=n; i++) {
                    m=order[i]
                    if (count[m] > 0) {
                        printf "%-24s %8s %8d %12.2f %12.2f %12.2f\n", m, unit[m], count[m], sum[m]/count[m], min[m], max[m]
                    } else {
                        printf "%-24s %8s %8d %12s %12s %12s\n", m, unit[m], 0, "n/a", "n/a", "n/a"
                    }
                }
            }
        ' "$log"
    } > "$out"

    cat "$out"
}

summarize_traffic() {
    local phase="$1"
    local log="$2"
    local out="$RUN_DIR/traffic_${phase}_summary.txt"

    {
        echo "# traffic summary: $phase"
        echo "log=$log"
        grep -E 'sender|receiver|packet loss|iperf Done|rtt min|transmitted' "$log" 2>/dev/null | tail -12 || true
    } > "$out"

    cat "$out"
}

run_phase() {
    local phase="$1"
    local traffic="$2"
    local duration="$3"
    local kpm_log="$RUN_DIR/kpm_${phase}.log"
    local traffic_log="$RUN_DIR/traffic_${phase}.log"

    section "Fase: $phase (${traffic}, ${duration}s)"
    : > "$kpm_log"
    : > "$traffic_log"

    start_iperf_server

    XAPP_DURATION="$duration" KPM_SST="$KPM_SST" KPM_SD="$KPM_SD" \
        timeout "$((duration + 45))" "$XAPP_KPM" > "$kpm_log" 2>&1 &
    XAPP_PID=$!

    sleep 3
    run_traffic "$traffic" "$duration" "$traffic_log" &
    TRAFFIC_PID=$!

    wait "$TRAFFIC_PID" 2>/dev/null || true
    TRAFFIC_PID=""

    wait "$XAPP_PID" 2>/dev/null || true
    XAPP_PID=""

    docker exec "$DN_CONTAINER" pkill -f iperf3 >/dev/null 2>&1 || true

    echo ""
    summarize_traffic "$phase" "$traffic_log"
    echo ""
    summarize_kpm "$phase" "$kpm_log"
}

write_report() {
    local report="$RUN_DIR/README.txt"
    {
        echo "UE stress observation run"
        echo "========================="
        echo ""
        echo "Run dir: $RUN_DIR"
        echo "UE source: $UE_SOURCE ($UE_IF $UE_BIND_IP)"
        echo "DN: $DN_CONTAINER $DN_IP"
        echo "Slice: SST=$KPM_SST SD=$KPM_SD"
        echo "Stress: mode=$STRESS_MODE duration=${STRESS_DURATION}s streams=$PARALLEL_STREAMS udp_rate=$UDP_RATE"
        echo ""
        echo "Files:"
        find "$RUN_DIR" -maxdepth 1 -type f -printf "  %f\n" | sort
        echo ""
        echo "Interpretation:"
        echo "  xApps/nearRT: compare kpm_baseline_summary.txt, kpm_stress_summary.txt and kpm_recovery_summary.txt."
        echo "  nonRT/rApps: compare nonrt_before.txt and nonrt_after.txt. In this Fase 1 lab, nonRT uses A1 simulators and does not consume FlexRIC KPM directly."
        echo "  A real closed loop is expected only in the O-RAN SC nearRT profile with A1 wiring and an rApp/xApp policy workflow."
    } > "$report"

    echo ""
    echo "Relatorio: $report"
}

section "UE stress + rApp/xApp observation"
ensure_prereqs

echo "Run dir: $RUN_DIR"
echo "UE: $UE_SOURCE $UE_IF $UE_BIND_IP"
echo "DN: $DN_CONTAINER $DN_IP"
echo "KPM slice: SST=$KPM_SST SD=$KPM_SD"

if [ "$NONRT_SEED" = "1" ]; then
    section "Seed nonRT sample policy data"
    "$SCRIPT_DIR/test_nonrt_ric.sh" --seed | tee "$RUN_DIR/nonrt_seed.txt"
fi

snapshot_nonrt "before"

run_phase "baseline" "ping" "$BASELINE_DURATION"
run_phase "stress" "$STRESS_MODE" "$STRESS_DURATION"
run_phase "recovery" "ping" "$RECOVERY_DURATION"

snapshot_nonrt "after"
write_report

section "Concluido"
echo "Compare principalmente:"
echo "  $RUN_DIR/kpm_baseline_summary.txt"
echo "  $RUN_DIR/kpm_stress_summary.txt"
echo "  $RUN_DIR/kpm_recovery_summary.txt"
echo "  $RUN_DIR/nonrt_before.txt"
echo "  $RUN_DIR/nonrt_after.txt"
