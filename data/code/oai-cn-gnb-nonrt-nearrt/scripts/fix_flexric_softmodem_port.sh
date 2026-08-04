#!/bin/bash
# Garante que ran_build/build/nr-softmodem conecta E2 em :36421 (Fase 1).
# Necessário quando build_e2_oran_sc.sh antigo sobrescreveu o binário FlexRIC
# com a porta 36422 (O-RAN SC) sem restaurar.
#
# Uso: ./scripts/fix_flexric_softmodem_port.sh
# Preferível a longo prazo: ./scripts/build_e2.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOFTMODEM="$PROJECT_DIR/openairinterface5g/cmake_targets/ran_build/build/nr-softmodem"

if [ ! -f "$SOFTMODEM" ]; then
    echo "ERRO: $SOFTMODEM ausente. Execute ./scripts/build_e2.sh"
    exit 1
fi

python3 - "$SOFTMODEM" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = bytearray(path.read_bytes())
# Região de init_agent_api neste binário PIE (VA == file offset)
start, end = 0xCEE810, 0xCEEC80
region = bytes(data[start:end])
n22_esi = region.count(bytes.fromhex("be468e0000"))
n21_esi = region.count(bytes.fromhex("be458e0000"))
n22_r9 = region.count(bytes.fromhex("41b9468e0000"))
n21_r9 = region.count(bytes.fromhex("41b9458e0000"))

print(f"Antes: mov $36422,%esi={n22_esi}  mov $36421,%esi={n21_esi}  r9d22={n22_r9} r9d21={n21_r9}")

if n22_esi == 0 and n21_esi >= 1 and n22_r9 == 0:
    print("OK: nr-softmodem já usa porta 36421 para e2_init_agent.")
    sys.exit(0)

bak = path.with_name(path.name + ".bak_port36422")
if not bak.exists():
    bak.write_bytes(path.read_bytes())
    print(f"Backup: {bak}")

def replace_all(buf: bytearray, old: bytes, new: bytes, lo: int, hi: int) -> int:
    n = 0
    i = lo
    while i < hi:
        j = bytes(buf[i:hi]).find(old)
        if j < 0:
            break
        abs_j = i + j
        buf[abs_j : abs_j + len(old)] = new
        n += 1
        i = abs_j + len(new)
    return n

n = 0
n += replace_all(data, bytes.fromhex("be468e0000"), bytes.fromhex("be458e0000"), start, end)
n += replace_all(data, bytes.fromhex("41b9468e0000"), bytes.fromhex("41b9458e0000"), start, end)
if n == 0:
    print("ERRO: padrões de porta 36422 não encontrados — rode ./scripts/build_e2.sh", file=sys.stderr)
    sys.exit(1)

path.write_bytes(data)
region = bytes(data[start:end])
assert region.count(bytes.fromhex("be468e0000")) == 0
assert region.count(bytes.fromhex("be458e0000")) >= 1
print(f"Corrigido ({n} immediates): e2_init_agent → porta 36421")
PY
