#!/bin/bash
# Recria dbaas com Redis 5.x e reinicia componentes que usam RNIB/SDL.
# Corrige: redis: got 7 elements in COMMAND reply, wanted 6
#
# Uso: ./scripts/fix_oran_ric_rnib.sh
# Depois: ./scripts/up_gnb_oai_oran.sh && ./scripts/test_oran_ric.sh

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

echo "=========================================="
echo "Corrigir RNIB — Redis 5.x (dbaas 0.5.0)"
echo "=========================================="

"$SCRIPT_DIR/down_gnb_oai.sh" 2>/dev/null || true

echo "A recriar dbaas e reiniciar e2mgr/submgr/a1mediator..."
cd "$ORAN_VENDOR"
compose stop e2mgr submgr a1mediator policy-agent 2>/dev/null || true
compose rm -f dbaas 2>/dev/null || true
compose up -d --force-recreate dbaas
sleep 3
compose up -d --force-recreate e2mgr submgr a1mediator
sleep 5

echo ""
echo "Redis: $(docker exec ric_dbaas redis-cli INFO server 2>/dev/null | grep '^redis_version:' | tr -d '\r' || echo '?')"
if docker logs ric_e2mgr 2>&1 | tail -5 | grep -q 'COMMAND reply'; then
    echo "AVISO: erros COMMAND ainda presentes nos logs do e2mgr."
else
    echo "e2mgr: sem erros Redis COMMAND nos logs recentes."
fi

echo ""
echo "Próximo: ./scripts/up_gnb_oai_oran.sh && ./scripts/test_oran_ric.sh"
