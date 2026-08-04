#!/bin/bash
# Compila nearRT-RIC e xApps FlexRIC (branch dev) alinhados ao gNB E2.
# Uso: ./scripts/build_flexric_tools.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FLEXRIC="$PROJECT_DIR/openairinterface5g/openair2/E2AP/flexric"
BUILD="$FLEXRIC/build"

echo "Compilando FlexRIC tools (dev, E2AP_V2, KPM_V2_03)..."

if [ ! -f "$FLEXRIC/CMakeLists.txt" ]; then
    echo "ERRO: Submodule FlexRIC ausente. Execute ./scripts/build_e2.sh"
    exit 1
fi

# Cache CMake de outro clone (path absoluto) quebra o build — recria se necessário.
if [ -f "$BUILD/CMakeCache.txt" ]; then
    cached_home=$(grep -E '^CMAKE_HOME_DIRECTORY:' "$BUILD/CMakeCache.txt" | head -1 | cut -d= -f2- || true)
    if [ -n "$cached_home" ] && [ "$cached_home" != "$FLEXRIC" ]; then
        echo "AVISO: CMakeCache de outro path ($cached_home)."
        echo "       Limpando $BUILD para recompilar neste projeto."
        rm -rf "$BUILD"
    fi
fi

mkdir -p "$BUILD"
cd "$BUILD"
cmake .. -GNinja -DE2AP_VERSION=E2AP_V2 -DKPM_VERSION=KPM_V2_03
ninja nearRT-RIC \
    libkpm_sm.so librc_sm.so libmac_sm.so librlc_sm.so libpdcp_sm.so libgtp_sm.so libtc_sm.so libslice_sm.so \
    xapp_rc_moni xapp_kpm_moni xapp_kpm_rc xapp_gtp_mac_rlc_pdcp_moni

"$SCRIPT_DIR/sync_flexric_lib.sh"
# Forçar espelho curto usado pelo gNB (pode ter SMs mais novas/incompatíveis)
SHORT_FLEXRIC_LIB="${SHORT_FLEXRIC_LIB:-/var/tmp/oai-flexric-lib}"
mkdir -p "$SHORT_FLEXRIC_LIB" 2>/dev/null || sudo mkdir -p "$SHORT_FLEXRIC_LIB"
cp -f "${FLEXRIC_LIB_DIR:-$PROJECT_DIR/flexric-lib}"/*.so "$SHORT_FLEXRIC_LIB/" 2>/dev/null \
    || sudo cp -f "${FLEXRIC_LIB_DIR:-$PROJECT_DIR/flexric-lib}"/*.so "$SHORT_FLEXRIC_LIB/"
chmod a+rX "$SHORT_FLEXRIC_LIB" "$SHORT_FLEXRIC_LIB"/*.so 2>/dev/null \
    || sudo chmod a+rX "$SHORT_FLEXRIC_LIB" "$SHORT_FLEXRIC_LIB"/*.so 2>/dev/null || true
echo "SMs espelhadas em: $SHORT_FLEXRIC_LIB/"

echo ""
echo "Binários em: $BUILD/examples/"
echo "SMs em: ${FLEXRIC_LIB_DIR:-$PROJECT_DIR/flexric-lib}/"
echo "  ric/nearRT-RIC"
echo "  xApp/c/monitor/xapp_rc_moni"
echo "  xApp/c/monitor/xapp_kpm_moni"
echo "  xApp/c/monitor/xapp_gtp_mac_rlc_pdcp_moni"
echo "  xApp/c/kpm_rc/xapp_kpm_rc"
