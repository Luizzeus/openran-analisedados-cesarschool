#!/bin/bash
# Lab Fase 2: Core + nearRT O-RAN SC + nonRT (A1) + gNB E2:36422
# Não altera Fase 1 — use RIC_STACK=oran-sc explicitamente.
#
# Uso: ./scripts/up_oai_oran_lab.sh
# Variáveis:
#   NONRT_RIC=0   — omitir nonRT RIC
#   SKIP_BUILD=1  — não verificar binário oran-sc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NONRT_RIC="${NONRT_RIC:-1}"
ORAN_GNB="$PROJECT_DIR/openairinterface5g/cmake_targets/ran_build/build-oran-sc/nr-softmodem-oran-sc"

echo "=========================================="
echo "Lab O-RAN SC — Fase 2"
echo "  (FlexRIC desativado; E2 porta 36422)"
echo "=========================================="

# Garantir FlexRIC parado
"$SCRIPT_DIR/down_flexric.sh" 2>/dev/null || true

# Parar perfil Fase 1 nonRT se estiver ativo (portas em conflito)
"$SCRIPT_DIR/down_nonrt_ric.sh" 2>/dev/null || true

if [ "${SKIP_BUILD:-0}" != "1" ] && [ ! -x "$ORAN_GNB" ]; then
    echo ""
    echo "Binário E2 O-RAN SC não encontrado — a compilar..."
    "$SCRIPT_DIR/build_e2_oran_sc.sh"
fi

echo ""
echo "[1/4] Core OAI..."
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^oai-amf$'; then
    "$SCRIPT_DIR/up_core.sh"
else
    echo "  Core já em execução."
fi

echo ""
echo "[2/4] nearRT O-RAN SC..."
"$SCRIPT_DIR/up_oran_ric.sh"

if [ "$NONRT_RIC" = "1" ]; then
    echo ""
    echo "[3/4] nonRT RIC (perfil A1 → ric-plt-a1)..."
    "$SCRIPT_DIR/up_nonrt_ric_oran.sh"
else
    echo ""
    echo "[3/4] nonRT RIC omitido (NONRT_RIC=0)."
fi

echo ""
echo "[4/4] gNB + nrUE (E2 O-RAN SC)..."
"$SCRIPT_DIR/up_gnb_oai_oran.sh"

echo ""
echo "Aguardando UE (30s)..."
sleep 30

echo ""
echo "=========================================="
echo "Lab Fase 2 pronto"
echo "=========================================="
echo ""
echo "  Testes:  ./scripts/test_oran_ric.sh"
echo "  Explorar: ./scripts/explore_oran_ric.sh full"
echo "  Parar:    ./scripts/down_oai_oran_lab.sh"
echo ""
echo "  Fase 1 (FlexRIC) inalterada: NONRT_RIC=0 ./scripts/up_e2_lab.sh"
