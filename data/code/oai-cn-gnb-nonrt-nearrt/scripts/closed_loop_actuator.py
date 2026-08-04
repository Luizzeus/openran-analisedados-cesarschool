#!/usr/bin/env python3
"""Atuador do loop fechado Fase 3: emulate (tc) ou real (E2SM-RC action=2)."""

from __future__ import annotations

import argparse
import json
import os
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ai_policy_pipeline import (  # noqa: E402
    load_json,
    parse_kpm,
    resolve_actuation,
    write_json,
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def append_event(audit_path: Path, event: dict) -> None:
    audit_path.parent.mkdir(parents=True, exist_ok=True)
    record = {"ts": utc_now(), **event}
    with audit_path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record, sort_keys=True) + "\n")


def load_decision_or_policy(path: Path) -> tuple[dict, dict]:
    data = load_json(path)
    if "policy" in data or "evaluation" in data:
        policy = data.get("policy")
        if policy is None:
            policy = {}
        actuation = data.get("actuation") or policy.get("actuation") or {}
        return data, {
            "policy": policy,
            "actuation": actuation,
            "evaluation": data.get("evaluation") or {},
        }
    return {"policy": data}, {
        "policy": data,
        "actuation": data.get("actuation") or {},
        "evaluation": {},
    }


def find_oaitun(prefix: str = "oaitun_ue") -> str | None:
    try:
        out = subprocess.check_output(["ip", "-o", "link", "show"], text=True)
    except (OSError, subprocess.CalledProcessError):
        return None
    for line in out.splitlines():
        # "3: oaitun_ue1: <...>"
        parts = line.split(":")
        if len(parts) < 2:
            continue
        name = parts[1].strip().split("@")[0]
        if name.startswith(prefix):
            return name
    return None


def run_cmd(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=check, capture_output=True, text=True)


def apply_emulate(actuation: dict, audit: Path, dry_run: bool = False) -> dict:
    emu = actuation.get("emulate") or {}
    rate = int(emu.get("rate_kbit", 8000))
    prefix = emu.get("iface_prefix", "oaitun_ue")
    iface = find_oaitun(prefix)
    if not iface:
        raise RuntimeError(f"nenhuma interface {prefix}* encontrada (nrUE ativo?)")
    detail = {
        "mode": "emulate",
        "iface": iface,
        "rate_kbit": rate,
        "action": "tc-tbf",
    }
    if dry_run:
        append_event(audit, {"event": "emulate_dry_run", **detail})
        return detail
    # Limpa qdisc anterior e aplica TBF (limita egress do host → UE / UL path simulado).
    run_cmd(["sudo", "tc", "qdisc", "del", "dev", iface, "root"], check=False)
    run_cmd(
        [
            "sudo",
            "tc",
            "qdisc",
            "add",
            "dev",
            iface,
            "root",
            "tbf",
            "rate",
            f"{rate}kbit",
            "burst",
            "32kbit",
            "latency",
            "400ms",
        ],
        check=True,
    )
    append_event(audit, {"event": "emulate_applied", **detail})
    return detail


def rollback_emulate(actuation: dict, audit: Path, dry_run: bool = False) -> dict:
    emu = actuation.get("emulate") or {}
    prefix = emu.get("iface_prefix", "oaitun_ue")
    iface = find_oaitun(prefix)
    detail = {"mode": "emulate", "iface": iface, "action": "tc-del"}
    if not iface:
        append_event(audit, {"event": "emulate_rollback_skip", "reason": "no-iface", **detail})
        return detail
    if dry_run:
        append_event(audit, {"event": "emulate_rollback_dry_run", **detail})
        return detail
    run_cmd(["sudo", "tc", "qdisc", "del", "dev", iface, "root"], check=False)
    append_event(audit, {"event": "emulate_rollback", **detail})
    return detail


def validate_real_actuation(actuation: dict) -> dict:
    real = dict(actuation.get("real") or {})
    action_id = int(real.get("control_action_id", 2))
    forbidden = {int(x) for x in real.get("forbidden_actions", [6])}
    if action_id in forbidden or action_id != 2:
        raise RuntimeError(
            f"recusado: control_action_id={action_id} não é seguro no gNB OAI "
            f"(apenas action=2; proibidos={sorted(forbidden)})"
        )
    if int(real.get("rc_style", 1)) != 1:
        raise RuntimeError("recusado: real.rc_style deve ser 1 (Radio Bearer Control)")
    return real


