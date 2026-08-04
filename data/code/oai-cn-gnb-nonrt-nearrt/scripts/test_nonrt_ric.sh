#!/bin/bash
# Valida nonRT RIC Fase 1: PMS, A1 Simulators, Gateway, Control Panel.
# Opcionalmente cria dados de exemplo (policy type + service + policy).
# Uso: ./scripts/test_nonrt_ric.sh [--seed]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NONRT_DIR="${NONRT_COMPOSE_DIR:-$PROJECT_DIR/config/nonrtric}"
SEED="${1:-}"

PMS_PORT="${NONRT_PMS_HTTP_PORT:-8081}"
GW_PORT="${NONRT_GATEWAY_PORT:-9090}"
CP_PORT="${NONRT_CONTROL_PANEL_PORT:-8181}"
OSC_PORT=30001
STD_V2_PORT=30005

check_http() {
    local label="$1"
    local url="$2"
    local expect="${3:-}"
    echo -n "  $label ... "
    local body
    body=$(curl -sf "$url" 2>/dev/null) || { echo "FALHOU ($url)"; return 1; }
    if [ -n "$expect" ] && ! echo "$body" | grep -qi "$expect"; then
        echo "FALHOU (resposta inesperada)"
        return 1
    fi
    echo "OK"
}

ensure_up() {
    if ! curl -sf "http://127.0.0.1:$PMS_PORT/status" >/dev/null 2>&1; then
        echo "nonRT RIC não responde; a iniciar..."
        "$SCRIPT_DIR/up_nonrt_ric.sh"
        sleep 5
    fi
}

wait_policy_types() {
    local expect="${1:-1}"
    echo -n "  sync policy types no PMS ... "
    for _ in $(seq 1 30); do
        local ids
        ids=$(curl -sf "http://127.0.0.1:$PMS_PORT/a1-policy/v2/policy-types" 2>/dev/null || echo "")
        if echo "$ids" | grep -q "\"$expect\""; then
            echo "OK"
            return 0
        fi
        sleep 2
    done
    echo "timeout (types atuais: $ids)"
    return 1
}

seed_sample_data() {
    local td="$NONRT_DIR/testdata"
    echo ""
    echo "=== Dados de exemplo (PMS + A1 OSC) ==="

    echo -n "  policy type OSC ... "
    res=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        "http://127.0.0.1:$OSC_PORT/policytype?id=1" \
        -H "Content-Type: application/json" \
        --data-binary "@$td/OSC/policy_type.json")
    [ "$res" = "201" ] && echo "OK ($res)" || echo "HTTP $res"

    wait_policy_types "1" || true

    echo -n "  service no PMS ... "
    res=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        "http://127.0.0.1:$PMS_PORT/a1-policy/v2/services" \
        -H "Content-Type: application/json" \
        --data-binary "@$td/service.json")
    [ "$res" = "201" ] || [ "$res" = "200" ] && echo "OK ($res)" || echo "HTTP $res"

    echo -n "  policy OSC ... "
    res=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        "http://127.0.0.1:$PMS_PORT/a1-policy/v2/policies" \
        -H "Content-Type: application/json" \
        --data-binary "@$td/policy_osc.json")
    [ "$res" = "201" ] || [ "$res" = "200" ] && echo "OK ($res)" || echo "HTTP $res"
}

echo "=========================================="
echo "Teste nonRT RIC — Fase 1"
echo "=========================================="

ensure_up

echo ""
echo "=== Health checks ==="
check_http "PMS status" "http://127.0.0.1:$PMS_PORT/status" "hunky dory"
check_http "A1 Sim OSC" "http://127.0.0.1:$OSC_PORT/counter/interface" "OSC"
check_http "A1 Sim STD v2" "http://127.0.0.1:$STD_V2_PORT/counter/interface" "STD"
check_http "Gateway" "http://127.0.0.1:$GW_PORT/actuator/health" "UP"
check_http "Control Panel" "http://127.0.0.1:$CP_PORT/" ""

echo ""
echo "=== RICs registados no PMS ==="
curl -sf "http://127.0.0.1:$PMS_PORT/a1-policy/v2/rics" 2>/dev/null | head -c 500 || true
echo ""

if [ "$SEED" = "--seed" ]; then
    seed_sample_data
    echo ""
    echo "Abra o Control Panel: http://127.0.0.1:$CP_PORT/"
fi

echo ""
echo "Teste nonRT RIC concluído."
