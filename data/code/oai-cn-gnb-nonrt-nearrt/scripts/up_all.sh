#!/bin/bash
# Sobe Core, UERANSIM e gNB OAI em sequência
# Usuários 01 (208950000000031) e 02 (208950000000032) já cadastrados em oai_db2.sql
# Uso: ./scripts/up_all.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Subindo laboratório OAI completo"
echo "=========================================="
echo ""

# 1. Core
echo "[1/4] Iniciando Core OAI..."
"$SCRIPT_DIR/up_core.sh"
echo ""

# 2. Rede para gNB OAI
echo "[2/4] Configurando rede (demo-oai)..."
sudo ip addr add 192.168.70.129/24 dev demo-oai 2>/dev/null || true
echo ""

# 3. UERANSIM
echo "[3/4] Iniciando UERANSIM (usuário 01)..."
"$SCRIPT_DIR/up_ueransim.sh"
echo ""

# 4. gNB OAI
echo "[4/4] Iniciando gNB OAI (usuário 02)..."
"$SCRIPT_DIR/up_gnb_oai.sh"
echo ""

echo "=========================================="
echo "Laboratório pronto!"
echo "=========================================="
echo ""
echo "Usuários: 01 (UERANSIM) | 02 (nrUE)"
echo "Para parar: ./scripts/down_all.sh"
echo ""
