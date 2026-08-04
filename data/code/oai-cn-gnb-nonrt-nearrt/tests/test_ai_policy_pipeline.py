#!/usr/bin/env python3

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "pipeline", ROOT / "scripts" / "ai_policy_pipeline.py"
)
PIPELINE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PIPELINE)


class PipelineTest(unittest.TestCase):
    def test_parse_and_infer(self):
        text = "\n".join(
            [
                "RRU.PrbTotUl = 2 [%]",
                "DRB.RlcSduDelayDl = 10.0 [μs]",
                "DRB.UEThpUl = 20.0 [kbps]",
                "RRU.PrbTotUl = 98 [%]",
                "DRB.RlcSduDelayDl = 200.0 [μs]",
                "DRB.UEThpUl = 80000.0 [kbps]",
            ]
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "kpm.log"
            path.write_text(text, encoding="utf-8")
            samples = PIPELINE.parse_kpm(
                path, ["RRU.PrbTotUl", "DRB.RlcSduDelayDl", "DRB.UEThpUl"]
            )
        self.assertEqual(2, len(samples))
        model = {
            "features": {
                "RRU.PrbTotUl": {"median": 2, "mad": 0},
                "DRB.RlcSduDelayDl": {"median": 10, "mad": 0},
                "DRB.UEThpUl": {"median": 20, "mad": 0},
            },
            "score_threshold": 3.5,
            "min_anomalous_features": 2,
            "mad_floor": 1,
        }
        self.assertEqual("observe", PIPELINE.infer(model, samples[0])["decision"])
        self.assertEqual("apply", PIPELINE.infer(model, samples[1])["decision"])

    def test_policy_shape(self):
        config = json.loads(
            (ROOT / "config" / "ai-policy" / "pipeline.json").read_text()
        )
        policy = PIPELINE.build_policy(
            config, {"decision": "apply", "anomalous_features": ["x"]}
        )
        self.assertEqual("ric-oran", policy["ric_id"])
        self.assertIn("policy_data", policy)
        self.assertEqual("ai-training-rapp", policy["service_id"])


class KpmStoreTest(unittest.TestCase):
    def test_ingest_export_roundtrip(self):
        store_spec = importlib.util.spec_from_file_location(
            "kpm_store", ROOT / "scripts" / "kpm_store.py"
        )
        store = importlib.util.module_from_spec(store_spec)
        store_spec.loader.exec_module(store)

        text = "\n".join(
            [
                "RRU.PrbTotUl = 2 [%]",
                "DRB.RlcSduDelayDl = 10.0 [μs]",
                "DRB.UEThpUl = 20.0 [kbps]",
                "RRU.PrbTotUl = 5 [%]",
                "DRB.RlcSduDelayDl = 12.0 [μs]",
                "DRB.UEThpUl = 25.0 [kbps]",
            ]
        )
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            kpm = base / "kpm.log"
            kpm.write_text(text, encoding="utf-8")
            db = base / "kpm.sqlite"
            jsonl = base / "kpm.jsonl"
            features = ["RRU.PrbTotUl", "DRB.RlcSduDelayDl", "DRB.UEThpUl"]
            count = store.ingest(
                db, jsonl, kpm, features, "run-test", "baseline", "ue-tp-load-anomaly"
            )
            self.assertEqual(2, count)
            exported = base / "out.log"
            store.export_phase(db, "run-test", "baseline", exported)
            parsed = PIPELINE.parse_kpm(exported, features)
            self.assertEqual(2, len(parsed))
            self.assertEqual(2.0, parsed[0]["RRU.PrbTotUl"])
            summary = store.summary(db, "run-test")
            self.assertEqual(1, len(summary))
            self.assertEqual(2, summary[0]["count"])


if __name__ == "__main__":
    unittest.main()
