#!/bin/bash
# Validate/preflight Fase 3 SMO/OAM scaffold.

set -euo pipefail

MODE="${1:-}"
SMO_OAM_DIR="${SMO_OAM_DIR:-}"
SMO_MODE="${SMO_MODE:-local}"
SMO_PROJECT_NAME="${SMO_PROJECT_NAME:-oai-smo-lab}"
SMO_WITH_NETWORK="${SMO_WITH_NETWORK:-0}"
SMO_WITH_TEIV="${SMO_WITH_TEIV:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

die() {
    echo "ERRO: $*" >&2
    exit 1
}

check_file() {
    local rel="$1"
    local required="${2:-1}"
    local file="$SMO_OAM_DIR/$rel"
    if [ -f "$file" ]; then
        echo "  OK  $rel"
    elif [ "$required" = "1" ]; then
        echo "  FALTA $rel"
        return 1
    else
        echo "  opcional ausente $rel"
    fi
}

compose_files=()
add_compose_file() {
    local rel="$1"
    local required="${2:-1}"
    local file="$SMO_OAM_DIR/$rel"
    if [ -f "$file" ]; then
        compose_files+=("-f" "$file")
    elif [ "$required" = "1" ]; then
        die "compose obrigatorio ausente: $file"
    fi
}

echo "=========================================="
echo "Teste Fase 3 SMO/OAM"
echo "=========================================="

if [ "$SMO_MODE" = "local" ]; then
    echo ""
    echo "=== Modo local SMO-lite ==="
    echo "Topologia: $PROJECT_DIR/config/smo/topology.lab.json"
    [ -f "$PROJECT_DIR/config/smo/topology.lab.json" ] || die "topologia local ausente"
    echo "  OK topology.lab.json"
    echo ""
    echo "=== Fluxo IA/A1 ==="
    python3 -m unittest discover -s "$PROJECT_DIR/tests" -v
    echo ""
    echo "=== Snapshot das interfaces abertas ==="
    "$SCRIPT_DIR/smo_lab_snapshot.sh"
    echo ""
    echo "Teste Fase 3 local concluido."
    exit 0
fi

[ "$SMO_MODE" = "external" ] || die "SMO_MODE invalido: $SMO_MODE (use local ou external)"
command -v docker >/dev/null 2>&1 || die "docker nao encontrado"
[ -n "$SMO_OAM_DIR" ] || die "defina SMO_OAM_DIR=/path/para/o-ran-sc-oam"
[ -d "$SMO_OAM_DIR" ] || die "SMO_OAM_DIR nao existe: $SMO_OAM_DIR"

echo ""
echo "=== Preflight arquivos ==="
missing=0
check_file "infra/docker-compose.yaml" 1 || missing=1
check_file "smo/common/docker-compose.yaml" 1 || missing=1
check_file "smo/oam/docker-compose.yaml" 1 || missing=1
check_file "network/docker-compose.yaml" 0 || true
check_file "smo/teiv/docker-compose.yaml" 0 || true

if [ "$missing" = "1" ]; then
    die "checkout SMO/OAM incompleto para este scaffold"
fi

echo ""
echo "=== Portas potencialmente sensiveis ==="
for port in 8080 8081 8181 8443 9092 2181; do
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$port$"; then
        echo "  porta $port em uso"
    else
        echo "  porta $port livre"
    fi
done

if [ "$MODE" = "--preflight" ]; then
    echo ""
    echo "Preflight concluido."
    exit 0
fi

add_compose_file "infra/docker-compose.yaml" 1
add_compose_file "smo/common/docker-compose.yaml" 1
add_compose_file "smo/oam/docker-compose.yaml" 1

if [ "$SMO_WITH_NETWORK" = "1" ]; then
    add_compose_file "network/docker-compose.yaml" 0
fi

if [ "$SMO_WITH_TEIV" = "1" ]; then
    add_compose_file "smo/teiv/docker-compose.yaml" 0
fi

echo ""
echo "=== Containers SMO ==="
docker compose -p "$SMO_PROJECT_NAME" "${compose_files[@]}" ps

echo ""
echo "=== Dicas de logs ==="
echo "docker compose -p $SMO_PROJECT_NAME <compose files> logs --tail=80"
echo ""
echo "Teste Fase 3 concluido."
