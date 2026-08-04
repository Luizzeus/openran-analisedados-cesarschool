#!/bin/bash
# Encerra xApps Python órfãos no container python_xapp_runner (libera HTTP/RMR).
# Uso: ./scripts/stop_xapp_oai_kpm.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORAN_VENDOR="${ORAN_VENDOR_DIR:-$PROJECT_DIR/vendor/oran-sc-ric}"
ORAN_CFG="${ORAN_CFG_DIR:-$PROJECT_DIR/config/oran-ric}"

compose() {
    docker compose \
        -f "$ORAN_VENDOR/docker-compose.yml" \
        -f "$ORAN_CFG/docker-compose.override.yml" \
        --env-file "$ORAN_VENDOR/.env" \
        --env-file "$ORAN_CFG/.env" \
        "$@"
}

if ! compose ps -q python_xapp_runner 2>/dev/null | grep -q .; then
    echo "python_xapp_runner não está rodando."
    exit 0
fi

echo "Parando xApps no container python_xapp_runner..."
compose exec -T python_xapp_runner sh -c '
killed=0
kill_xapps() {
    sig=$1
    for f in /proc/[0-9]*/cmdline; do
        pid=${f#/proc/}
        pid=${pid%/cmdline}
        [ "$pid" = "1" ] && continue
        cmd=$(tr "\0" " " < "$f" 2>/dev/null || true)
        case "$cmd" in
            python3\ ./simple_xapp*|python3\ ./simple_xapp_oai*|python3\ ./simple_mon_xapp*|python3\ ./kpm_mon_xapp*)
                kill $sig "$pid" 2>/dev/null && killed=$((killed+1)) || true
                ;;
        esac
    done
}
kill_xapps TERM
sleep 0.5
kill_xapps -9
echo "Processos xApp encerrados: $killed"
'
