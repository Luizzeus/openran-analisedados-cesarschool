#!/bin/bash
# Loop fechado Fase 3: KPM → store → MAD → A1 → atuação (emulate|real) → evidência.
#
# Uso:
#   ACTUATION_MODE=emulate ./scripts/run_closed_loop_lab.sh --offline
#   ACTUATION_MODE=emulate ./scripts/run_closed_loop_lab.sh --live-fase2
#   ACTUATION_MODE=real CLOSED_LOOP_ALLOW_REAL=1 ./scripts/run_closed_loop_lab.sh --live-fase2
#
# Variáveis:
#   AI_POLICY_COMMIT=0|1          envia policy ao PMS (padrão 0 = dry-run A1)
#   ACTUATION_MODE=emulate|real
#   KPM_CAPTURE_SEC=20            duração de cada captura KPM
#   CLOSED_LOOP_ALLOW_REAL=1      obrigatório para modo real com envio E2
#   CLOSED_LOOP_REAL_DRY_RUN=1    gera intent sem enviar CONTROL
#   CLOSED_LOOP_AUTO_STRESS=1     live: sobe iperf UDP durante before/after (padrão 1)
#   CLOSED_LOOP_STRESS_RATE=40M   taxa UDP do iperf (padrão; 100M pode matar Indications E2)
#   CLOSED_LOOP_IPERF_PORT=5202   porta dedicada (não conflitar com test-vpp :5201)
#   CLOSED_LOOP_FORCE_LOAD=1      live: se MAD=observe sob carga alta, force-apply (padrão 1)
#   CLOSED_LOOP_LOAD_UETHP_KBPS=20000   limiar UEThpUl (kbps) para force-apply
#   CLOSED_LOOP_LOAD_PRB_PCT=40         limiar RRU.PrbTotUl (%) para force-apply

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORAN_VENDOR="${ORAN_VENDOR_DIR:-$PROJECT_DIR/vendor/oran-sc-ric}"
ORAN_CFG="${ORAN_CFG_DIR:-$PROJECT_DIR/config/oran-ric}"

CONFIG="${AI_POLICY_CONFIG:-$PROJECT_DIR/config/ai-policy/closed_loop.json}"
STRESS_DIR="${AI_STRESS_DIR:-$PROJECT_DIR/logs/ue_stress_20260615-081959}"
MODE="${ACTUATION_MODE:-emulate}"
COMMIT="${AI_POLICY_COMMIT:-0}"
CAPTURE_SEC="${KPM_CAPTURE_SEC:-20}"
ALLOW_REAL="${CLOSED_LOOP_ALLOW_REAL:-0}"
REAL_DRY="${CLOSED_LOOP_REAL_DRY_RUN:-0}"
AUTO_STRESS="${CLOSED_LOOP_AUTO_STRESS:-1}"
# 100M UDP pode saturar o gNB rfsim e interromper Indications E2/KPM; 40M é mais estável no lab.
STRESS_RATE="${CLOSED_LOOP_STRESS_RATE:-40M}"
IPERF_PORT="${CLOSED_LOOP_IPERF_PORT:-5202}"
FORCE_LOAD="${CLOSED_LOOP_FORCE_LOAD:-1}"
LOAD_UETHP="${CLOSED_LOOP_LOAD_UETHP_KBPS:-20000}"
LOAD_PRB="${CLOSED_LOOP_LOAD_PRB_PCT:-40}"
DN_IP="${OAI_DN_IP:-192.168.73.135}"
DN_CONTAINER="${OAI_DN_CONTAINER:-oai-ext-dn}"
RUN_ID="${AI_RUN_ID:-closed-loop-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${AI_RUN_DIR:-$PROJECT_DIR/logs/closed_loop_${RUN_ID}}"
E2_NODE_ID="${E2_NODE_ID:-$("$SCRIPT_DIR/get_oran_e2_node_id.sh" 2>/dev/null || echo gnb_208_095_00000e00)}"

LIVE=0
OFFLINE=1
for arg in "$@"; do
    case "$arg" in
        --live-fase2) LIVE=1; OFFLINE=0 ;;
        --offline) LIVE=0; OFFLINE=1 ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *)
            echo "argumento desconhecido: $arg" >&2
            exit 1
            ;;
    esac
