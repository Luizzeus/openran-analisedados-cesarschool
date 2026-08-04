#!/bin/bash
# Compila gNB + nrUE com agente E2 (FlexRIC) integrado.
# Uso: ./scripts/build_e2.sh
#
# Pré-requisitos: dependências OAI (./build_oai --ninja -I, uma vez)
# Service Models: /usr/local/lib/flexric/ (instalados com FlexRIC)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OAI_DIR="$PROJECT_DIR/openairinterface5g"
FLEXRIC_DIR="$OAI_DIR/openair2/E2AP/flexric"
BUILD_DIR="$OAI_DIR/cmake_targets"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"
LOG_FILE="$LOG_DIR/build_e2.log"

E2AP_VERSION="${E2AP_VERSION:-E2AP_V2}"
KPM_VERSION="${KPM_VERSION:-KPM_V2_03}"

echo "=========================================="
echo "Build OAI gNB + nrUE com E2 Agent"
echo "  E2AP: $E2AP_VERSION  KPM: $KPM_VERSION"
echo "=========================================="

mkdir -p "$LOG_DIR"

# FlexRIC submodule (obrigatório para compilar E2)
if [ ! -f "$FLEXRIC_DIR/CMakeLists.txt" ]; then
    echo "Clonando FlexRIC (branch dev — compatível com OAI E2 agent)..."
    git clone --branch dev --depth 1 \
        https://gitlab.eurecom.fr/mosaic5g/flexric.git "$FLEXRIC_DIR"
fi

# Service Models no sistema
if [ ! -d /usr/local/lib/flexric ] || [ -z "$(ls -A /usr/local/lib/flexric/*.so 2>/dev/null)" ]; then
    echo ""
    echo "AVISO: Service Models não encontrados em /usr/local/lib/flexric/"
    echo "       Instale FlexRIC antes (ver docs/E2_FLEXRIC.md)."
    echo ""
fi

cd "$BUILD_DIR"
echo "Log: $LOG_FILE"
echo ""

./build_oai --ninja --gNB --nrUE --build-e2 -w SIMU -c \
    --cmake-opt "-DE2AP_VERSION=${E2AP_VERSION}" \
    --cmake-opt "-DKPM_VERSION=${KPM_VERSION}" \
    2>&1 | tee "$LOG_FILE"

echo ""
echo "Build concluído. Binários em: $OAI_DIR/cmake_targets/ran_build/build/"
echo "  nr-softmodem (com E2 agent)"
echo "  nr-uesoftmodem"
