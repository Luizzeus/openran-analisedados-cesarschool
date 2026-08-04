#!/usr/bin/env python3
"""rApp experimental: treina baseline KPM e produz/aplica policy A1 via PMS."""

import argparse
import json
import re
import statistics
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

# Aceita "NAME = 1.2" (FlexRIC/stress) e "NAME: 1.2 kbps" (simple_xapp_oai Fase 2).
METRIC_RE = re.compile(
    r"^([A-Za-z][A-Za-z0-9_.]+)\s*[:=]\s*(-?\d+(?:\.\d+)?)"
)


def load_json(path):
    with Path(path).open(encoding="utf-8") as stream:
        return json.load(stream)


def write_json(path, value):
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def parse_kpm(path, features):
    """Parse blocos do log textual do xApp OAI; blocos incompletos são ignorados."""
    samples, current = [], {}
    with Path(path).open(encoding="utf-8", errors="replace") as stream:
        for raw_line in stream:
            match = METRIC_RE.match(raw_line.strip())
            if not match:
                continue
            name, value = match.groups()
            if name not in features:
                continue
            if name in current:
                if all(feature in current for feature in features):
                    samples.append(current)
                current = {}
            current[name] = float(value)
            if all(feature in current for feature in features):
                samples.append(current)
                current = {}
    if not samples:
        raise ValueError(f"nenhuma amostra KPM completa em {path}")
    return samples


def resolve_actuation(config, mode_override=None):
    """Extrai bloco de atuação do config; mode_override tem prioridade (env/CLI)."""
    actuation = dict(config.get("actuation") or {})
    if mode_override:
        actuation["mode"] = mode_override
    mode = actuation.get("mode", "emulate")
    if mode not in ("emulate", "real"):
        raise ValueError(f"actuation.mode inválido: {mode}")
    real = dict(actuation.get("real") or {})
    action_id = int(real.get("control_action_id", 2))
    forbidden = {int(x) for x in real.get("forbidden_actions", [6])}
    if action_id in forbidden or action_id != 2:
        raise ValueError(
            "atuação real só permite E2SM-RC control_action_id=2 "
            f"(recebido {action_id}; proibidos={sorted(forbidden)})"
        )
    actuation["real"] = real
    actuation["mode"] = mode
    return actuation


def median_absolute_deviation(values, center):
    return statistics.median(abs(value - center) for value in values)


def train(args):
    config = load_json(args.config)
    features = config["features"]
    samples = parse_kpm(args.input, features)
    model_features = {}
    for feature in features:
        values = [sample[feature] for sample in samples]
        center = statistics.median(values)
        model_features[feature] = {
            "median": center,
            "mad": median_absolute_deviation(values, center),
            "min": min(values),
            "max": max(values),
        }
    model = {
        "schema_version": 1,
        "algorithm": "robust-baseline-mad",
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "training_source": str(Path(args.input)),
        "sample_count": len(samples),
        "features": model_features,
        "score_threshold": float(config["score_threshold"]),
        "min_anomalous_features": int(config["min_anomalous_features"]),
        "mad_floor": float(config.get("mad_floor", 1.0)),
    }
    write_json(args.model, model)
    print(f"modelo treinado: {args.model} ({len(samples)} amostras)")


def infer(model, sample):
    scores = {}
    for feature, params in model["features"].items():
        scale = max(float(params["mad"]) * 1.4826, float(model["mad_floor"]))
        scores[feature] = abs(float(sample[feature]) - float(params["median"])) / scale
    anomalous = [name for name, score in scores.items() if score >= model["score_threshold"]]
    return {
        "decision": "apply" if len(anomalous) >= model["min_anomalous_features"] else "observe",
        "scores": scores,
        "anomalous_features": anomalous,
        "sample": sample,
    }


def build_policy(config, decision, actuation=None):
    suffix = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    policy = {
        "ric_id": config["ric_id"],
        "policy_id": f"{config['policy_id_prefix']}-{suffix}",
        "service_id": config["service_id"],
        "policytype_id": str(config["policytype_id"]),
        "policy_data": config["policy_data"],
    }
    # Metadados de lab (fora de policy_data para não quebrar schema OSC type 1).
    if actuation is not None:
        policy["actuation"] = actuation
    if isinstance(decision, dict) and decision.get("anomalous_features") is not None:
        policy["lab_context"] = {
            "anomalous_features": decision.get("anomalous_features"),
            "decision": decision.get("decision"),
        }
    return policy