def apply_real(actuation: dict, audit: Path, e2_node_id: str, ue_id: int, dry_run: bool = False) -> dict:
    real = validate_real_actuation(actuation)
    detail = {
        "mode": "real",
        "e2_node_id": e2_node_id,
        "ue_id": ue_id,
        "rc_style": int(real.get("rc_style", 1)),
        "control_action_id": int(real.get("control_action_id", 2)),
        "drb_id": int(real.get("drb_id", 1)),
        "qfi": int(real.get("qfi", 1)),
        "dir": int(real.get("dir", 0)),
        "ran_func_id": int(real.get("ran_func_id", 3)),
    }
    if dry_run or os.environ.get("CLOSED_LOOP_REAL_DRY_RUN", "0") == "1":
        append_event(audit, {"event": "real_control_dry_run", **detail})
        return {**detail, "sent": False, "dry_run": True}

    # Envio real só dentro do runner xApp (RMR). Aqui registramos intent e
    # delegamos via marker file consumido por policy_actuator_xapp.py.
    intent_dir = Path(os.environ.get("CLOSED_LOOP_INTENT_DIR", "/tmp/oai-closed-loop"))
    intent_dir.mkdir(parents=True, exist_ok=True)
    intent_path = intent_dir / "pending_rc_control.json"
    write_json(intent_path, {**detail, "created_at": utc_now()})
    append_event(audit, {"event": "real_control_intent", "intent_path": str(intent_path), **detail})
    return {**detail, "sent": False, "intent_path": str(intent_path)}


def rollback_real(actuation: dict, audit: Path, dry_run: bool = False) -> dict:
    detail = {"mode": "real", "action": "ttl-expire-note"}
    # QoS mapping PoC OAI não tem undo nativo; registramos rollback lógico.
    append_event(
        audit,
        {
            "event": "real_rollback_logical",
            "dry_run": dry_run,
            "note": "OAI RC action=2 não expõe undo; TTL apenas encerra a janela de observação",
            **detail,
        },
    )
    return detail


def feature_means(samples: list[dict], features: list[str]) -> dict:
    out = {}
    for feature in features:
        values = [float(s[feature]) for s in samples if feature in s]
        out[feature] = {
            "count": len(values),
            "mean": statistics.fmean(values) if values else None,
            "median": statistics.median(values) if values else None,
        }
    return out


def report(args) -> None:
    config = load_json(args.config)
    features = list(config["features"])
    before = parse_kpm(args.before, features)
    after = parse_kpm(args.after, features)
    before_stats = feature_means(before, features)
    after_stats = feature_means(after, features)
    deltas = {}
    for feature in features:
        b = before_stats[feature]["mean"]
        a = after_stats[feature]["mean"]
        deltas[feature] = None if b is None or a is None else a - b
    result = {
        "generated_at": utc_now(),
        "mode": args.mode,
        "before_samples": len(before),
        "after_samples": len(after),
        "before": before_stats,
        "after": after_stats,
        "delta_mean": deltas,
        "notes": {
            "emulate_expect": "DRB.UEThpUl mean should drop under UL load when tc is applied",
            "real_expect": "CONTROL action=2 evidence in actuator audit; KPM impact may be limited on OAI PoC",
        },
    }
    write_json(args.output, result)
    append_event(Path(args.audit), {"event": "effect_report", "output": str(args.output), "delta_mean": deltas})
    print(f"effect_report: {args.output}")
    print(json.dumps(deltas, indent=2, sort_keys=True))


def merge_actuation(config: dict, decision_actuation: dict | None, mode_override: str | None) -> dict:
    base = dict(config.get("actuation") or {})
    if decision_actuation:
        for key, value in decision_actuation.items():
            if isinstance(value, dict):
                nested = dict(base.get(key) or {})
                nested.update(value)
                base[key] = nested
            else:
                base[key] = value
    return resolve_actuation({"actuation": base}, mode_override)


