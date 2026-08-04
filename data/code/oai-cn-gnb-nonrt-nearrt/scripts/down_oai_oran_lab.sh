#!/bin/bash
# Para lab Fase 2 (O-RAN SC). Não afeta artefatos Fase 1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/down_gnb_oai.sh" 2>/dev/null || true
"$SCRIPT_DIR/down_nonrt_ric_oran.sh" 2>/dev/null || true
"$SCRIPT_DIR/down_oran_ric.sh" 2>/dev/null || true

echo "Lab Fase 2 parado."
