#!/bin/bash
# Sobe laboratório completo: Core + nonRT RIC + nearRT FlexRIC + gNB E2 + nrUE.
# Uso: ./scripts/up_e2_lab.sh
#
# Requer gNB compilado com E2: ./scripts/build_e2.sh
# Desativar nonRT RIC: NONRT_RIC=0 ./scripts/up_e2_lab.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NONRT_RIC="${NONRT_RIC:-1}"

echo "=========================================="
echo "Laboratório OAI: Core + nonRT + nearRT + gNB"
echo "=========================================="
echo ""

# 1. Core
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^oai-amf$'; then
    echo "[1/5] Iniciando Core OAI..."
    "$SCRIPT_DIR/up_core.sh"
else
    echo "[1/5] Core OAI já em execução."
fi

# 2. nonRT RIC (O-RAN SC — Fase 1)
if [ "$NONRT_RIC" = "1" ]; then
    echo ""
    echo "[2/5] Iniciando nonRT RIC (O-RAN SC)..."
    "$SCRIPT_DIR/up_nonrt_ric.sh"
else
    echo ""
    echo "[2/5] nonRT RIC desativado (NONRT_RIC=0)."
fi

# 3. nearRT-RIC (FlexRIC)
echo ""
echo "[3/5] Iniciando nearRT-RIC (FlexRIC)..."
"$SCRIPT_DIR/up_flexric.sh"

# 4. gNB + UE (com E2 agent)
echo ""
echo "[4/5] Iniciando gNB OAI + nrUE (E2 agent → 127.0.0.1)..."
"$SCRIPT_DIR/up_gnb_oai.sh"

# 5. Aguardar registro UE
echo ""
echo "[5/5] Aguardando UE registrar (30s)..."
sleep 30

echo ""
echo "=========================================="
echo "Laboratório pronto"
echo "=========================================="
echo ""
if [ "$NONRT_RIC" = "1" ]; then
    echo "nonRT RIC Control Panel: http://127.0.0.1:${NONRT_CONTROL_PANEL_PORT:-8181}/"
    echo "  Teste: ./scripts/test_nonrt_ric.sh --seed"
    echo ""
fi
echo "Verificar E2 setup nos logs do gNB:"
echo "  grep -iE 'E2|RIC|setup' ${OAI_LOG_DIR:-$PROJECT_DIR/logs}/gnb_oai.log"
echo ""
echo "Testar Service Models (nearRT FlexRIC):"
echo "  ./scripts/test_e2_sm.sh cust"
echo "  ./scripts/test_e2_kpm.sh"
echo "  ./scripts/test_e2_rc_attach.sh"
echo ""
echo "Parar: ./scripts/down_e2_lab.sh"
