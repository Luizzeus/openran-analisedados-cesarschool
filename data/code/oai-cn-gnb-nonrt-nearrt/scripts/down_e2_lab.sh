#!/bin/bash
# Para laboratório E2 (gNB, FlexRIC; Core permanece ativo).
# Uso: ./scripts/down_e2_lab.sh [--all]
#
# --all  também para o Core OAI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Parando laboratório E2..."

"$SCRIPT_DIR/down_gnb_oai.sh" 2>/dev/null || true
"$SCRIPT_DIR/down_flexric.sh"
"$SCRIPT_DIR/down_nonrt_ric.sh" 2>/dev/null || true

if [ "${1:-}" = "--all" ]; then
    "$SCRIPT_DIR/down_core.sh" 2>/dev/null || true
fi

echo "Laboratório E2 parado."
