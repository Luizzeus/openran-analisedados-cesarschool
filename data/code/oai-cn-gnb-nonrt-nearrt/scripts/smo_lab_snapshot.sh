#!/bin/bash
# Coleta snapshot SMO-lite das interfaces abertas do lab.
# Uso:
#   ./scripts/smo_lab_snapshot.sh [run_dir]
#
# Saidas:
#   summary.txt
#   topology.lab.json
#   a1_*.json/txt
#   e2_*.txt
#   o2_docker_inventory.txt
#   oam_events.jsonl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="${1:-$PROJECT_DIR/logs/smo_lab_$TS}"
TOPOLOGY_FILE="${SMO_TOPOLOGY_FILE:-$PROJECT_DIR/config/smo/topology.lab.json}"
PMS_URL="${NONRT_PMS_URL:-http://127.0.0.1:8081/a1-policy/v2}"
A1_URL="${A1_MEDIATOR_URL:-http://127.0.0.1:10000/a1-p}"
EVENT_LOG="${SMO_EVENT_LOG:-$PROJECT_DIR/logs/smo_lab_events.jsonl}"

mkdir -p "$RUN_DIR"

copy_or_note() {
    local src="$1"
    local dst="$2"
    if [ -f "$src" ]; then
        cp "$src" "$dst"
    else
        echo "arquivo ausente: $src" > "$dst"
    fi
}

http_get() {
    local url="$1"
    local out="$2"
    if command -v curl >/dev/null 2>&1; then
        if curl -fsS --max-time 4 "$url" > "$out" 2>"$out.err"; then
            rm -f "$out.err"
            return 0
        fi
        {
            echo "ERRO ao consultar $url"
            cat "$out.err" 2>/dev/null || true
        } > "$out"
        rm -f "$out.err"
        return 1
    fi
    echo "curl nao encontrado" > "$out"
    return 1
}

docker_safe() {
    local out="$1"
    shift
    if command -v docker >/dev/null 2>&1; then
        if "$@" > "$out" 2>"$out.err"; then
            rm -f "$out.err"
            return 0
        fi
        {
            echo "ERRO ao executar: $*"
            cat "$out.err" 2>/dev/null || true
        } > "$out"
        rm -f "$out.err"
        return 1
    fi
    echo "docker nao encontrado" > "$out"
    return 1
}

copy_or_note "$TOPOLOGY_FILE" "$RUN_DIR/topology.lab.json"

http_get "$PMS_URL/rics" "$RUN_DIR/a1_pms_rics.json" || true
http_get "$PMS_URL/policy-types" "$RUN_DIR/a1_pms_policy_types.json" || true
http_get "$A1_URL/healthcheck" "$RUN_DIR/a1_mediator_health.txt" || true
http_get "$A1_URL/policytypes/" "$RUN_DIR/a1_mediator_policytypes.json" || true

if [ -x "$SCRIPT_DIR/get_oran_e2_node_id.sh" ]; then
    "$SCRIPT_DIR/get_oran_e2_node_id.sh" > "$RUN_DIR/e2_node_id.txt" 2>&1 || true
else
    echo "get_oran_e2_node_id.sh ausente" > "$RUN_DIR/e2_node_id.txt"
fi

docker_safe "$RUN_DIR/e2_rnib_keys.txt" docker exec ric_dbaas redis-cli KEYS '{e2Manager},RAN:*' || true
docker_safe "$RUN_DIR/e2mgr_e2t_list.json" docker exec ric_e2mgr curl -sf http://localhost:3800/v1/e2t/list || true
docker_safe "$RUN_DIR/o2_docker_inventory.txt" docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true

if [ -f "$EVENT_LOG" ]; then
    cp "$EVENT_LOG" "$RUN_DIR/oam_events.jsonl"
else
    : > "$RUN_DIR/oam_events.jsonl"
fi

{
    echo "# SMO-lite snapshot"
    echo "timestamp=$TS"
    echo "run_dir=$RUN_DIR"
    echo "topology=$RUN_DIR/topology.lab.json"
    echo ""
    echo "## A1"
    echo "PMS RICs: $RUN_DIR/a1_pms_rics.json"
    echo "PMS policy types: $RUN_DIR/a1_pms_policy_types.json"
    echo "A1 mediator health: $RUN_DIR/a1_mediator_health.txt"
    echo "A1 mediator policy types: $RUN_DIR/a1_mediator_policytypes.json"
    echo ""
    echo "## E2"
    echo "E2 node ID: $(head -1 "$RUN_DIR/e2_node_id.txt" 2>/dev/null || echo n/a)"
    echo "RNIB keys: $RUN_DIR/e2_rnib_keys.txt"
    echo "E2T list: $RUN_DIR/e2mgr_e2t_list.json"
    echo ""
    echo "## O1/VES"
    echo "Topology/O1 simulated: $RUN_DIR/topology.lab.json"
    echo "OAM events: $RUN_DIR/oam_events.jsonl"
    echo ""
    echo "## O2"
    echo "Docker inventory: $RUN_DIR/o2_docker_inventory.txt"
} > "$RUN_DIR/summary.txt"

cat "$RUN_DIR/summary.txt"
