#!/bin/bash
# Copia Service Models FlexRIC (submodule dev) para flexric-lib/ do projeto.
# Uso: ./scripts/sync_flexric_lib.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FLEXRIC_BUILD="$PROJECT_DIR/openairinterface5g/openair2/E2AP/flexric/build"
LIB_DIR="${FLEXRIC_LIB_DIR:-$PROJECT_DIR/flexric-lib}"
# nearRT-RIC exige trailing slash no path das libs
[[ "$LIB_DIR" == */ ]] || LIB_DIR="${LIB_DIR}/"

if [ ! -d "$FLEXRIC_BUILD" ]; then
    echo "ERRO: Build FlexRIC ausente. Execute ./scripts/build_flexric_tools.sh"
    exit 1
fi

mkdir -p "$LIB_DIR"

copy_sm() {
    local name="$1"
    local src
    src=$(find "$FLEXRIC_BUILD/src/sm" -name "$name" -print -quit 2>/dev/null || true)
    if [ -n "$src" ] && [ -f "$src" ]; then
        cp -f "$src" "$LIB_DIR/$name"
        echo "  $name"
    else
        echo "  AVISO: $name não encontrado no build FlexRIC"
    fi
}

echo "Sincronizando SMs para $LIB_DIR ..."
copy_sm libkpm_sm.so
copy_sm librc_sm.so
copy_sm libmac_sm.so
copy_sm librlc_sm.so
copy_sm libpdcp_sm.so
copy_sm libgtp_sm.so
copy_sm libtc_sm.so
copy_sm libslice_sm.so

if [ ! -f "$LIB_DIR/libkpm_sm.so" ]; then
    echo "ERRO: libkpm_sm.so ausente. Recompile: ./scripts/build_flexric_tools.sh"
    exit 1
fi

echo "FlexRIC libs prontas em: $LIB_DIR"

# Espelho curto em /usr/local (evita truncamento FR_CONF_FILE_LEN=128 no agente E2)
if [ "${SYNC_USR_LOCAL:-1}" = "1" ]; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        sudo mkdir -p /usr/local/lib/flexric
        sudo cp -f "$LIB_DIR"/*.so /usr/local/lib/flexric/ 2>/dev/null || true
        echo "Espelho: /usr/local/lib/flexric/"
    elif [ -w /usr/local/lib/flexric ] 2>/dev/null || mkdir -p /usr/local/lib/flexric 2>/dev/null; then
        cp -f "$LIB_DIR"/*.so /usr/local/lib/flexric/ 2>/dev/null || true
        echo "Espelho: /usr/local/lib/flexric/"
    else
        echo "Nota: não foi possível atualizar /usr/local/lib/flexric (sem permissão)."
        echo "      Os scripts usam symlink curto via resolve_flexric_sm_dir.sh."
    fi
fi
