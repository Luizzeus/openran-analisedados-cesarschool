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
RU_AUTO_START="${RU_AUTO_START:-0}"
export CU_AUTO_START DU_CONFIG DU_AUTO_START RU_AUTO_START

echo "Subindo RAN aberta (CU+DU+RU opcional)…"
echo "  CU_AUTO_START=${CU_AUTO_START}  DU_CONFIG=${DU_CONFIG}  DU_AUTO_START=${DU_AUTO_START}  RU_AUTO_START=${RU_AUTO_START}"

echo ""
echo "Perfis de DU disponíveis (configs/):"
echo "  - du.yml                   (ru_dummy — lab F1 sem UE/RU)"
echo "  - du-zmq-srsue.yml          (ZMQ — srsUE no host)"
echo "  - du-ofh-ru-emulator.yml    (Open Fronthaul — RU emulada em srsran-ru)"

if [ "${CU_AUTO_START}" = "0" ] || [ "${DU_AUTO_START}" = "0" ] || [ "${RU_AUTO_START}" = "0" ]; then
  echo ""
  echo "Arranque manual (defeito):"
  echo "  - CU:  ./scripts/start-cu.sh"
  echo "  - DU (ZMQ):     srsue configs/ue_srsue.conf  (host)  →  ./scripts/start-du-after-ue.sh"
  echo "  - DU (ru_dummy): ./scripts/run-du.sh du.yml"
  echo "  - OFH (RU emulada): ./scripts/start-ru-emulator.sh  →  ./scripts/start-du-ofh.sh"
  echo ""
fi

echo "Arranque automático (tudo dentro dos containers):"
echo "  - ru_dummy:"
echo "      DU_CONFIG=du.yml CU_AUTO_START=1 DU_AUTO_START=1 bash ./scripts/up.sh"
echo "  - ZMQ (sem ordem manual):"
echo "      DU_CONFIG=du-zmq-srsue.yml CU_AUTO_START=1 DU_AUTO_START=1 bash ./scripts/up.sh"
echo "  - Open Fronthaul (RU emulada):"
echo "      DU_CONFIG=du-ofh-ru-emulator.yml CU_AUTO_START=1 DU_AUTO_START=1 RU_AUTO_START=1 bash ./scripts/up.sh"
echo ""
echo "Nota: para ZMQ (srsUE), o modo manual é mais confiável (ordem CU → UE → DU)."

mkdir -p logs
ensure_srsran_image
docker compose up -d
docker compose ps
