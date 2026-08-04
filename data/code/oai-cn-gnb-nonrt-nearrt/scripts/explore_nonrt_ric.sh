#!/bin/bash
# Explora funcionalidades do nonRT RIC O-RAN SC (Fase 1).
# Uso: ./scripts/explore_nonrt_ric.sh [suite]
#
# Suites:
#   health   - PMS, Gateway, Control Panel, A1 simulators (padrão)
#   pms      - APIs REST do Policy Management Service
#   a1sim    - Simuladores A1 (OSC, STD, STD-v2)
#   policies - Ciclo policy type → service → policy (com --seed)
#   full     - Todas as suites acima
#
# Pré-requisito: ./scripts/up_nonrt_ric.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NONRT_DIR="${NONRT_COMPOSE_DIR:-$PROJECT_DIR/config/nonrtric}"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"
SUITE="${1:-health}"

PMS_PORT="${NONRT_PMS_HTTP_PORT:-8081}"
GW_PORT="${NONRT_GATEWAY_PORT:-9090}"
CP_PORT="${NONRT_CONTROL_PANEL_PORT:-8181}"

ensure_up() {
    if ! curl -sf "http://127.0.0.1:$PMS_PORT/status" >/dev/null 2>&1; then
        echo "nonRT RIC offline; a iniciar..."
        "$SCRIPT_DIR/up_nonrt_ric.sh"
        sleep 5
    fi
}

section() {
    echo ""
    echo "=== $1 ==="
}

pretty_json() {
    if command -v jq >/dev/null 2>&1; then
        jq . 2>/dev/null || cat
    else
        cat
    fi
}

suite_health() {
    section "Health checks"
    "$SCRIPT_DIR/test_nonrt_ric.sh"
}

suite_pms() {
    section "PMS — status"
    curl -sf "http://127.0.0.1:$PMS_PORT/status"
    echo ""

    section "PMS — RICs registados"
    curl -sf "http://127.0.0.1:$PMS_PORT/a1-policy/v2/rics" | pretty_json

    section "PMS — policy types"
    curl -sf "http://127.0.0.1:$PMS_PORT/a1-policy/v2/policy-types" | pretty_json

    section "PMS — services"
    curl -sf "http://127.0.0.1:$PMS_PORT/a1-policy/v2/services" | pretty_json

    section "PMS — policies (lista)"
    curl -sf "http://127.0.0.1:$PMS_PORT/a1-policy/v2/policies" 2>/dev/null | pretty_json || echo "(vazio ou endpoint indisponível)"

    section "Gateway — actuator"
    curl -sf "http://127.0.0.1:$GW_PORT/actuator/health" | pretty_json

    section "Control Panel"
    echo "  http://127.0.0.1:$CP_PORT/"
    curl -sf -o /dev/null -w "  HTTP %{http_code}\n" "http://127.0.0.1:$CP_PORT/"
}

suite_a1sim() {
    local sims=(
        "OSC:30001"
        "STD:30003"
        "STD-v2:30005"
    )
    section "A1 Simulators — interface e contadores"
    for entry in "${sims[@]}"; do
        local name="${entry%%:*}"
        local port="${entry##*:}"
        echo ""
        echo "--- $name (porta $port) ---"
        curl -sf "http://127.0.0.1:$port/counter/interface" || echo "  FALHOU"
        echo ""
        curl -sf "http://127.0.0.1:$port/counter/num_instances" 2>/dev/null || true
    done
}

suite_policies() {
    section "Dados de exemplo (policy type + service + policy)"
    "$SCRIPT_DIR/test_nonrt_ric.sh" --seed

    section "Verificar policy no PMS"
    local policy_id="aa8feaa88d944d919ef0e83f2172a5100"
    curl -sf -o /dev/null -w "GET /policies/$policy_id → HTTP %{http_code}\n" \
        "http://127.0.0.1:$PMS_PORT/a1-policy/v2/policies/$policy_id" || true

    section "Instâncias no A1 Sim OSC"
    curl -sf "http://127.0.0.1:30001/counter/num_instances" || true
    echo ""
    echo "Abra o Control Panel para ver policies: http://127.0.0.1:$CP_PORT/"
}

echo "=========================================="
echo "Explorar nonRT RIC — Fase 1"
echo "=========================================="
echo "Compose: $NONRT_DIR"
echo "Suite:   $SUITE"

ensure_up

case "$SUITE" in
    health)  suite_health ;;
    pms)     suite_pms ;;
    a1sim)   suite_a1sim ;;
    policies) suite_policies ;;
    full)
        suite_health
        suite_pms
        suite_a1sim
        suite_policies
        ;;
    *)
        echo "Uso: $0 [health|pms|a1sim|policies|full]"
        exit 1
        ;;
esac

echo ""
echo "Exploração concluída. Guia: docs/EXPLORAR_NONRT_RIC.md"
echo "Logs compose: docker compose -f $NONRT_DIR/docker-compose.yml logs -f policy-agent"
