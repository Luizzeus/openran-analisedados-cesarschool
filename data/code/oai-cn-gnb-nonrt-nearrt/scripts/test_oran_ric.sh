#!/bin/bash
# Valida nearRT O-RAN SC + (opcional) nonRT perfil oran + E2 no gNB.
# Uso: ./scripts/test_oran_ric.sh [--run-xapp]
#
# Por defeito NÃO executa xApp (evita bloqueio — xApp corre em loop infinito).
# Com --run-xapp: tenta subscription KPM (~12s, com timeout).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORAN_VENDOR="${ORAN_VENDOR_DIR:-$PROJECT_DIR/vendor/oran-sc-ric}"
ORAN_CFG="${ORAN_CFG_DIR:-$PROJECT_DIR/config/oran-ric}"
LOG_DIR="${OAI_LOG_DIR:-$PROJECT_DIR/logs}"
A1_PORT="${A1MEDIATOR_HOST_PORT:-10000}"
E2_PORT="${ORAN_E2_HOST_PORT:-36422}"
PMS_PORT="${NONRT_PMS_HTTP_PORT:-8081}"
RUN_XAPP=0

for arg in "$@"; do
    case "$arg" in
        --run-xapp) RUN_XAPP=1 ;;
        -h|--help)
            echo "Uso: $0 [--run-xapp]"
            exit 0
            ;;
    esac
done

compose() {
    docker compose \
        -f "$ORAN_VENDOR/docker-compose.yml" \
        -f "$ORAN_CFG/docker-compose.override.yml" \
        --env-file "$ORAN_VENDOR/.env" \
        --env-file "$ORAN_CFG/.env" \
        "$@"
}

check() {
    local label="$1"
    shift
    echo -n "  $label ... "
    if "$@" >/dev/null 2>&1; then
        echo "OK"
        return 0
    fi
    echo "FALHOU"
    return 1
}

echo "=========================================="
echo "Teste O-RAN SC — Fase 2"
echo "=========================================="

echo ""
echo "=== Containers nearRT ==="
if ! compose ps 2>/dev/null | grep -q ric_e2term; then
    echo "  nearRT não está rodando. Execute: ./scripts/up_oran_ric.sh"
    exit 1
fi
compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | sed 's/^/  /'

echo ""
echo "=== Health checks ==="
check "ric_e2term running" docker inspect -f '{{.State.Running}}' ric_e2term
check "ric_a1mediator running" docker inspect -f '{{.State.Running}}' ric_a1mediator
echo -n "  A1 mediator TCP :$A1_PORT ... "
if bash -c "exec 3<>/dev/tcp/127.0.0.1/$A1_PORT" 2>/dev/null; then
    echo "OK"
else
    echo "FALHOU"
fi

if curl -sf "http://127.0.0.1:$PMS_PORT/status" 2>/dev/null | grep -qi "hunky dory"; then
    echo "  PMS (perfil oran) ... OK"
    echo ""
    echo "=== RIC no PMS (perfil oran) ==="
    curl -sf "http://127.0.0.1:$PMS_PORT/a1-policy/v2/rics" 2>/dev/null | head -c 400 || true
    echo ""
else
    echo "  PMS (perfil oran) ... omitido"
fi

echo ""
echo "=== RNIB Redis (SDL) ==="
if docker inspect ric_dbaas >/dev/null 2>&1; then
    redis_ver=$(docker exec ric_dbaas redis-cli INFO server 2>/dev/null | grep '^redis_version:' | cut -d: -f2 | tr -d '\r' || echo "?")
    echo "  Redis version: $redis_ver"
    rnib_keys=$(docker exec ric_dbaas redis-cli KEYS '{e2Manager},RAN:gnb_*' 2>/dev/null | grep -c . || true)
    rnib_keys=${rnib_keys:-0}
    echo -n "  RAN entries no RNIB ... "
    if [ "$rnib_keys" -gt 0 ]; then
        echo "OK ($rnib_keys)"
        docker exec ric_dbaas redis-cli KEYS '{e2Manager},RAN:gnb_*' 2>/dev/null | sed 's/^/    /'
    else
        echo "vazio"
    fi
    redis_err=$(docker logs ric_e2mgr 2>&1 | grep -c 'COMMAND reply' 2>/dev/null || true)
    redis_err=${redis_err:-0}
    if [ "${redis_err}" -gt 0 ] 2>/dev/null; then
        echo "  AVISO: e2mgr ainda reporta erros Redis COMMAND ($redis_err) — use DBAAS_VER=0.5.0"
    else
        echo "  e2mgr Redis SDL ... OK (sem erros COMMAND)"
    fi