def evaluate(args):
    config, model = load_json(args.config), load_json(args.model)
    samples = parse_kpm(args.input, list(model["features"]))
    window = samples[-args.window :]
    decisions = [infer(model, sample) for sample in window]
    apply_count = sum(item["decision"] == "apply" for item in decisions)
    actuation = resolve_actuation(config, getattr(args, "actuation_mode", None))
    aggregate = {
        "evaluated_at": datetime.now(timezone.utc).isoformat(),
        "window_size": len(window),
        "apply_votes": apply_count,
        "decision": "apply" if apply_count > len(window) / 2 else "observe",
        "latest": decisions[-1],
        "actuation": actuation,
    }
    policy = (
        build_policy(config, aggregate["latest"], actuation)
        if aggregate["decision"] == "apply"
        else None
    )
    result = {"evaluation": aggregate, "policy": policy, "actuation": actuation}
    write_json(args.output, result)
    print(f"decisão: {aggregate['decision']} ({apply_count}/{len(window)} votos)")
    print(f"atuação: {actuation['mode']}")
    print(f"resultado: {args.output}")


def put_json(url, payload, timeout):
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url, data=body, method="PUT", headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8", errors="replace")


def apply_policy(args):
    result = load_json(args.decision)
    policy = result.get("policy")
    if not policy:
        print("nenhuma policy: decisão do modelo foi observe")
        return
    if not args.commit:
        print(json.dumps(policy, indent=2, sort_keys=True))
        print("dry-run: use --commit para enviar ao PMS")
        return
    try:
        status, response = put_json(
            f"{args.pms_url.rstrip('/')}/policies", policy, args.timeout
        )
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"PMS retornou HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"falha ao acessar PMS: {exc.reason}") from exc
    print(f"policy {policy['policy_id']} enviada ao PMS (HTTP {status})")
    if response:
        print(response)


def mean_feature(decision_path, feature):
    result = load_json(decision_path)
    sample = (result.get("evaluation") or {}).get("latest", {}).get("sample") or {}
    if feature in sample:
        return float(sample[feature])
    return None


def force_apply(args):
    """Força decision=apply e gera policy (lab: carga alta com MAD observe)."""
    config = load_json(args.config)
    result = load_json(args.decision)
    actuation = resolve_actuation(config, getattr(args, "actuation_mode", None))
    evaluation = dict(result.get("evaluation") or {})
    latest = dict(evaluation.get("latest") or {"decision": "observe", "sample": {}})
    latest["decision"] = "apply"
    if not latest.get("anomalous_features"):
        latest["anomalous_features"] = list(config.get("features") or [])
    evaluation["decision"] = "apply"
    evaluation["latest"] = latest
    evaluation["force_apply"] = True
    evaluation["force_reason"] = args.reason
    evaluation["actuation"] = actuation
    policy = build_policy(config, latest, actuation)
    out = {"evaluation": evaluation, "policy": policy, "actuation": actuation}
    dest = args.output or args.decision
    write_json(dest, out)
    print(f"force-apply: policy gerada ({args.reason}) → {dest}")


def parser():
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)
    train_cmd = commands.add_parser("train", help="treinar baseline robusto")
    train_cmd.add_argument("--input", required=True, help="log KPM de baseline")
    train_cmd.add_argument("--config", required=True)
    train_cmd.add_argument("--model", required=True)
    train_cmd.set_defaults(func=train)
    eval_cmd = commands.add_parser("evaluate", help="inferir e gerar policy candidata")
    eval_cmd.add_argument("--input", required=True, help="log KPM a avaliar")
    eval_cmd.add_argument("--config", required=True)
    eval_cmd.add_argument("--model", required=True)
    eval_cmd.add_argument("--output", required=True)
    eval_cmd.add_argument("--window", type=int, default=5)
    eval_cmd.add_argument(
        "--actuation-mode",
        choices=["emulate", "real"],
        default=None,
        help="sobrescreve config.actuation.mode",
    )
    eval_cmd.set_defaults(func=evaluate)
    apply_cmd = commands.add_parser("apply", help="mostrar ou enviar policy ao PMS")
    apply_cmd.add_argument("--decision", required=True)
    apply_cmd.add_argument(
        "--pms-url",
        default="http://127.0.0.1:8081/a1-policy/v2",
    )
    apply_cmd.add_argument("--timeout", type=float, default=5.0)
    apply_cmd.add_argument("--commit", action="store_true")
    apply_cmd.set_defaults(func=apply_policy)
    force_cmd = commands.add_parser(
        "force-apply",
        help="força decision=apply e gera policy (lab sob carga)",
    )
    force_cmd.add_argument("--decision", required=True)
    force_cmd.add_argument("--config", required=True)
    force_cmd.add_argument("--output", default=None)
    force_cmd.add_argument("--reason", default="lab-load-gate")
    force_cmd.add_argument(
        "--actuation-mode",
        choices=["emulate", "real"],
        default=None,
    )
    force_cmd.set_defaults(func=force_apply)
    return root


def main():
    args = parser().parse_args()
    try:
        args.func(args)
    except (OSError, ValueError, KeyError, RuntimeError) as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
