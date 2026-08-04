#!/bin/bash
# Experimento local virtualizado: coleta KPM -> BD -> IA -> policy A1 (dry-run).
#
# Caso de uso: UE-TP / anomalia de carga (proxy lab do artigo SUTD).
# Offline por padrão (usa capturas já existentes). Com --live, corre stress_ue_observe_apps.
#
# Uso:
#   ./scripts/run_ue_tp_experiment.sh
#   ./scripts/run_ue_tp_experiment.sh --live
#   AI_POLICY_COMMIT=1 ./scripts/run_ue_tp_experiment.sh   # envia A1 se PMS up

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="${AI_POLICY_CONFIG:-$PROJECT_DIR/config/ai-policy/pipeline.json}"
STRESS_DIR="${AI_STRESS_DIR:-$PROJECT_DIR/logs/ue_stress_20260615-081959}"
RUN_ID="${AI_RUN_ID:-ue-tp-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${AI_RUN_DIR:-$PROJECT_DIR/logs/experiments/$RUN_ID}"
DB_PATH="${AI_KPM_DB:-$OUT_DIR/kpm.sqlite}"
JSONL_PATH="${AI_KPM_JSONL:-$OUT_DIR/kpm.jsonl}"
COMMIT="${AI_POLICY_COMMIT:-0}"
LIVE=0

for arg in "$@"; do
    case "$arg" in
        --live) LIVE=1 ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        *)
            echo "argumento desconhecido: $arg" >&2
            exit 1
            ;;
    esac
done

mkdir -p "$OUT_DIR"

echo "=========================================="
echo "Experimento UE-TP / load-anomaly (lab local)"
echo "=========================================="
echo "run_id=$RUN_ID"
echo "out=$OUT_DIR"
echo "mode=$([ "$LIVE" = 1 ] && echo live || echo offline)"
echo ""

if [ "$LIVE" = 1 ]; then
    echo "[1/5] captura live via stress_ue_observe_apps.sh"
    STRESS_OUT="$OUT_DIR/ue_stress"
    mkdir -p "$STRESS_OUT"
    RUN_DIR="$STRESS_OUT" "$SCRIPT_DIR/stress_ue_observe_apps.sh"
    STRESS_DIR="$STRESS_OUT"
else
    echo "[1/5] offline: reutilizando capturas em $STRESS_DIR"
    [ -f "$STRESS_DIR/kpm_baseline.log" ] || { echo "ERRO: falta kpm_baseline.log" >&2; exit 1; }
    [ -f "$STRESS_DIR/kpm_stress.log" ] || { echo "ERRO: falta kpm_stress.log" >&2; exit 1; }
fi

echo "[2/5] ingestão SQLite + JSONL"
python3 "$SCRIPT_DIR/kpm_store.py" ingest \
    --db "$DB_PATH" --jsonl "$JSONL_PATH" \
    --input "$STRESS_DIR/kpm_baseline.log" \
    --config "$CONFIG" --run-id "$RUN_ID" --phase baseline \
    --use-case ue-tp-load-anomaly \
    --notes "baseline lab OAI+RFSIM+FlexRIC"
python3 "$SCRIPT_DIR/kpm_store.py" ingest \
    --db "$DB_PATH" --jsonl "$JSONL_PATH" \
    --input "$STRESS_DIR/kpm_stress.log" \
    --config "$CONFIG" --run-id "$RUN_ID" --phase stress \
    --use-case ue-tp-load-anomaly \
    --notes "stress UL/DL lab"
if [ -f "$STRESS_DIR/kpm_recovery.log" ]; then
    python3 "$SCRIPT_DIR/kpm_store.py" ingest \
        --db "$DB_PATH" --jsonl "$JSONL_PATH" \
        --input "$STRESS_DIR/kpm_recovery.log" \
        --config "$CONFIG" --run-id "$RUN_ID" --phase recovery \
        --use-case ue-tp-load-anomaly
fi

echo "[3/5] exportar fases do BD (fonte canónica para treino/inferência)"
python3 "$SCRIPT_DIR/kpm_store.py" export \
    --db "$DB_PATH" --run-id "$RUN_ID" --phase baseline \
    --output "$OUT_DIR/baseline_from_db.log"
python3 "$SCRIPT_DIR/kpm_store.py" export \
    --db "$DB_PATH" --run-id "$RUN_ID" --phase stress \
    --output "$OUT_DIR/stress_from_db.log"

echo "[4/5] treino + inferência (rApp lab)"
python3 "$SCRIPT_DIR/ai_policy_pipeline.py" train \
    --input "$OUT_DIR/baseline_from_db.log" \
    --config "$CONFIG" \
    --model "$OUT_DIR/model.json"
python3 "$SCRIPT_DIR/ai_policy_pipeline.py" evaluate \
    --input "$OUT_DIR/stress_from_db.log" \
    --config "$CONFIG" \
    --model "$OUT_DIR/model.json" \
    --output "$OUT_DIR/decision.json"

echo "[5/5] policy A1 (dry-run por defeito)"
apply_args=(apply --decision "$OUT_DIR/decision.json" --pms-url "${NONRT_PMS_URL:-http://127.0.0.1:8081/a1-policy/v2}")
if [ "$COMMIT" = "1" ]; then
    apply_args+=(--commit)
fi
python3 "$SCRIPT_DIR/ai_policy_pipeline.py" "${apply_args[@]}"

python3 "$SCRIPT_DIR/kpm_store.py" summary --db "$DB_PATH" --run-id "$RUN_ID" > "$OUT_DIR/db_summary.json"

cat > "$OUT_DIR/README.md" <<EOF
# Experimento $RUN_ID

- Caso de uso: UE-TP / load-anomaly (lab local virtualizado)
- BD: \`kpm.sqlite\`
- JSONL: \`kpm.jsonl\`
- Modelo: \`model.json\`
- Decisão: \`decision.json\`

Ver \`docs/CASO_USO_LOCAL_VIRTUALIZADO.md\`.
EOF

echo ""
echo "OK — artefatos em: $OUT_DIR"
echo "  db:       $DB_PATH"
echo "  jsonl:    $JSONL_PATH"
echo "  model:    $OUT_DIR/model.json"
echo "  decision: $OUT_DIR/decision.json"
echo "  summary:  $OUT_DIR/db_summary.json"
