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

METRIC_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_.]+)\s*=\s*(-?\d+(?:\.\d+)?)")


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


def build_policy(config, decision):
    suffix = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    return {
        "ric_id": config["ric_id"],
        "policy_id": f"{config['policy_id_prefix']}-{suffix}",
        "service_id": config["service_id"],
        "policytype_id": str(config["policytype_id"]),
        "policy_data": config["policy_data"],
    }


def evaluate(args):
    config, model = load_json(args.config), load_json(args.model)
    samples = parse_kpm(args.input, list(model["features"]))
    window = samples[-args.window :]
    decisions = [infer(model, sample) for sample in window]
    apply_count = sum(item["decision"] == "apply" for item in decisions)
    aggregate = {
        "evaluated_at": datetime.now(timezone.utc).isoformat(),
        "window_size": len(window),
        "apply_votes": apply_count,
        "decision": "apply" if apply_count > len(window) / 2 else "observe",
        "latest": decisions[-1],
    }
    policy = build_policy(config, aggregate["latest"]) if aggregate["decision"] == "apply" else None
    result = {"evaluation": aggregate, "policy": policy}
    write_json(args.output, result)
    print(f"decisão: {aggregate['decision']} ({apply_count}/{len(window)} votos)")
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
