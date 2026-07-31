#!/bin/sh
set -eu

AMF_IP="${AMF_IP:-10.100.200.16}"
CU_CP_IP="${CU_CP_IP:-10.100.200.51}"

echo "$(date '+%Y-%m-%d %H:%M:%S')[wait] srsDU: aguardando AMF (${AMF_IP}) e CU-CP (${CU_CP_IP})..."
for i in $(seq 1 120); do
  ip link show eth0 >/dev/null 2>&1 &&
  ip route get "${AMF_IP}" >/dev/null 2>&1 &&
  ping -c1 -W1 "${AMF_IP}" >/dev/null 2>&1 &&
  ping -c1 -W1 "${CU_CP_IP}" >/dev/null 2>&1 && break
  sleep 0.25
done

echo "$(date '+%Y-%m-%d %H:%M:%S')[debug] ip a:"; ip a
echo "$(date '+%Y-%m-%d %H:%M:%S')[debug] ip r:"; ip r

BIN="$(command -v srsdu || true)"
[ -x "${BIN:-}" ] || { echo "FATAL: srsdu não encontrado (imagem srsRAN incompleta?)"; exit 127; }

DU_CONFIG="${DU_CONFIG:-du.yml}"
echo "$(date '+%Y-%m-%d %H:%M:%S')[info] srsDU config: ${DU_CONFIG}"
CONFIG_PATH="/etc/srsran/${DU_CONFIG}"

if grep -q "ru_ofh:" "${CONFIG_PATH}" 2>/dev/null; then
  DU_OFH_MAC="${DU_OFH_MAC:-02:00:00:00:01:02}"
  OFH_IFACE="$(ip -o link show | awk -v mac="${DU_OFH_MAC}" 'tolower($0) ~ tolower(mac) { gsub(":", "", $2); print $2; exit }')"
  if [ -n "${OFH_IFACE}" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S')[info] OFH interface detected by MAC ${DU_OFH_MAC}: ${OFH_IFACE}"
    sed "s/^\([[:space:]]*network_interface:[[:space:]]*\).*/\1${OFH_IFACE}/" "${CONFIG_PATH}" > /tmp/du-ofh-runtime.yml
    CONFIG_PATH="/tmp/du-ofh-runtime.yml"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S')[warn] OFH interface with MAC ${DU_OFH_MAC} not found; using ${CONFIG_PATH}"
  fi
fi

if [ "${DU_AUTO_START:-0}" = "0" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S')[info] DU_AUTO_START=0: srsdu NÃO foi iniciado (arranque manual)."
  echo "  Ordem sugerida: 1) ./scripts/start-cu.sh  2) srsue … (ZMQ)  3) ./scripts/start-du-after-ue.sh"
  echo "  ou: docker exec -it srsran-du srsdu -c /etc/srsran/${DU_CONFIG}"
  echo "  O container fica em espera (idle)."
  exec tail -f /dev/null
fi

exec "$BIN" -c "${CONFIG_PATH}"
