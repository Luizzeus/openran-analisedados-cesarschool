#!/bin/bash
# Resolve um caminho CURTO e acessível ao root para os Service Models FlexRIC.
#
# Dois problemas comuns com o path do projeto (.../cesar-school-lectures/.../flexric-lib/):
# 1) O agente E2 copia sm_dir para um buffer de FR_CONF_FILE_LEN (128) bytes sem
#    garantir NUL → path longo trunca e opendir aborta o nr-softmodem.
# 2) Symlink curto → $HOME falha sob sudo: em muitos hosts root não atravessa
#    /home/<user> (700/750) → "Error opening the input directory".
#
# Solução: materializar as .so em SHORT_FLEXRIC_LIB (dir real, não symlink).
#
# Uso:
#   source "$SCRIPT_DIR/resolve_flexric_sm_dir.sh"
#   _resolve_flexric_sm_dir "$PROJECT_DIR"
#   # define FLEXRIC_LIB com trailing slash, length < 128
#
# Variáveis:
#   FLEXRIC_LIB_DIR     — árvore de origem (default: $PROJECT_DIR/flexric-lib)
#   SHORT_FLEXRIC_LIB   — dir curto (default: /var/tmp/oai-flexric-lib)
#   FLEXRIC_USE_USR_LOCAL=1 — usar /usr/local/lib/flexric/ (não recomendado no lab)

_resolve_flexric_sm_dir() {
    local project_dir="${1:-}"
    local src="${FLEXRIC_LIB_DIR:-}"
    local short="${SHORT_FLEXRIC_LIB:-/var/tmp/oai-flexric-lib}"
    local need_sync=0

    if [ -z "$src" ]; then
        if [ -n "$project_dir" ]; then
            src="$project_dir/flexric-lib"
        else
            src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/flexric-lib"
        fi
    fi
    [[ "$src" == */ ]] && src="${src%/}"
    [[ "$short" == */ ]] && short="${short%/}"

    if [ ! -d "$src" ] || [ ! -f "$src/libkpm_sm.so" ]; then
        echo "ERRO: SMs ausentes em $src (libkpm_sm.so). Rode: ./scripts/sync_flexric_lib.sh" >&2
        return 1
    fi

    # Override explícito (SMs do sistema podem crashar com AMF Region ID 128)
    if [ "${FLEXRIC_USE_USR_LOCAL:-0}" = "1" ] && [ -f /usr/local/lib/flexric/libkpm_sm.so ]; then
        FLEXRIC_LIB="/usr/local/lib/flexric/"
        export FLEXRIC_LIB
        return 0
    fi

    # Path curto do próprio projeto: ok se acessível e < 128
    if [ "${#src}" -lt 127 ] && [ -r "$src" ]; then
        if sudo -n test -r "$src/libkpm_sm.so" 2>/dev/null || test -r "$src/libkpm_sm.so"; then
            # Verificar se root consegue ler (nr-softmodem roda com sudo)
            if sudo -n test -r "$src/libkpm_sm.so" 2>/dev/null; then
                FLEXRIC_LIB="${src}/"
                export FLEXRIC_LIB
                return 0
            fi
        fi
    fi

    # Materializar cópia em dir curto (não symlink — root precisa ler sem atravessar $HOME)
    if [ -L "$short" ]; then
        rm -f "$short" 2>/dev/null || sudo -n rm -f "$short" 2>/dev/null || true
    fi
    mkdir -p "$short" 2>/dev/null || sudo -n mkdir -p "$short" 2>/dev/null || {
        echo "ERRO: não foi possível criar $short" >&2
        return 1
    }

    if [ ! -f "$short/libkpm_sm.so" ] || \
       [ "$src/libkpm_sm.so" -nt "$short/libkpm_sm.so" ] || \
       [ "$(stat -c '%s' "$src/libkpm_sm.so" 2>/dev/null || echo 0)" != "$(stat -c '%s' "$short/libkpm_sm.so" 2>/dev/null || echo 1)" ]; then
        need_sync=1
    fi

    if [ "$need_sync" = "1" ]; then
        if cp -f "$src"/*.so "$short/" 2>/dev/null; then
            :
        elif sudo -n cp -f "$src"/*.so "$short/" 2>/dev/null; then
            :
        else
            echo "ERRO: falha ao copiar SMs $src → $short (precisa permissão de escrita)" >&2
            return 1
        fi
        chmod a+rX "$short" "$short"/*.so 2>/dev/null || \
            sudo -n chmod a+rX "$short" "$short"/*.so 2>/dev/null || true
    fi

    if [ ! -f "$short/libkpm_sm.so" ]; then
        echo "ERRO: $short/libkpm_sm.so ausente após sync" >&2
        return 1
    fi

    # Confirmar leitura como root (mesmo contexto do nr-softmodem)
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        if ! sudo -n test -r "$short/libkpm_sm.so" 2>/dev/null; then
            echo "ERRO: root não consegue ler $short/libkpm_sm.so" >&2
            return 1
        fi
    fi

    FLEXRIC_LIB="${short}/"
    if [ "${#FLEXRIC_LIB}" -ge 128 ]; then
        echo "ERRO: FLEXRIC_LIB ainda tem ${#FLEXRIC_LIB} chars (>=128): $FLEXRIC_LIB" >&2
        return 1
    fi
    export FLEXRIC_LIB
}

# Se sourced, não executa sozinho; se chamado, imprime o path.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    _resolve_flexric_sm_dir "$PROJECT_DIR"
    printf '%s\n' "$FLEXRIC_LIB"
fi
