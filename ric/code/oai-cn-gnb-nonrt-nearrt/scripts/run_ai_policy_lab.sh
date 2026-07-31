#!/bin/bash
# Treina, avalia e (opcionalmente) aplica uma policy A1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="${AI_POLICY_CONFIG:-$PROJECT_DIR/config/ai-policy/pipeline.json}"
BASELINE="${AI_BASELINE_LOG:-$PROJECT_DIR/logs/ue_stress_20260615-081959/kpm_baseline.log}"
INPUT="${AI_EVALUATION_LOG:-$PROJECT_DIR/logs/ue_stress_20260615-081959/kpm_stress.log}"
RUN_DIR="${AI_RUN_DIR:-$PROJECT_DIR/logs/ai_policy_$(date +%Y%m%d-%H%M%S)}"
COMMIT="${AI_POLICY_COMMIT:-0}"

mkdir -p "$RUN_DIR"

python3 "$SCRIPT_DIR/ai_policy_pipeline.py" train \
    --input "$BASELINE" --config "$CONFIG" --model "$RUN_DIR/model.json"
python3 "$SCRIPT_DIR/ai_policy_pipeline.py" evaluate \
    --input "$INPUT" --config "$CONFIG" --model "$RUN_DIR/model.json" \
    --output "$RUN_DIR/decision.json"

apply_args=(
    apply
    --decision "$RUN_DIR/decision.json"
    --pms-url "${NONRT_PMS_URL:-http://127.0.0.1:8081/a1-policy/v2}"
)
if [ "$COMMIT" = "1" ]; then
    apply_args+=(--commit)
fi
python3 "$SCRIPT_DIR/ai_policy_pipeline.py" "${apply_args[@]}"

echo "Artefatos: $RUN_DIR"
