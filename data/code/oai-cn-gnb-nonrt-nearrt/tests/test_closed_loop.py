#!/usr/bin/env python3

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_module(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


PIPELINE = load_module("pipeline", "scripts/ai_policy_pipeline.py")
ACTUATOR = load_module("actuator", "scripts/closed_loop_actuator.py")


class ClosedLoopContractTest(unittest.TestCase):
    def test_closed_loop_config_and_actuation(self):
        config = json.loads((ROOT / "config/ai-policy/closed_loop.json").read_text())
        self.assertIn("actuation", config)
        act = PIPELINE.resolve_actuation(config, "emulate")
        self.assertEqual("emulate", act["mode"])
        act_real = PIPELINE.resolve_actuation(config, "real")
        self.assertEqual(2, int(act_real["real"]["control_action_id"]))

    def test_reject_prb_quota_action(self):
        config = {
            "actuation": {
                "mode": "real",
                "real": {"control_action_id": 6, "forbidden_actions": [6]},
            }
        }
        with self.assertRaises(ValueError):
            PIPELINE.resolve_actuation(config, "real")

    def test_parse_fase2_colon_format(self):
        text = "\n".join(
            [
                "    DRB.UEThpUl: 3.720 kbps",
                "    RRU.PrbTotUl: 2.000 %",
                "    DRB.RlcSduDelayDl: 10.000 us",
                "    DRB.UEThpUl: 80000.000 kbps",
                "    RRU.PrbTotUl: 99.000 %",
                "    DRB.RlcSduDelayDl: 200.000 us",
            ]
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "kpm.log"
            path.write_text(text, encoding="utf-8")
            samples = PIPELINE.parse_kpm(
                path, ["RRU.PrbTotUl", "DRB.RlcSduDelayDl", "DRB.UEThpUl"]
            )
        self.assertEqual(2, len(samples))
        self.assertGreater(samples[1]["DRB.UEThpUl"], 1000)

    def test_policy_keeps_osc_schema_clean(self):
        config = json.loads((ROOT / "config/ai-policy/closed_loop.json").read_text())
        act = PIPELINE.resolve_actuation(config, "emulate")
        policy = PIPELINE.build_policy(
            config, {"decision": "apply", "anomalous_features": ["RRU.PrbTotUl"]}, act
        )
        self.assertNotIn("intent", policy["policy_data"])
        self.assertIn("actuation", policy)
        self.assertEqual("emulate", policy["actuation"]["mode"])

    def test_force_apply_builds_policy(self):
        config = json.loads((ROOT / "config/ai-policy/closed_loop.json").read_text())
        with tempfile.TemporaryDirectory() as directory:
            decision = Path(directory) / "decision.json"
            decision.write_text(
                json.dumps(
                    {
                        "evaluation": {
                            "decision": "observe",
                            "latest": {
                                "decision": "observe",
                                "sample": {
                                    "RRU.PrbTotUl": 95.0,
                                    "DRB.RlcSduDelayDl": 50.0,
                                    "DRB.UEThpUl": 80000.0,
                                },
                            },
                        },
                        "policy": None,
                    }
                ),
                encoding="utf-8",
            )
            args = type(
                "A",
                (),
                {
                    "decision": str(decision),
                    "config": str(ROOT / "config/ai-policy/closed_loop.json"),
                    "output": None,
                    "reason": "unit-test",
                    "actuation_mode": "emulate",
                },
            )()
            PIPELINE.force_apply(args)
            out = json.loads(decision.read_text())
            self.assertEqual("apply", out["evaluation"]["decision"])
            self.assertTrue(out["evaluation"]["force_apply"])
            self.assertIsNotNone(out["policy"])
            self.assertEqual("emulate", out["actuation"]["mode"])
            self.assertEqual(config["policytype_id"], out["policy"]["policytype_id"])


class ClosedLoopActuatorTest(unittest.TestCase):
    def test_apply_skips_observe_without_force(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            decision = base / "decision.json"
            audit = base / "events.jsonl"
            state = base / "state.json"
            decision.write_text(
                json.dumps({"evaluation": {"decision": "observe"}, "policy": None}),
                encoding="utf-8",
            )
            args = type(
                "A",
                (),
                {
                    "decision": str(decision),
                    "config": str(ROOT / "config/ai-policy/closed_loop.json"),
                    "audit": str(audit),
                    "state": str(state),
                    "mode": "emulate",
                    "e2_node_id": "",
                    "ue_id": 1,
                    "dry_run": True,
                    "force": False,
                },
            )()
            ACTUATOR.apply_cmd(args)
            self.assertFalse(state.is_file())
            events = [json.loads(line) for line in audit.read_text().splitlines() if line.strip()]
            self.assertEqual("apply_skipped", events[-1]["event"])

    def test_validate_real_rejects_action_6(self):
        with self.assertRaises(RuntimeError):
            ACTUATOR.validate_real_actuation(
                {"real": {"control_action_id": 6, "forbidden_actions": [6]}}
            )

    def test_report_before_after(self):
        before = "\n".join(
            [
                "RRU.PrbTotUl = 90",
                "DRB.RlcSduDelayDl = 100",
                "DRB.UEThpUl = 50000",
            ]
        )
        after = "\n".join(
            [
                "RRU.PrbTotUl = 20",
                "DRB.RlcSduDelayDl = 40",
                "DRB.UEThpUl = 5000",
            ]
        )
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            b = base / "before.log"
            a = base / "after.log"
            out = base / "effect.json"
            audit = base / "events.jsonl"
            b.write_text(before + "\n", encoding="utf-8")
            a.write_text(after + "\n", encoding="utf-8")
            args = type(
                "A",
                (),
                {
                    "config": str(ROOT / "config/ai-policy/closed_loop.json"),
                    "before": str(b),
                    "after": str(a),
                    "output": str(out),
                    "audit": str(audit),
                    "mode": "emulate",
                },
            )()
            ACTUATOR.report(args)
            report = json.loads(out.read_text())
            self.assertLess(report["delta_mean"]["DRB.UEThpUl"], 0)
            self.assertTrue(audit.is_file())


if __name__ == "__main__":
    unittest.main()