done

if [ "$MODE" != "emulate" ] && [ "$MODE" != "real" ]; then
    echo "ERRO: ACTUATION_MODE deve ser emulate|real (recebido: $MODE)" >&2
    exit 1
fi
if [ "$MODE" = "real" ] && [ "$ALLOW_REAL" != "1" ] && [ "$REAL_DRY" != "1" ]; then
    echo "ERRO: modo real exige CLOSED_LOOP_ALLOW_REAL=1 ou CLOSED_LOOP_REAL_DRY_RUN=1" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
DB_PATH="$OUT_DIR/kpm.sqlite"
JSONL_PATH="$OUT_DIR/kpm.jsonl"
AUDIT="$OUT_DIR/actuator_events.jsonl"
STATE="$OUT_DIR/actuator_state.json"
INTENT_DIR="$OUT_DIR/intent"
mkdir -p "$INTENT_DIR"
export CLOSED_LOOP_INTENT_DIR="$INTENT_DIR"

STRESS_PID=""
STRESS_SERVER_STARTED=0
cleanup_stress() {
    if [ -n "${STRESS_PID:-}" ] && kill -0 "$STRESS_PID" 2>/dev/null; then
        kill "$STRESS_PID" 2>/dev/null || true
        wait "$STRESS_PID" 2>/dev/null || true
    fi
    STRESS_PID=""
    # Encerra só o servidor da porta dedicada (não mata iperf em :5201 do test-vpp).
    if [ "${STRESS_SERVER_STARTED:-0}" = "1" ] \
        && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DN_CONTAINER"; then
        docker exec "$DN_CONTAINER" sh -c \
            "pkill -f 'iperf3 -s -p ${IPERF_PORT}' 2>/dev/null || true" >/dev/null 2>&1 || true
    fi
    STRESS_SERVER_STARTED=0
}
trap cleanup_stress EXIT

compose() {
    docker compose \
        -f "$ORAN_VENDOR/docker-compose.yml" \
        -f "$ORAN_CFG/docker-compose.override.yml" \
        --env-file "$ORAN_VENDOR/.env" \
        --env-file "$ORAN_CFG/.env" \
        "$@"
}

find_ue_bind() {
    for cand in oaitun_ue1 oaitun_ue0 oaitun_ue2; do
        if ip link show "$cand" >/dev/null 2>&1; then
            ip -4 addr show "$cand" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1
            return 0
        fi
    done
    return 1
}

start_auto_stress() {
    # iperf UDP UL via oaitun → DN; roda em background durante before/after.
    if [ "$AUTO_STRESS" != "1" ]; then
        echo "  CLOSED_LOOP_AUTO_STRESS=0 — use tráfego externo durante before/after"
        return 0
    fi
    if ! command -v iperf3 >/dev/null 2>&1; then
        echo "AVISO: iperf3 ausente no host; stress automático desligado" >&2
        return 0
    fi
    UE_IP="$(find_ue_bind || true)"
    if [ -z "${UE_IP:-}" ]; then
        echo "AVISO: sem oaitun — stress automático desligado" >&2
        return 0
    fi
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DN_CONTAINER"; then
        # Porta dedicada: não usa pkill genérico (evita matar test-vpp em :5201).
        docker exec "$DN_CONTAINER" sh -c \
            "pkill -f 'iperf3 -s -p ${IPERF_PORT}' 2>/dev/null || true" >/dev/null 2>&1 || true
        sleep 0.3
        docker exec -d "$DN_CONTAINER" iperf3 -s -p "$IPERF_PORT" >/dev/null 2>&1 || true
        STRESS_SERVER_STARTED=1
    fi
    # duração cobre before + after + margem
    local dur=$(( CAPTURE_SEC * 2 + 40 ))
    echo "  stress auto: iperf3 UDP -b $STRESS_RATE -p $IPERF_PORT -B $UE_IP → $DN_IP (${dur}s)"
    iperf3 -c "$DN_IP" -p "$IPERF_PORT" -u -b "$STRESS_RATE" -t "$dur" -B "$UE_IP" -f m \
        >"$OUT_DIR/iperf_stress.log" 2>&1 &
    STRESS_PID=$!
    sleep 2
}