def apply_cmd(args) -> None:
    _raw, bundle = load_decision_or_policy(Path(args.decision))
    config = load_json(args.config) if args.config else {}
    mode_override = args.mode or os.environ.get("ACTUATION_MODE")
    actuation = merge_actuation(config, bundle.get("actuation"), mode_override)
    policy = bundle.get("policy") or None
    if isinstance(policy, dict) and not policy:
        policy = None
    decision = (bundle.get("evaluation") or _raw.get("evaluation") or {}).get("decision")
    if policy is None and decision != "apply" and not args.force:
        audit = Path(args.audit)
        append_event(
            audit,
            {
                "event": "apply_skipped",
                "reason": "observe_without_policy",
                "mode": actuation["mode"],
            },
        )
        print("atuação omitida: decisão observe (sem policy). Use --force para forçar.")
        return

    audit = Path(args.audit)
    append_event(
        audit,
        {
            "event": "apply_start",
            "mode": actuation["mode"],
            "policy_id": (policy or {}).get("policy_id"),
            "dry_run": args.dry_run,
        },
    )
    if actuation["mode"] == "emulate":
        detail = apply_emulate(actuation, audit, dry_run=args.dry_run)
    else:
        if not args.e2_node_id:
            raise RuntimeError("modo real exige --e2-node-id")
        detail = apply_real(
            actuation,
            audit,
            e2_node_id=args.e2_node_id,
            ue_id=args.ue_id,
            dry_run=args.dry_run,
        )
    state = {
        "applied_at": utc_now(),
        "actuation": actuation,
        "detail": detail,
        "ttl_sec": int(actuation.get("ttl_sec", 30)),
    }
    write_json(args.state, state)
    print(json.dumps(state, indent=2, sort_keys=True))


def rollback_cmd(args) -> None:
    state = load_json(args.state) if Path(args.state).is_file() else {}
    actuation = state.get("actuation") or load_json(args.config).get("actuation") or {}
    if args.mode:
        actuation["mode"] = args.mode
    mode = actuation.get("mode", "emulate")
    audit = Path(args.audit)
    if mode == "emulate":
        detail = rollback_emulate(actuation, audit, dry_run=args.dry_run)
    else:
        detail = rollback_real(actuation, audit, dry_run=args.dry_run)
    append_event(audit, {"event": "rollback_done", **detail})
    print(json.dumps(detail, indent=2, sort_keys=True))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    sub = root.add_subparsers(dest="command", required=True)

    apply_p = sub.add_parser("apply", help="aplicar atuação emulate|real")
    apply_p.add_argument("--decision", required=True, help="decision.json ou policy.json")
    apply_p.add_argument("--config", default=str(ROOT / "config/ai-policy/closed_loop.json"))
    apply_p.add_argument("--audit", required=True, help="actuator_events.jsonl")
    apply_p.add_argument("--state", required=True, help="estado para rollback")
    apply_p.add_argument("--mode", choices=["emulate", "real"])
    apply_p.add_argument("--e2-node-id", default=os.environ.get("E2_NODE_ID", ""))
    apply_p.add_argument("--ue-id", type=int, default=1)
    apply_p.add_argument("--dry-run", action="store_true")
    apply_p.add_argument(
        "--force",
        action="store_true",
        help="atuar mesmo sem policy (lab)",
    )
    apply_p.set_defaults(func=apply_cmd)

    rb = sub.add_parser("rollback", help="desfazer atuação")
    rb.add_argument("--state", required=True)
    rb.add_argument("--audit", required=True)
    rb.add_argument("--config", default=str(ROOT / "config/ai-policy/closed_loop.json"))
    rb.add_argument("--mode", choices=["emulate", "real"])
    rb.add_argument("--dry-run", action="store_true")
    rb.set_defaults(func=rollback_cmd)

    rep = sub.add_parser("report", help="comparar KPM before/after")
    rep.add_argument("--config", default=str(ROOT / "config/ai-policy/closed_loop.json"))
    rep.add_argument("--before", required=True)
    rep.add_argument("--after", required=True)
    rep.add_argument("--output", required=True)
    rep.add_argument("--audit", required=True)
    rep.add_argument("--mode", default="unknown")
    rep.set_defaults(func=report)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        args.func(args)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        if isinstance(exc, subprocess.CalledProcessError) and exc.stderr:
            print(exc.stderr, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
