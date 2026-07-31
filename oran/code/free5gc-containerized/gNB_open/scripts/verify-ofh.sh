#!/usr/bin/env bash
# Verifica a interface OFH dentro dos containers (rede `ofhnet`) e mostra as MACs.
set -euo pipefail

echo "=== DU (srsran-du): interfaces ==="
if docker ps --format '{{.Names}}' | grep -qx srsran-du; then
  docker exec srsran-du sh -lc 'ip -br link && echo --- && ip -br addr'
else
  echo "Container srsran-du não está em execução."
fi

echo ""
echo "=== RU (srsran-ru): interfaces ==="
if docker ps --format '{{.Names}}' | grep -qx srsran-ru; then
  docker exec srsran-ru sh -lc 'ip -br link && echo --- && ip -br addr'
else
  echo "Container srsran-ru não está em execução."
fi

echo ""
echo "=== Observação ==="
echo "O arquivo configs/du-ofh-ru-emulator.yml usa:"
echo "  ru_mac_addr: 02:00:00:00:01:01"
echo "  du_mac_addr: 02:00:00:00:01:02"
echo "Confirme se essas MACs batem com:"
echo "  RU: MAC da eth0 (srsran-ru)"
echo "  DU: interface com MAC 02:00:00:00:01:02 (o entrypoint ajusta o YAML para esta interface)"