decision_is_apply() {
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("evaluation",{}).get("decision")=="apply" and d.get("policy") else 1)' \
        "$1"
}

load_gate_triggered() {
    python3 - "$1" "$2" "$3" <<'PY'
import json, sys
path, uethp_thr, prb_thr = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
d = json.load(open(path))
sample = (d.get("evaluation") or {}).get("latest", {}).get("sample") or {}
uethp = float(sample.get("DRB.UEThpUl") or 0)
prb = float(sample.get("RRU.PrbTotUl") or 0)
sys.exit(0 if (uethp >= uethp_thr or prb >= prb_thr) else 1)
PY
}

maybe_force_apply_live() {
    # Se MAD ficou em observe mas a janela before está sob carga alta, gera policy.
    if [ "$FORCE_LOAD" != "1" ]; then
        return 0
    fi
    if decision_is_apply "$OUT_DIR/decision.json"; then
        return 0
    fi
    if ! load_gate_triggered "$OUT_DIR/decision.json" "$LOAD_UETHP" "$LOAD_PRB"; then
        echo "  load-gate: carga abaixo dos limiares — mantém observe (sem atuação)"
        return 0
    fi
    echo "  load-gate: carga alta com MAD=observe → force-apply (lab)"
    python3 "$SCRIPT_DIR/ai_policy_pipeline.py" force-apply \
        --decision "$OUT_DIR/decision.json" \
        --config "$CONFIG" \
        --reason "live-load-gate uethp>=${LOAD_UETHP}kbps|prb>=${LOAD_PRB}%" \
        --actuation-mode "$MODE"
}

write_policy_sidecar() {
    python3 -c 'import json,pathlib,sys
d=json.load(open(sys.argv[1]))
pathlib.Path(sys.argv[2]).write_text(json.dumps(d.get("policy") or {}, indent=2)+"\n")' \
        "$OUT_DIR/decision.json" "$OUT_DIR/policy.json"
}

echo "=========================================="
echo "Closed loop Fase 3"
echo "=========================================="
echo "run_id=$RUN_ID"
echo "out=$OUT_DIR"
echo "mode=$MODE"
echo "collect=$([ "$LIVE" = 1 ] && echo live-fase2 || echo offline)"
echo "a1_commit=$COMMIT"
echo "auto_stress=$([ "$LIVE" = 1 ] && echo "$AUTO_STRESS" || echo n/a)"
echo ""

echo "[1/9] SMO-lite + evento início"
"$SCRIPT_DIR/up_smo_lab.sh" >/dev/null
"$SCRIPT_DIR/smo_lab_event.sh" MINOR closed_loop_lab Notice \
    "closed-loop start run_id=$RUN_ID mode=$MODE" >/dev/null || true

BASELINE_LOG="$OUT_DIR/kpm_baseline.log"
BEFORE_LOG="$OUT_DIR/kpm_before.log"

if [ "$LIVE" = 1 ]; then
    echo "[2/9] captura KPM baseline calmo (treino)"
    KPM_TRAFFIC=0 KPM_CAPTURE_SEC="$CAPTURE_SEC" \
        "$SCRIPT_DIR/capture_kpm_fase2.sh" "$BASELINE_LOG" "$CAPTURE_SEC"

    echo "[3/9] treino MAD no baseline"
    python3 "$SCRIPT_DIR/kpm_store.py" ingest \
        --db "$DB_PATH" --jsonl "$JSONL_PATH" \
        --input "$BASELINE_LOG" \
        --config "$CONFIG" --run-id "$RUN_ID" --phase baseline \
        --use-case closed-loop-ue-tp --notes "baseline calmo live"
    python3 "$SCRIPT_DIR/ai_policy_pipeline.py" train \
        --input "$BASELINE_LOG" \
        --config "$CONFIG" \
        --model "$OUT_DIR/model.json"

    echo "[4/9] stress + captura KPM before (avaliação)"
    start_auto_stress
    KPM_TRAFFIC=1 KPM_CAPTURE_SEC="$CAPTURE_SEC" \
        "$SCRIPT_DIR/capture_kpm_fase2.sh" "$BEFORE_LOG" "$CAPTURE_SEC"
