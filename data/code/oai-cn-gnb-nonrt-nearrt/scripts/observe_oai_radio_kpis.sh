#!/bin/bash
# Observa KPIs de rádio/MAC a partir do log do gNB OAI.
# Uso:
#   ./scripts/observe_oai_radio_kpis.sh [logs/gnb_oai_oran.log]
#
# Estes campos não vêm do E2SM-KPM neste lab. Eles são extraídos do log OAI para
# correlacionar qualidade de rádio com os KPMs E2 coletados por xApp.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="${1:-${OAI_GNB_LOG:-$PROJECT_DIR/logs/gnb_oai_oran.log}}"
LINES="${RADIO_KPI_LINES:-300}"
SAMPLES="${RADIO_KPI_SAMPLES:-10}"
DETAIL="${RADIO_KPI_DETAIL:-0}"

if [ ! -f "$LOG_FILE" ]; then
    echo "ERRO: log não encontrado: $LOG_FILE" >&2
    exit 1
fi

echo "=========================================="
echo "KPIs rádio/MAC OAI — observação por log"
echo "=========================================="
echo "log=$LOG_FILE"
echo "samples=$SAMPLES"
echo "mode=$([ "$DETAIL" = "1" ] && echo detail || echo summary)"
echo ""
echo "Campos e unidades:"
echo "  RSRP       dBm"
echo "  SNR        dB"
echo "  PH         dB"
echo "  PCMAX      dBm"
echo "  MCS        índice"
echo "  BLER       razão"
echo "  CQI        índice 0-15, quando presente no log"
echo ""

tail -n "$LINES" "$LOG_FILE" | awk -v max_samples="$SAMPLES" -v detail="$DETAIL" '
    function add_metric(key, value) {
        if (value == "n/a" || value == "") return
        value += 0
        count[key]++
        sum[key] += value
        if (count[key] == 1 || value < min[key]) min[key] = value
        if (count[key] == 1 || value > max[key]) max[key] = value
    }

    function remember_rnti(rnti) {
        if (!(rnti in seen)) {
            seen[rnti] = 1
            rnti_order[++rnti_count] = rnti
        }
    }

    /UE RNTI/ && /average RSRP/ {
        active=0
        if (sample_count >= max_samples) next
        sample_count++
        active=1
        rnti="n/a"; ph="n/a"; pcmax="n/a"; rsrp="n/a"; meas="n/a"
        for (i=1; i<=NF; i++) {
            if ($i == "RNTI") rnti=$(i+1)
            if ($i == "PH") ph=$(i+1)
            if ($i == "PCMAX") pcmax=$(i+1)
            if ($i == "RSRP") {
                rsrp=$(i+1)
                gsub(/[()]/, "", $(i+2))
                meas=$(i+2)
            }
        }
        last_rnti=rnti
        remember_rnti(rnti)
        add_metric(rnti "|PH", ph)
        add_metric(rnti "|PCMAX", pcmax)
        add_metric(rnti "|RSRP", rsrp)
        sample_seen[rnti]++
        if (detail == "1")
            printf "UE RNTI=%s PH=%s dB PCMAX=%s dBm RSRP=%s dBm samples=%s\n", rnti, ph, pcmax, rsrp, meas
    }
    /dlsch_rounds/ {
        if (!active) next
        split($0, parts, "BLER ")
        bler="n/a"
        if (length(parts) > 1) {
            split(parts[2], b, " ")
            bler=b[1]
        }
        mcs="n/a"
        for (i=1; i<=NF; i++) if ($i == "MCS") mcs=$(i+2)
        add_metric(last_rnti "|DL_BLER", bler)
        add_metric(last_rnti "|DL_MCS", mcs)
        if (detail == "1")
            printf "  DL BLER=%s MCS=%s\n", bler, mcs
    }
    /ulsch_rounds/ {
        if (!active) next
        split($0, parts, "BLER ")
        bler="n/a"
        if (length(parts) > 1) {
            split(parts[2], b, " ")
            bler=b[1]
        }
        mcs="n/a"; snr="n/a"
        for (i=1; i<=NF; i++) {
            if ($i == "MCS") mcs=$(i+2)
            if ($i == "SNR") snr=$(i+1)
        }
        add_metric(last_rnti "|UL_BLER", bler)
        add_metric(last_rnti "|UL_MCS", mcs)
        add_metric(last_rnti "|SNR", snr)
        if (detail == "1")
            printf "  UL BLER=%s MCS=%s SNR=%s dB\n", bler, mcs, snr
    }
    /CQI/ {
        cqi="n/a"; rnti=last_rnti
        for (i=1; i<=NF; i++) {
            if ($i == "CQI") cqi=$(i+1)
            if ($i == "RNTI") rnti=$(i+1)
        }
        if (rnti != "") {
            remember_rnti(rnti)
            add_metric(rnti "|CQI", cqi)
        }
        if (detail == "1") print
    }

    END {
        if (detail == "1") {
            print ""
            print "Resumo:"
        }
        if (rnti_count == 0) {
            print "Nenhuma amostra UE encontrada no trecho analisado."
            print "Aumente RADIO_KPI_LINES ou confirme se o gNB está gerando logs NR_MAC."
            exit
        }

        for (i=1; i<=rnti_count; i++) {
            rnti = rnti_order[i]
            printf "RNTI %s (%d amostras)\n", rnti, sample_seen[rnti]
            printf "  %-9s %-7s %12s %12s %12s\n", "metric", "unit", "avg", "min", "max"
            printf "  %-9s %-7s %12s %12s %12s\n", "---------", "-------", "------------", "------------", "------------"
            print_metric(rnti, "RSRP", "dBm")
            print_metric(rnti, "SNR", "dB")
            print_metric(rnti, "PH", "dB")
            print_metric(rnti, "PCMAX", "dBm")
            print_metric(rnti, "DL_BLER", "ratio")
            print_metric(rnti, "UL_BLER", "ratio")
            print_metric(rnti, "DL_MCS", "index")
            print_metric(rnti, "UL_MCS", "index")
            print_metric(rnti, "CQI", "index")
            print ""
        }

        print "Formato: média (mín..máx) nas últimas amostras analisadas."
    }

    function print_metric(rnti, metric, unit, key, avg) {
        key = rnti "|" metric
        if (count[key] == 0) {
            printf "  %-9s %-7s %12s %12s %12s\n", metric, unit, "n/a", "n/a", "n/a"
            return
        }
        avg = sum[key] / count[key]
        printf "  %-9s %-7s %12.2f %12.2f %12.2f\n", metric, unit, avg, min[key], max[key]
    }
'