fi

echo ""
echo "=== E2 no gNB ==="
if [ -f "$LOG_DIR/gnb_oai_oran.log" ]; then
    if grep -qiE 'E2 SETUP|E2 setup|RIC.*setup|Connected.*RIC' "$LOG_DIR/gnb_oai_oran.log" 2>/dev/null; then
        echo "  E2 SETUP detectado no log — OK"
        grep -iE "E2 SETUP|E2 setup|nearRT-RIC|PORT = $E2_PORT|near_ric" "$LOG_DIR/gnb_oai_oran.log" 2>/dev/null | tail -5 | sed 's/^/    /'
    else
        echo "  E2 SETUP não encontrado — ./scripts/up_gnb_oai_oran.sh"
    fi
else
    echo "  gNB oran não iniciado — ./scripts/up_gnb_oai_oran.sh"
fi

e2_node_id=""
if [ -x "$SCRIPT_DIR/get_oran_e2_node_id.sh" ]; then
    e2_node_id=$("$SCRIPT_DIR/get_oran_e2_node_id.sh" 2>/dev/null) || true
fi
if [ -n "$e2_node_id" ]; then
    echo ""
    echo "=== E2 Node ID (RNIB) ==="
    echo "  $e2_node_id"
    echo -n "  e2mgr e2t list ... "
    e2t_json=$(docker exec ric_e2mgr curl -sf http://localhost:3800/v1/e2t/list 2>/dev/null || echo "[]")
    if echo "$e2t_json" | grep -q "$e2_node_id"; then
        echo "associado"
    else
        echo "não associado (reinicie gNB: ./scripts/up_gnb_oai_oran.sh)"
    fi
fi

echo ""
if [ "$RUN_XAPP" = "1" ]; then
    echo "=== xApp KPM (12s max) ==="
    if compose ps -q python_xapp_runner 2>/dev/null | grep -q .; then
        node="${e2_node_id:-gnb_208_095_00000e00}"
        echo "  Node: $node"
        "$SCRIPT_DIR/stop_xapp_oai_kpm.sh" >/dev/null 2>&1 || true
        xapp_log="$LOG_DIR/test_oran_ric_xapp.log"
        : > "$xapp_log"
        set +e
        timeout --signal=TERM --kill-after=5 25 docker compose \
            -f "$ORAN_VENDOR/docker-compose.yml" \
            -f "$ORAN_CFG/docker-compose.override.yml" \
            --env-file "$ORAN_VENDOR/.env" \
            --env-file "$ORAN_CFG/.env" \
            exec -T -e PYTHONUNBUFFERED=1 python_xapp_runner \
            python3 ./simple_xapp_oai.py --e2_node_id="$node" \
            --http_server_port=8092 --rmr_port=4562 \
            --metrics=DRB.UEThpDl,DRB.UEThpUl > "$xapp_log" 2>&1
        xapp_rc=$?
        set -e
        tail -25 "$xapp_log" | sed 's/^/  /'
        if grep -qiE 'RIC Indication|UEThp|Successfully|Subscribe OAI' "$xapp_log"; then
            echo "  xApp KPM apresentou atividade (log: $xapp_log)"
        elif [ "$xapp_rc" -eq 124 ] || [ "$xapp_rc" -eq 137 ] || [ "$xapp_rc" -eq 143 ]; then
            echo "  xApp encerrado por timeout sem INDICATION visível (log: $xapp_log)"
        else
            echo "  xApp terminou com código $xapp_rc (log: $xapp_log)"
        fi
    else
        echo "  python_xapp_runner não disponível"
    fi
else
    echo "=== xApp KPM ==="
    echo "  Omitido (xApp corre em loop). Use: $0 --run-xapp"
fi

echo ""
echo "Teste Fase 2 concluído."