else
    echo "[2/9] logs offline (baseline + stress→before)"
    cp "$STRESS_DIR/kpm_baseline.log" "$BASELINE_LOG"
    cp "$STRESS_DIR/kpm_stress.log" "$BEFORE_LOG"

    echo "[3/9] treino MAD no baseline"
    python3 "$SCRIPT_DIR/kpm_store.py" ingest \
        --db "$DB_PATH" --jsonl "$JSONL_PATH" \
        --input "$BASELINE_LOG" \
        --config "$CONFIG" --run-id "$RUN_ID" --phase baseline \
        --use-case closed-loop-ue-tp --notes "baseline offline"
    python3 "$SCRIPT_DIR/ai_policy_pipeline.py" train \
        --input "$BASELINE_LOG" \
        --config "$CONFIG" \
        --model "$OUT_DIR/model.json"

    echo "[4/9] (offline) before = stress log"
fi

python3 "$SCRIPT_DIR/kpm_store.py" ingest \
    --db "$DB_PATH" --jsonl "$JSONL_PATH" \
    --input "$BEFORE_LOG" \
    --config "$CONFIG" --run-id "$RUN_ID" --phase before \
    --use-case closed-loop-ue-tp --notes "janela pré-atuação"

echo "[5/9] evaluate (+ force-apply se load-gate)"
python3 "$SCRIPT_DIR/ai_policy_pipeline.py" evaluate \
    --input "$BEFORE_LOG" \
    --config "$CONFIG" \
    --model "$OUT_DIR/model.json" \
    --output "$OUT_DIR/decision.json" \
    --window 5 \
    --actuation-mode "$MODE"

if ! decision_is_apply "$OUT_DIR/decision.json"; then
    if [ "$OFFLINE" = 1 ]; then
        echo "  decisão observe no offline — reavaliando stress vs baseline"
        python3 "$SCRIPT_DIR/ai_policy_pipeline.py" evaluate \
            --input "$STRESS_DIR/kpm_stress.log" \
            --config "$CONFIG" \
            --model "$OUT_DIR/model.json" \
            --output "$OUT_DIR/decision.json" \
            --window 5 \
            --actuation-mode "$MODE"
        if ! decision_is_apply "$OUT_DIR/decision.json"; then
            echo "  ainda observe — force-apply (demo offline)"
            python3 "$SCRIPT_DIR/ai_policy_pipeline.py" force-apply \
                --decision "$OUT_DIR/decision.json" \
                --config "$CONFIG" \
                --reason "offline-demo" \
                --actuation-mode "$MODE"
        fi
    else
        maybe_force_apply_live || true
    fi
fi
write_policy_sidecar

echo "[6/9] A1 policy"
APPLY_ARGS=(--decision "$OUT_DIR/decision.json")
if [ "$COMMIT" = "1" ]; then
    APPLY_ARGS+=(--commit)
fi
python3 "$SCRIPT_DIR/ai_policy_pipeline.py" apply "${APPLY_ARGS[@]}" | tee "$OUT_DIR/a1_apply.txt"

echo "[7/9] atuação ($MODE)"
ACTUATED=0
if decision_is_apply "$OUT_DIR/decision.json"; then
    ACT_ARGS=(
        apply
        --decision "$OUT_DIR/decision.json"
        --config "$CONFIG"
        --audit "$AUDIT"
        --state "$STATE"
        --mode "$MODE"
        --e2-node-id "$E2_NODE_ID"
    )
    if [ "$MODE" = "emulate" ] && [ "$OFFLINE" = 1 ] && ! ip link show oaitun_ue1 >/dev/null 2>&1 \
        && ! ip link show oaitun_ue0 >/dev/null 2>&1; then
        ACT_ARGS+=(--dry-run)
        echo "  sem oaitun — emulate dry-run"
    fi
    if [ "$MODE" = "real" ] && [ "$REAL_DRY" = "1" ]; then
        ACT_ARGS+=(--dry-run)
    fi
    python3 "$SCRIPT_DIR/closed_loop_actuator.py" "${ACT_ARGS[@]}"
    ACTUATED=1

    if [ "$MODE" = "real" ] && [ "$ALLOW_REAL" = "1" ] && [ "$REAL_DRY" != "1" ]; then
        INTENT_HOST="$INTENT_DIR/pending_rc_control.json"
        if [ -f "$INTENT_HOST" ]; then
            echo "  enviando CONTROL via policy_actuator_xapp"
            docker cp "$INTENT_HOST" python_xapp_runner:/tmp/pending_rc_control.json
            docker cp "$AUDIT" python_xapp_runner:/tmp/actuator_events.jsonl 2>/dev/null || true
            compose exec -T -e PYTHONUNBUFFERED=1 python_xapp_runner \
                python3 ./policy_actuator_xapp.py \
                --e2_node_id="$E2_NODE_ID" \
                --intent=/tmp/pending_rc_control.json \
                --audit=/tmp/actuator_events.jsonl \
                --once || echo "AVISO: falha no envio CONTROL (ver logs xApp)"
            docker cp python_xapp_runner:/tmp/actuator_events.jsonl "$AUDIT" 2>/dev/null || true
        fi
    fi
    "$SCRIPT_DIR/smo_lab_event.sh" MAJOR closed_loop_lab Warning \
        "actuation applied mode=$MODE run_id=$RUN_ID" >/dev/null || true
