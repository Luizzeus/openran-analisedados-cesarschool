#!/usr/bin/env bash
# Diagnóstico rápido ZMQ (gNB_disaggregated): rede Docker, portas no host, teste ao UL a partir do DU.
set -euo pipefail
NET="${1:-free5gc-privnet}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Rede ${NET} ==="
docker network inspect "$NET" -f '{{range .IPAM.Config}}{{.Subnet}} gateway={{.Gateway}}{{end}}' 2>/dev/null || echo "Rede não encontrada."

echo ""
echo "=== Contentores srsran-* ==="
docker ps -a --filter name=srsran --format '{{.Names}}	{{.Status}}'

echo ""
echo "=== Portas TCP no host (2002 DL / 2003 UL gNB_disaggregated) ==="
ss -tlnH 2>/dev/null | grep -E ':200[23]\s' || echo "(nada à escuta ou ss indisponível)"

echo ""
echo "=== Teste: DU → gateway → porta UL (precisa srsUE a correr na 2003) ==="
GW=$(docker network inspect "$NET" -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)
if [[ -n "$GW" ]] && docker ps --format '{{.Names}}' | grep -qx srsran-du; then
  echo "Gateway: ${GW}"
  docker exec srsran-du sh -c "command -v nc >/dev/null && nc -z -w2 ${GW} 2003 && echo OK: TCP ${GW}:2003 alcançável a partir do DU || echo FALHOU: ${GW}:2003"
else
  echo "Sem srsran-du ou sem gateway — suba: cd ${ROOT} && ./scripts/up.sh"
fi

echo ""
echo "Use ./scripts/start-du-after-ue.sh (substitui host.docker.internal pelo gateway ao arrancar o srsdu)."
