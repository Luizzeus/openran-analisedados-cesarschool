#!/usr/bin/env bash
# SOBE srsCU + srsDU (split F1). Exige core já rodando (rede free5gc-privnet).
# Ordem: CU primeiro, DU em seguida (depends_on no compose).
set -euo pipefail

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
  echo "Aviso: containers típicos do core não parecem estar ativos."
  echo "Confirme: cd ../core && docker compose ps"
fi

DU_CONFIG="${DU_CONFIG:-du-zmq-srsue.yml}"
# 0 = arranque manual. 1 = binário no entrypoint.
CU_AUTO_START="${CU_AUTO_START:-0}"
DU_AUTO_START="${DU_AUTO_START:-0}"
export CU_AUTO_START DU_CONFIG DU_AUTO_START
echo "Subindo RAN aberto (srsran-cu + srsran-du)… CU_AUTO_START=${CU_AUTO_START} DU_CONFIG=${DU_CONFIG} DU_AUTO_START=${DU_AUTO_START}"
if [ "${CU_AUTO_START}" = "0" ] || [ "${DU_AUTO_START}" = "0" ]; then
  echo ""
  echo "Arranque manual (defeito):"
  echo "  1) ./scripts/start-cu.sh          # srscu → N2 (AMF); ver logs/cu.log e AMF"
  echo "  2) srsue configs/ue_srsue.conf  # (ZMQ) terminal seguinte"
  echo "  3) ./scripts/start-du-after-ue.sh   # ou ./scripts/run-du.sh (ZMQ; ru_dummy: só run-du sem srsUE)"
  echo "  Para arrancar srscu/srsdu dentro dos contentores: CU_AUTO_START=1 e/ou DU_AUTO_START=1 antes de ./scripts/up.sh"
  echo ""
fi
mkdir -p logs
ensure_srsran_image
docker compose up -d
docker compose ps
