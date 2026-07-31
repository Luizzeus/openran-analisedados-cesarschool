#!/usr/bin/env bash
# SOBE apenas o gNB integrado. Exige core já rodando (rede free5gc-privnet).
set -euo pipefail

# 1 = inicia gnb no entrypoint (necessário para srsUE; sem isto o container fica idle e o UE fica em «Attaching UE...»).
# 0 = só sobe o container; use para exec manual: docker exec -it srsran-gnb-tradicional gnb -c /etc/srsran/gnb-zmq-srsue.yml
GNB_AUTO_START="${GNB_AUTO_START:-1}"
GNB_CONFIG="${GNB_CONFIG:-gnb-zmq-srsue.yml}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=../../core/scripts/lib/srsran-image.sh
. "${ROOT}/../core/scripts/lib/srsran-image.sh"

NET=free5gc-privnet
if ! docker network inspect "$NET" >/dev/null 2>&1; then
  echo "Rede Docker \"$NET\" não existe."
  echo "Inicie o core primeiro:  cd ../core && ./scripts/up.sh"
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qxE 'amf|mongodb'; then
  echo "Aviso: containers típicos do core (ex.: amf) não parecem estar ativos."
  echo "Confirme: cd ../core && docker compose ps"
fi

echo "Subindo RAN tradicional (srsran-gnb-tradicional)..."
mkdir -p logs
ensure_srsran_image
GNB_CONFIG="${GNB_CONFIG}" GNB_AUTO_START="${GNB_AUTO_START}" SRSRAN_IMAGE="${SRSRAN_IMAGE}" docker compose up -d
docker compose ps
