#!/bin/bash
# Inicia o nearRT-RIC (FlexRIC) no host.
# Uso: ./scripts/up_flexric.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"
RIC_LOG="$LOG_DIR/nearRT-RIC.log"
RIC_IP="${NEAR_RIC_IP:-127.0.0.1}"
# shellcheck source=resolve_flexric_sm_dir.sh
source "$SCRIPT_DIR/resolve_flexric_sm_dir.sh"
_resolve_flexric_sm_dir "$PROJECT_DIR"
FLEXRIC_CONF_SRC="${FLEXRIC_CONF:-$PROJECT_DIR/config/flexric/flexric.conf}"
# FlexRIC limita o path do -c a FR_CONF_FILE_LEN-1 (127). Paths longos do repo abortam.
FLEXRIC_CONF_MAX=127
if [ -n "${FLEXRIC_CONF_RUNTIME:-}" ]; then
    FLEXRIC_CONF="$FLEXRIC_CONF_RUNTIME"
elif [ -f "$FLEXRIC_CONF_SRC" ] && [ "${#FLEXRIC_CONF_SRC}" -ge "$FLEXRIC_CONF_MAX" ]; then
    FLEXRIC_CONF_RUNTIME_DIR="${FLEXRIC_CONF_RUNTIME_DIR:-/tmp/oai-flexric}"
    mkdir -p "$FLEXRIC_CONF_RUNTIME_DIR"
    FLEXRIC_CONF="$FLEXRIC_CONF_RUNTIME_DIR/flexric.conf"
    cp -f "$FLEXRIC_CONF_SRC" "$FLEXRIC_CONF"
    echo "Nota: conf FlexRIC copiada para path curto ($FLEXRIC_CONF)."
else
    FLEXRIC_CONF="$FLEXRIC_CONF_SRC"
fi

# Preferir nearRT-RIC do submodule (mesma versão E2AP que gNB/xApps dev)
FLEXRIC_BUILD="$PROJECT_DIR/openairinterface5g/openair2/E2AP/flexric/build/examples/ric/nearRT-RIC"

RIC_BIN="${NEAR_RIC_BIN:-}"
if [ -n "$RIC_BIN" ] && [ -x "$RIC_BIN" ]; then
    :
elif [ "${FLEXRIC_USE_SUBMODULE:-1}" = "1" ] && [ -x "$FLEXRIC_BUILD" ]; then
    RIC_BIN="$FLEXRIC_BUILD"
else
    for candidate in \
        "$FLEXRIC_BUILD" \
        /usr/local/bin/flexric/ric/nearRT-RIC \
        /usr/local/bin/nearRT-RIC; do
        if [ -x "$candidate" ]; then
            RIC_BIN="$candidate"
            break
        fi
    done
fi

if [ -z "$RIC_BIN" ]; then
    echo "ERRO: nearRT-RIC não encontrado."
    echo "      Instale FlexRIC ou compile o submodule (ver docs/E2_FLEXRIC.md)."
    exit 1
fi

mkdir -p "$LOG_DIR"

if [ ! -f "$FLEXRIC_LIB/libkpm_sm.so" ]; then
    echo "SMs FlexRIC ausentes; sincronizando..."
    "$SCRIPT_DIR/sync_flexric_lib.sh" 2>/dev/null || "$SCRIPT_DIR/build_flexric_tools.sh"
fi

if pgrep -x "nearRT-RIC" >/dev/null 2>&1; then
    echo "nearRT-RIC já está em execução (PID $(pgrep -x 'nearRT-RIC'))."
    exit 0
fi

RIC_ARGS=(-p "$FLEXRIC_LIB")
[ -f "$FLEXRIC_CONF" ] && RIC_ARGS+=(-c "$FLEXRIC_CONF")
RIC_ARGS+=(-a "$RIC_IP")

echo "Iniciando nearRT-RIC ($RIC_BIN) em $RIC_IP (libs: $FLEXRIC_LIB)..."
nohup "$RIC_BIN" "${RIC_ARGS[@]}" > "$RIC_LOG" 2>&1 &
RIC_PID=$!
sleep 2

if ! kill -0 "$RIC_PID" 2>/dev/null; then
    echo "ERRO: nearRT-RIC falhou ao iniciar. Ver: $RIC_LOG"
    tail -20 "$RIC_LOG" 2>/dev/null || true
    exit 1
fi

echo "nearRT-RIC PID: $RIC_PID"
echo "Log: $RIC_LOG"
echo ""
echo "Porta E2AP padrão: 36421 (FlexRIC) / 36422 (O-RAN SC)"
echo "Parar: ./scripts/down_flexric.sh"
