#!/usr/bin/env bash
# Inicia o srsdu DEPOIS do srsUE — o UE tem de estar à escuta na porta UL (TCP) antes do DU
# ligar a host.docker.internal nessa porta.
#
# Defeito gNB_open: UL **2003** (DL 2002) — ver configs/ZMQ_PORTS.md e configs/ue_srsue.conf.
# Se mudar portas no YAML/UE, exporte: UE_ZMQ_UL_PORT=...
#
# Uso (ordem obrigatória):
#   1) ./scripts/start-cu.sh
#   2) srsue configs/ue_srsue.conf   ← PRIMEIRO (outro terminal, deixe correr)
#   3) ./scripts/start-du-after-ue.sh
# Se o DU arrancar antes do srsUE, o ZMQ UL pode ficar inválido e o UE fica em «Attaching…».
#
# Variável opcional: DU_CONFIG (default du-zmq-srsue.yml) — tem de coincidir com ./scripts/up.sh
# REQUIRE_SRSUE_RUNNING=0 — desativa a verificação do processo srsue (só para depuração).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=/dev/null
. "${ROOT}/scripts/lib-zmq-du-runtime.sh"

CFG="${DU_CONFIG:-du-zmq-srsue.yml}"
UE_PORT="${UE_ZMQ_UL_PORT:-2003}"
TIMEOUT_SEC="${WAIT_UE_SEC:-180}"

if ! docker ps --format '{{.Names}}' | grep -qx srsran-du; then
  echo "Erro: o contentor srsran-du não está em execução."
  echo "  Suba o RAN:  ./scripts/up.sh   (com DU_AUTO_START=0 por defeito)"
  exit 1
fi

if docker ps --format '{{.Names}}' | grep -qx srsran-cu; then
  if ! docker exec srsran-cu pgrep srscu >/dev/null 2>&1; then
    echo "Aviso: o srscu não parece estar a correr no srsran-cu. O F1 falha sem o CU."
    echo "  Execute primeiro:  ./scripts/start-cu.sh"
  fi
fi

if [ "${REQUIRE_SRSUE_RUNNING:-1}" != "0" ]; then
  if ! pgrep -x srsue >/dev/null 2>&1; then
    echo "Erro: não há processo «srsue» no host."
    echo "  Arranque PRIMEIRO o srsUE noutro terminal e só depois este script:"
    echo "    srsue configs/ue_srsue.conf"
    echo "  Ordem: CU → srsUE → DU (este script). Se o DU subir antes do UE, pare o srsdu (Ctrl+C) e repita."
    exit 1
  fi
fi

port_ready() {
  local p=$1
  if command -v nc >/dev/null 2>&1; then
    nc -z -w1 127.0.0.1 "$p" 2>/dev/null && return 0
  fi
  if command -v ss >/dev/null 2>&1; then
    ss -tlnH 2>/dev/null | grep -qE ":${p}\s" && return 0
    ss -tlnH 2>/dev/null | grep -qE ":${p}\]" && return 0
  fi
  (echo >/dev/tcp/127.0.0.1/"${p}") 2>/dev/null
}

echo "À espera do srsUE em 127.0.0.1:${UE_PORT} (até ${TIMEOUT_SEC}s)…"
echo "  Noutro terminal:  srsue configs/ue_srsue.conf"
echo "  Espere até «Waiting PHY… done!» / «Attaching UE…» (o bind na ${UE_PORT} costuma aparecer aí)."
echo ""

n=0
while ! port_ready "${UE_PORT}"; do
  n=$((n + 1))
  if [ "$((n % 20))" -eq 0 ]; then
    echo "  … ainda à espera (${n}s)"
  fi
  if [ "$n" -ge "$TIMEOUT_SEC" ]; then
    echo "Timeout: a porta ${UE_PORT} não abriu. Confirme srsUE com o mesmo ue_srsue.conf (UL=${UE_PORT})."
    echo "  Conflitos: gNB_traditional usa 2000/2001; gNB_open usa 2002/2003 — ver configs/ZMQ_PORTS.md"
    exit 1
  fi
  sleep 1
done

echo "Porta ${UE_PORT} detetada — a iniciar srsdu (${CFG})…"
YML_IN_CONTAINER="$(prepare_du_yaml_for_container "$ROOT" "$CFG")"
exec docker exec -it srsran-du srsdu -c "${YML_IN_CONTAINER}"

