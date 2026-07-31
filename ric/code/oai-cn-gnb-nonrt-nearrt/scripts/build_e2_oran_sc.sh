#!/bin/bash
# Compila gNB + nrUE com E2AP porta 36422 (O-RAN SC nearRT).
# Mantém build FlexRIC (36421) intacto — binário separado: nr-softmodem-oran-sc
#
# Uso: ./scripts/build_e2_oran_sc.sh
# Requer: build OAI base (./scripts/build_e2.sh ou build_oai -I)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OAI_DIR="$PROJECT_DIR/openairinterface5g"
FLEXRIC_DIR="$OAI_DIR/openair2/E2AP/flexric"
BUILD_DIR="$OAI_DIR/cmake_targets"
RAN_BUILD="$BUILD_DIR/ran_build/build"
ORAN_BIN_DIR="$RAN_BUILD-oran-sc"
AGENT_API="$FLEXRIC_DIR/src/agent/e2_agent_api.c"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"
LOG_FILE="$LOG_DIR/build_e2_oran_sc.log"

E2AP_VERSION="${E2AP_VERSION:-E2AP_V2}"
KPM_VERSION="${KPM_VERSION:-KPM_V2_03}"
E2_PORT_ORAN=36422
E2_PORT_FLEX=36421

echo "=========================================="
echo "Build OAI gNB E2 — O-RAN SC (porta $E2_PORT_ORAN)"
echo "=========================================="

mkdir -p "$LOG_DIR" "$ORAN_BIN_DIR"

if [ ! -f "$AGENT_API" ]; then
    echo "ERRO: $AGENT_API não encontrado"
    exit 1
fi

# Backup e patch temporário da porta E2
BACKUP="$AGENT_API.bak_oran_sc_build"
if [ ! -f "$BACKUP" ]; then
    cp "$AGENT_API" "$BACKUP"
fi

restore_agent_api() {
    if [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$AGENT_API"
    fi
}
trap restore_agent_api EXIT

sed -i "s/const int e2ap_server_port = ${E2_PORT_FLEX};/const int e2ap_server_port = ${E2_PORT_ORAN};/" "$AGENT_API"

cd "$BUILD_DIR"
./build_oai --ninja --gNB --nrUE --build-e2 -w SIMU -c \
    --cmake-opt "-DE2AP_VERSION=${E2AP_VERSION}" \
    --cmake-opt "-DKPM_VERSION=${KPM_VERSION}" \
    2>&1 | tee "$LOG_FILE"

cp -f "$RAN_BUILD/nr-softmodem" "$ORAN_BIN_DIR/nr-softmodem-oran-sc"
cp -f "$RAN_BUILD/nr-uesoftmodem" "$ORAN_BIN_DIR/nr-uesoftmodem"

echo ""
echo "Build O-RAN SC concluído."
echo "  $ORAN_BIN_DIR/nr-softmodem-oran-sc  (E2 → :$E2_PORT_ORAN)"
echo "  Build FlexRIC (36421) inalterado em: $RAN_BUILD/nr-softmodem"
echo ""
echo "Próximo: ./scripts/up_oai_oran_lab.sh"
