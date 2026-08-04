#!/bin/bash
# Validação do loop fechado Fase 3.
# Offline (padrão): unittests + run_closed_loop_lab.sh --offline (emulate dry-run se sem oaitun).
# Real live: CLOSED_LOOP_ALLOW_REAL=1 ./scripts/test_closed_loop_lab.sh --real-live

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REAL_LIVE=0

for arg in "$@"; do
    case "$arg" in
        --real-live) REAL_LIVE=1 ;;
        -h|--help)
            sed -n '2,6p' "$0"
            exit 0
            ;;
    esac
done

echo "=========================================="
echo "Teste closed loop Fase 3"
echo "=========================================="

echo "[1/3] unittests"
python3 -m unittest discover -s "$PROJECT_DIR/tests" -v

echo "[2/3] offline emulate"
AI_RUN_DIR="$PROJECT_DIR/logs/closed_loop_test_offline" \
ACTUATION_MODE=emulate \
AI_POLICY_COMMIT=0 \
"$SCRIPT_DIR/run_closed_loop_lab.sh" --offline

test -f "$PROJECT_DIR/logs/closed_loop_test_offline/effect_report.json"
test -f "$PROJECT_DIR/logs/closed_loop_test_offline/actuator_events.jsonl"
test -f "$PROJECT_DIR/logs/closed_loop_test_offline/decision.json"
echo "  offline OK"

if [ "$REAL_LIVE" = 1 ]; then
    echo "[3/3] real live (CONTROL action=2)"
    if [ "${CLOSED_LOOP_ALLOW_REAL:-0}" != "1" ]; then
        echo "ERRO: defina CLOSED_LOOP_ALLOW_REAL=1" >&2
        exit 1
    fi
    if ! docker ps --format '{{.Names}}' | grep -q '^python_xapp_runner$'; then
        echo "ERRO: Fase 2 (python_xapp_runner) necessária" >&2
        exit 1
    fi
    AI_RUN_DIR="$PROJECT_DIR/logs/closed_loop_test_real" \
    ACTUATION_MODE=real \
    CLOSED_LOOP_ALLOW_REAL=1 \
    AI_POLICY_COMMIT=0 \
    KPM_CAPTURE_SEC="${KPM_CAPTURE_SEC:-15}" \
    "$SCRIPT_DIR/run_closed_loop_lab.sh" --live-fase2
    grep -qE 'real_control|CONTROL' "$PROJECT_DIR/logs/closed_loop_test_real/actuator_events.jsonl"
    echo "  real live OK"
else
    echo "[3/3] real live omitido (use --real-live com CLOSED_LOOP_ALLOW_REAL=1)"
fi

echo ""
echo "Teste closed loop concluído."
