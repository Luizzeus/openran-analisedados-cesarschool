#!/usr/bin/env bash
# Confirma que o CU/DU têm os IPs esperados na rede free5gc-privnet.
# Se o AMF mostrar outro IP (ex.: 10.100.200.11) para o RAN, o compose não está a aplicar ipv4_address.
set -euo pipefail

echo "=== srsran-cu (esperado: 10.100.200.51) ==="
if docker ps --format '{{.Names}}' | grep -qx srsran-cu; then
  docker exec srsran-cu ip -4 addr show eth0 | sed -n '1,6p'
else
  echo "Container srsran-cu não está em execução."
fi

echo ""
echo "=== srsran-du (esperado: 10.100.200.52) ==="
if docker ps --format '{{.Names}}' | grep -qx srsran-du; then
  docker exec srsran-du ip -4 addr show eth0 | sed -n '1,6p'
else
  echo "Container srsran-du não está em execução."
fi

echo ""
echo "=== amf (esperado: 10.100.200.16) ==="
if docker ps --format '{{.Names}}' | grep -qx amf; then
  docker exec amf ip -4 addr show eth0 2>/dev/null | sed -n '1,6p' || true
fi

echo ""
echo "Nos logs do AMF, o endereço do RAN deve coincidir com o IP do CU (10.100.200.51)."
echo "Se vir 10.100.200.11 ou outro, recrie: cd gNB_disaggregated && ./scripts/down.sh && ./scripts/up.sh"
