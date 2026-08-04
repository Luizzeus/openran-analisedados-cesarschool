#!/bin/bash
# Start Fase 3 SMO/OAM from an external O-RAN SC OAM checkout.
# This script is intentionally conservative and does not stop Fase 1/2.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SMO_OAM_DIR="${SMO_OAM_DIR:-}"
SMO_MODE="${SMO_MODE:-local}"
SMO_PROJECT_NAME="${SMO_PROJECT_NAME:-oai-smo-lab}"
SMO_WITH_NETWORK="${SMO_WITH_NETWORK:-0}"
SMO_WITH_TEIV="${SMO_WITH_TEIV:-0}"
SMO_ALLOW_SHARED_HOST="${SMO_ALLOW_SHARED_HOST:-0}"
SMO_RUN_DIR="${SMO_RUN_DIR:-$PROJECT_DIR/logs/smo_lab_runtime}"

die() {
    echo "ERRO: $*" >&2
    exit 1
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

check_active_phase_stacks() {
    local active=0

    if pgrep -x "nearRT-RIC" >/dev/null 2>&1; then
        echo "Detectado FlexRIC nearRT-RIC ativo."
        active=1
    fi

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -Eq '^(nonrt-|a1-sim-|ric_)'; then
        echo "Detectados containers Fase 1/Fase 2 ativos."
        docker ps --format '  {{.Names}}' | grep -E '^(  nonrt-|  a1-sim-|  ric_)' || true
        active=1
    fi

    if [ "$active" = "1" ] && [ "$SMO_ALLOW_SHARED_HOST" != "1" ]; then
        die "abortei para nao interferir nas Fases 1/2. Pare-as ou use SMO_ALLOW_SHARED_HOST=1 apos revisar portas."
    fi
}

if [ "$SMO_MODE" = "local" ]; then
    mkdir -p "$SMO_RUN_DIR"
    cat > "$SMO_RUN_DIR/README.txt" <<EOF
Fase 3 SMO-lite local iniciada.

Este modo nao sobe containers SMO externos. Ele cria um ponto de integracao
operacional para:
- snapshots A1/E2/O1-simulado/O2
- eventos OAM/VES simulados
- correlacao posterior com KPM/xApps da Fase 2

Comandos:
  ./scripts/smo_lab_snapshot.sh
  ./scripts/smo_lab_event.sh MAJOR sim_o_du_001 HighPrbUl "UL PRB acima do limiar"
  ./scripts/test_smo_lab.sh
EOF
    echo "=========================================="
    echo "Fase 3 SMO-lite local iniciada"
    echo "=========================================="
    echo "run_dir=$SMO_RUN_DIR"
    echo ""
    echo "Coletar snapshot:"
    echo "  ./scripts/smo_lab_snapshot.sh"
    echo ""
    echo "Registrar evento OAM/VES simulado:"
    echo "  ./scripts/smo_lab_event.sh MAJOR sim_o_du_001 HighPrbUl \"UL PRB acima do limiar\""
    echo ""
    echo "Validar:"
    echo "  ./scripts/test_smo_lab.sh"
    exit 0
fi

[ "$SMO_MODE" = "external" ] || die "SMO_MODE invalido: $SMO_MODE (use local ou external)"
command -v docker >/dev/null 2>&1 || die "docker nao encontrado"
check_active_phase_stacks
[ -n "$SMO_OAM_DIR" ] || die "defina SMO_OAM_DIR=/path/para/o-ran-sc-oam"
[ -d "$SMO_OAM_DIR" ] || die "SMO_OAM_DIR nao existe: $SMO_OAM_DIR"

add_compose_file "infra/docker-compose.yaml" 1
add_compose_file "smo/common/docker-compose.yaml" 1
add_compose_file "smo/oam/docker-compose.yaml" 1

if [ "$SMO_WITH_NETWORK" = "1" ]; then
    add_compose_file "network/docker-compose.yaml" 0
fi

if [ "$SMO_WITH_TEIV" = "1" ]; then
    add_compose_file "smo/teiv/docker-compose.yaml" 0
fi

echo "Subindo Fase 3 SMO/OAM"
echo "  SMO_OAM_DIR=$SMO_OAM_DIR"
echo "  project=$SMO_PROJECT_NAME"
echo "  compose files:"
printf '    %s\n' "${compose_files[@]}" | sed '/^-f$/d'

docker compose -p "$SMO_PROJECT_NAME" "${compose_files[@]}" up -d

echo ""
echo "SMO/OAM iniciado. Validar com:"
echo "  SMO_OAM_DIR=$SMO_OAM_DIR ./scripts/test_smo_lab.sh"
echo ""
echo "Parar com:"
echo "  SMO_OAM_DIR=$SMO_OAM_DIR ./scripts/down_smo_lab.sh"
