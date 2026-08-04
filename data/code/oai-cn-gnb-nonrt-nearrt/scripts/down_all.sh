#!/bin/bash
# Para gNB OAI, UERANSIM e Core em sequência
# Uso: ./scripts/down_all.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Parando laboratório OAI"
echo "=========================================="
echo ""

echo "[1/3] Parando gNB OAI..."
"$SCRIPT_DIR/down_gnb_oai.sh"
echo ""

echo "[2/3] Parando UERANSIM..."
"$SCRIPT_DIR/down_ueransim.sh"
echo ""

echo "[3/3] Parando Core OAI..."
"$SCRIPT_DIR/down_core.sh"
echo ""

echo "=========================================="
echo "Laboratório parado."
echo "=========================================="
echo ""
echo "Para reiniciar: ./scripts/up_all.sh"
echo ""
