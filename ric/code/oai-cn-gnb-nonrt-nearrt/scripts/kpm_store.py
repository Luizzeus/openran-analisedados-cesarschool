#!/usr/bin/env python3
"""Armazena amostras KPM em SQLite + JSONL para experimentos de rApp."""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

# Reusa o parser do pipeline (mesmo processo / import via path).
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ai_policy_pipeline import load_json, parse_kpm  # noqa: E402

SCHEMA = """
CREATE TABLE IF NOT EXISTS runs (
  run_id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  use_case TEXT NOT NULL,
  notes TEXT
);
CREATE TABLE IF NOT EXISTS kpm_samples (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL,
  phase TEXT NOT NULL,
  sample_index INTEGER NOT NULL,
  ingested_at TEXT NOT NULL,
  source_path TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  FOREIGN KEY(run_id) REFERENCES runs(run_id)
);
CREATE INDEX IF NOT EXISTS idx_kpm_run_phase ON kpm_samples(run_id, phase);
"""


def connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.executescript(SCHEMA)
    return conn


def ingest(
    db_path: Path,
    jsonl_path: Path,
    kpm_log: Path,
    features: list[str],
    run_id: str,
    phase: str,
    use_case: str,
    notes: str = "",
) -> int:
    samples = parse_kpm(kpm_log, features)
    now = datetime.now(timezone.utc).isoformat()
    conn = connect(db_path)
    try:
        conn.execute(
            "INSERT OR IGNORE INTO runs(run_id, created_at, use_case, notes) VALUES (?,?,?,?)",
            (run_id, now, use_case, notes),
        )
        jsonl_path.parent.mkdir(parents=True, exist_ok=True)
        with jsonl_path.open("a", encoding="utf-8") as jsonl:
            for index, sample in enumerate(samples):
                record = {
                    "run_id": run_id,
                    "phase": phase,
                    "sample_index": index,
                    "ingested_at": now,
                    "source_path": str(kpm_log),
                    "metrics": sample,
                }
                jsonl.write(json.dumps(record, sort_keys=True) + "\n")
                conn.execute(
                    """
                    INSERT INTO kpm_samples(
                      run_id, phase, sample_index, ingested_at, source_path, payload_json
                    ) VALUES (?,?,?,?,?,?)
                    """,
                    (
                        run_id,
                        phase,
                        index,
                        now,
                        str(kpm_log),
                        json.dumps(sample, sort_keys=True),
                    ),
                )
        conn.commit()
    finally:
        conn.close()
    return len(samples)


def export_phase(db_path: Path, run_id: str, phase: str, output: Path) -> int:
    conn = connect(db_path)
    try:
        rows = conn.execute(
            """
            SELECT payload_json FROM kpm_samples
            WHERE run_id=? AND phase=?
            ORDER BY sample_index
            """,
            (run_id, phase),
        ).fetchall()
    finally:
        conn.close()
    if not rows:
        raise ValueError(f"nenhuma amostra run_id={run_id} phase={phase}")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Reconstrói um pseudo-log KPM textual compatível com ai_policy_pipeline.parse_kpm
    lines = []
    for (payload,) in rows:
        metrics = json.loads(payload)
        for name, value in metrics.items():
            lines.append(f"{name} = {value}")
        lines.append("")
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return len(rows)


def summary(db_path: Path, run_id: str | None = None) -> list[dict]:
    conn = connect(db_path)
    try:
        if run_id:
            rows = conn.execute(
                """
                SELECT phase, COUNT(*) FROM kpm_samples
                WHERE run_id=? GROUP BY phase ORDER BY phase
                """,
                (run_id,),
            ).fetchall()
            return [{"run_id": run_id, "phase": p, "count": c} for p, c in rows]
        rows = conn.execute(
            """
            SELECT run_id, phase, COUNT(*) FROM kpm_samples
            GROUP BY run_id, phase ORDER BY run_id, phase
            """
        ).fetchall()
        return [{"run_id": r, "phase": p, "count": c} for r, p, c in rows]
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    ingest_cmd = sub.add_parser("ingest", help="ler log KPM e gravar SQLite+JSONL")
    ingest_cmd.add_argument("--db", required=True)
    ingest_cmd.add_argument("--jsonl", required=True)
    ingest_cmd.add_argument("--input", required=True, help="log KPM textual")
    ingest_cmd.add_argument("--config", required=True, help="pipeline.json com features")
    ingest_cmd.add_argument("--run-id", required=True)
    ingest_cmd.add_argument("--phase", required=True, choices=["baseline", "stress", "recovery", "eval"])
    ingest_cmd.add_argument("--use-case", default="ue-tp-load-anomaly")
    ingest_cmd.add_argument("--notes", default="")

    export_cmd = sub.add_parser("export", help="exportar fase do BD para log textual")
    export_cmd.add_argument("--db", required=True)
    export_cmd.add_argument("--run-id", required=True)
    export_cmd.add_argument("--phase", required=True)
    export_cmd.add_argument("--output", required=True)

    sum_cmd = sub.add_parser("summary", help="contar amostras por run/fase")
    sum_cmd.add_argument("--db", required=True)
    sum_cmd.add_argument("--run-id")

    args = parser.parse_args()
    try:
        if args.command == "ingest":
            features = load_json(args.config)["features"]
            count = ingest(
                Path(args.db),
                Path(args.jsonl),
                Path(args.input),
                features,
                args.run_id,
                args.phase,
                args.use_case,
                args.notes,
            )
            print(f"ingestidos {count} amostras -> {args.db} / {args.jsonl}")
        elif args.command == "export":
            count = export_phase(Path(args.db), args.run_id, args.phase, Path(args.output))
            print(f"exportadas {count} amostras -> {args.output}")
        else:
            print(json.dumps(summary(Path(args.db), args.run_id), indent=2))
    except (OSError, ValueError, KeyError, sqlite3.Error) as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
