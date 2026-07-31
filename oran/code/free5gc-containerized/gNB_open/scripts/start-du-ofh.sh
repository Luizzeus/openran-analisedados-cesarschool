#!/usr/bin/env bash
# Inicia o srsDU usando o perfil Open Fronthaul (ru_ofh) com RU emulada (ru_emulator).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CFG="${1:-du-ofh-ru-emulator.yml}"

if ! docker ps --format '{{.Names}}' | grep -qx srsran-du; then
  echo "Erro: o contentor srsran-du não está em execução."
  echo "  Suba o stack: ./scripts/up.sh"
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx srsran-ru; then
  echo "Erro: o contentor srsran-ru não está em execução."
  echo "  Suba o stack: ./scripts/up.sh"
  exit 1
fi

echo "Dica: confirme MACs do link OFH antes (opcional): ./scripts/verify-ofh.sh"
echo "Iniciando srsDU (ru_ofh) com ${CFG}..."
exec docker exec -it srsran-du sh -lc "
set -eu
CFG='/etc/srsran/${CFG}'
DU_OFH_MAC=\"\${DU_OFH_MAC:-02:00:00:00:01:02}\"
OFH_IFACE=\$(ip -o link show | awk -v mac=\"\${DU_OFH_MAC}\" 'tolower(\$0) ~ tolower(mac) { gsub(\":\", \"\", \$2); print \$2; exit }')
if [ -n \"\${OFH_IFACE}\" ]; then
  echo \"[info] OFH interface detected by MAC \${DU_OFH_MAC}: \${OFH_IFACE}\"
  sed \"s/^\\([[:space:]]*network_interface:[[:space:]]*\\).*/\\1\${OFH_IFACE}/\" \"\${CFG}\" > /tmp/du-ofh-runtime.yml
  exec srsdu -c /tmp/du-ofh-runtime.yml
fi
echo \"[warn] OFH interface with MAC \${DU_OFH_MAC} not found; using \${CFG}\"
exec srsdu -c \"\${CFG}\"
"
