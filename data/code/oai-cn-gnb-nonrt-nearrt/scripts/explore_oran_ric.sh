#!/bin/bash
# Explora nearRT O-RAN SC + nonRT perfil oran (Fase 2).
# Uso: ./scripts/explore_oran_ric.sh [suite]
#
# Suites: health | e2 | a1 | xapp | full

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORAN_VENDOR="${ORAN_VENDOR_DIR:-$PROJECT_DIR/vendor/oran-sc-ric}"
ORAN_CFG="${ORAN_CFG_DIR:-$PROJECT_DIR/config/oran-ric}"
SUITE="${1:-health}"
A1_PORT="${A1MEDIATOR_HOST_PORT:-10000}"
DURATION="${XAPP_DURATION:-20}"

compose() {
    docker compose \
        -f "$ORAN_VENDOR/docker-compose.yml" \
        -f "$ORAN_CFG/docker-compose.override.yml" \
        --env-file "$ORAN_VENDOR/.env" \
        --env-file "$ORAN_CFG/.env" \
        "$@"
}

section() { echo ""; echo "=== $1 ==="; }

ensure_oran() {
    if ! docker inspect ric_e2term >/dev/null 2>&1; then
        echo "A iniciar nearRT O-RAN SC..."
        "$SCRIPT_DIR/up_oran_ric.sh"
        sleep 10
    fi
}

suite_health() {
    "$SCRIPT_DIR/test_oran_ric.sh"
}

suite_e2() {
    section "Containers RIC"
    compose ps

    section "e2term logs (últimas 20 linhas)"
    docker logs ric_e2term 2>&1 | tail -20

    section "e2mgr logs"
    docker logs ric_e2mgr 2>&1 | tail -15

    section "gNB E2 log"
    local log="${OAI_LOG_DIR:-$PROJECT_DIR/logs}/gnb_oai_oran.log"
    if [ -f "$log" ]; then
        grep -iE 'E2|RIC|setup|SCTP' "$log" | tail -25 || echo "(sem entradas E2)"
    else
        echo "gNB não iniciado — ./scripts/up_gnb_oai_oran.sh"
    fi
}

suite_a1() {
    section "A1 Mediator — healthcheck"
    curl -sv "http://127.0.0.1:$A1_PORT/a1-p/healthcheck" 2>&1 | tail -10

    section "A1 — policy types"
    curl -s "http://127.0.0.1:$A1_PORT/a1-p/policytypes/" 2>/dev/null || echo "(vazio)"

    if curl -sf "http://127.0.0.1:${NONRT_PMS_HTTP_PORT:-8081}/status" >/dev/null 2>&1; then
        section "PMS → ric-oran"
        curl -s "http://127.0.0.1:${NONRT_PMS_HTTP_PORT:-8081}/a1-policy/v2/rics" 2>/dev/null || true
        echo ""
    fi
}

suite_xapp() {
    local node
    node=$("$SCRIPT_DIR/get_oran_e2_node_id.sh" 2>/dev/null) || node="gnb_208_095_00000e00"
    section "xApp simple_mon_xapp (${DURATION}s) node=$node"
    timeout --signal=KILL "$DURATION" compose exec -T python_xapp_runner \
        ./simple_mon_xapp.py --e2_node_id="$node" \
        --http_server_port=8092 --rmr_port=4562 \
        --metrics=DRB.UEThpDl,DRB.UEThpUl 2>&1 || true
}

echo "=========================================="
echo "Explorar O-RAN SC — Fase 2"
echo "=========================================="

ensure_oran

case "$SUITE" in
    health) suite_health ;;
    e2)     suite_e2 ;;
    a1)     suite_a1 ;;
    xapp)   suite_xapp ;;
    full)
        suite_health
        suite_e2
        suite_a1
        suite_xapp
        ;;
    *)
        echo "Uso: $0 [health|e2|a1|xapp|full]"
        exit 1
        ;;
esac

echo ""
echo "Guia: docs/ORAN_RIC_FASE2.md"
