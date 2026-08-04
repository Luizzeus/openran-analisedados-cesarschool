#!/bin/bash
# Coleta estendida de KPMs OAI via O-RAN SC nearRT RIC.
# Uso:
#   ./scripts/run_xapp_oai_kpm_extended.sh [e2_node_id]
#
# Este script usa apenas measNames suportados pelo gNB OAI em E2SM-KPM:
#   DRB.PdcpSduVolumeDL/UL, DRB.RlcSduDelayDl, DRB.UEThpDl/Ul, RRU.PrbTotDl/Ul
#
# RSSI/RSRP/CQI existem no OAI como métricas internas de rádio/MAC/CSI, mas não
# são expostos como measNames E2SM-KPM por este binário. Para observação auxiliar:
#   ./scripts/observe_oai_radio_kpis.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUPPORTED_KPMS="${SUPPORTED_KPMS:-DRB.PdcpSduVolumeDL,DRB.PdcpSduVolumeUL,DRB.RlcSduDelayDl,DRB.UEThpDl,DRB.UEThpUl,RRU.PrbTotDl,RRU.PrbTotUl}"

echo "=========================================="
echo "xApp OAI KPM estendido — E2SM-KPM"
echo "=========================================="
echo ""
echo "KPMs E2 solicitados:"
echo "  $SUPPORTED_KPMS"
echo ""
echo "Unidades esperadas:"
echo "  DRB.UEThpDl / DRB.UEThpUl          kbps"
echo "  DRB.PdcpSduVolumeDL / UL           Mb"
echo "  DRB.RlcSduDelayDl                  us"
echo "  RRU.PrbTotDl / RRU.PrbTotUl        %"
echo ""
echo "Nota: RSSI/RSRP/CQI não são measNames E2SM-KPM suportados pelo gNB OAI atual."
echo "      Para rádio/MAC auxiliar: ./scripts/observe_oai_radio_kpis.sh"
echo ""

XAPP_METRICS="$SUPPORTED_KPMS" "$SCRIPT_DIR/run_xapp_oai_kpm.sh" "$@"