else
    echo "  sem policy/apply — atuação omitida (MAD observe e load-gate inativo)"
    "$SCRIPT_DIR/smo_lab_event.sh" MINOR closed_loop_lab Notice \
        "actuation skipped observe run_id=$RUN_ID" >/dev/null || true
fi

echo "[8/9] coleta KPM (after) + effect report"
AFTER_LOG="$OUT_DIR/kpm_after.log"
if [ "$LIVE" = 1 ]; then
    sleep 2
    KPM_TRAFFIC=1 KPM_CAPTURE_SEC="$CAPTURE_SEC" \
        "$SCRIPT_DIR/capture_kpm_fase2.sh" "$AFTER_LOG" "$CAPTURE_SEC" || \
        cp "$BEFORE_LOG" "$AFTER_LOG"
else
    # offline: after ≈ baseline (efeito esperado se emulate cortasse stress)
    cp "$STRESS_DIR/kpm_baseline.log" "$AFTER_LOG"
fi
python3 "$SCRIPT_DIR/kpm_store.py" ingest \
    --db "$DB_PATH" --jsonl "$JSONL_PATH" \
    --input "$AFTER_LOG" \
    --config "$CONFIG" --run-id "$RUN_ID" --phase after \
    --use-case closed-loop-ue-tp --notes "janela pós-atuação"

python3 "$SCRIPT_DIR/closed_loop_actuator.py" report \
    --config "$CONFIG" \
    --before "$BEFORE_LOG" \
    --after "$AFTER_LOG" \
    --output "$OUT_DIR/effect_report.json" \
    --audit "$AUDIT" \
    --mode "$MODE"

echo "[9/9] rollback + snapshot SMO"
if [ "$ACTUATED" = "1" ] && [ -f "$STATE" ]; then
    python3 "$SCRIPT_DIR/closed_loop_actuator.py" rollback \
        --state "$STATE" \
        --audit "$AUDIT" \
        --config "$CONFIG" \
        --mode "$MODE" || true
fi
cleanup_stress

SNAP_DIR="$OUT_DIR/smo_snapshot"
"$SCRIPT_DIR/smo_lab_snapshot.sh" "$SNAP_DIR" >/dev/null || true
"$SCRIPT_DIR/smo_lab_event.sh" MINOR closed_loop_lab Notice \
    "closed-loop end run_id=$RUN_ID actuated=$ACTUATED" >/dev/null || true

echo ""
echo "=========================================="
echo "Closed loop concluído"
echo "=========================================="
echo "Artefatos: $OUT_DIR"
echo "  decision.json / policy.json / model.json"
echo "  actuator_events.jsonl / effect_report.json"
echo "  kpm_baseline.log / kpm_before.log / kpm_after.log / kpm.sqlite"
if [ -f "$OUT_DIR/decision.json" ]; then
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); e=d.get("evaluation",{}); print("  decision=", e.get("decision"), " force_apply=", e.get("force_apply", False), " actuated=", sys.argv[2])' \
        "$OUT_DIR/decision.json" "$ACTUATED"
fi
ls -la "$OUT_DIR" | sed -n '1,25p'
