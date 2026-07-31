#!/bin/bash
# Registra evento OAM/VES simulado para correlacao com KPM/A1/E2.
# Uso:
#   ./scripts/smo_lab_event.sh <severity> <source> <event_name> [description]
#
# Exemplo:
#   ./scripts/smo_lab_event.sh MAJOR sim_o_du_001 HighPrbUl "UL PRB acima do limiar"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${SMO_EVENT_LOG:-$PROJECT_DIR/logs/smo_lab_events.jsonl}"

severity="${1:-}"
source="${2:-}"
event_name="${3:-}"
description="${4:-}"

if [ -z "$severity" ] || [ -z "$source" ] || [ -z "$event_name" ]; then
    echo "Uso: $0 <severity> <source> <event_name> [description]" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

severity_esc="$(json_escape "$severity")"
source_esc="$(json_escape "$source")"
event_name_esc="$(json_escape "$event_name")"
description_esc="$(json_escape "$description")"

cat >> "$OUT" <<EOF
{"eventTime":"$ts","interface":"VES-simulated","severity":"$severity_esc","sourceName":"$source_esc","eventName":"$event_name_esc","description":"$description_esc"}
EOF

echo "Evento registrado em $OUT"
tail -1 "$OUT"
