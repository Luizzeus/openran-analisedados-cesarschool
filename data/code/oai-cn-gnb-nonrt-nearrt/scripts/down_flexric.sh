#!/bin/bash
# Para nearRT-RIC e xApps FlexRIC.
# Uso: ./scripts/down_flexric.sh

set -euo pipefail

echo "Parando nearRT-RIC e xApps FlexRIC..."

pkill -x "nearRT-RIC" 2>/dev/null || true
pkill -f "/xapp_" 2>/dev/null || true
pkill -f "xapp_oran_moni" 2>/dev/null || true
pkill -f "xapp_cust_moni" 2>/dev/null || true
pkill -f "xapp_all_moni" 2>/dev/null || true
pkill -f "xapp_kpm_moni" 2>/dev/null || true
pkill -f "xapp_rc_moni" 2>/dev/null || true
pkill -f "xapp_gtp_mac_rlc_pdcp_moni" 2>/dev/null || true
pkill -f "xapp_kpm_rc" 2>/dev/null || true

sleep 1
if pgrep -x "nearRT-RIC" >/dev/null 2>&1; then
    pkill -9 -x "nearRT-RIC" 2>/dev/null || true
    sleep 1
fi
echo "FlexRIC parado."
