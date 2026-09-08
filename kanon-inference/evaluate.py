#!/usr/bin/env python3
"""Compare a local proposer with candidate order on a fixed, small intent corpus."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--provider", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    raw = args.corpus.read_bytes()
    tasks = json.loads(raw)
    if not isinstance(tasks, list) or not 1 <= len(tasks) <= 100:
        raise ValueError("corpus must contain 1 to 100 tasks")
    records = []
    for task in tasks:
        request = {
            "protocol_version": 1, "context": "", "max_new_tokens": 96,
            "max_candidates": 8, "allowed_axioms": [], **task["request"],
        }
        started = time.monotonic()
        try:
            completed = subprocess.run(
                [str(args.provider.resolve())], input=json.dumps(request) + "\n",
                capture_output=True, text=True, timeout=65, check=False,
            )
            response = json.loads(completed.stdout)
        except subprocess.TimeoutExpired:
            response = {"error": {"code": "harness_timeout", "message": "provider exceeded 65 seconds"}}
        elapsed = time.monotonic() - started
        proposed = response.get("candidates", [])
        expected = task["expected_candidate"]
        record = {
            "id": task["id"], "request": request, "expected_candidate": expected,
            "first_candidate_matches_intent": bool(proposed and proposed[0] == expected),
            "candidate_order_baseline_matches_intent": request["candidates"][0] == expected,
            "end_to_end_seconds": elapsed, "response": response,
        }
        records.append(record)
        print(json.dumps({key: record[key] for key in (
            "id", "first_candidate_matches_intent", "candidate_order_baseline_matches_intent", "end_to_end_seconds",
        )}), flush=True)
        # Persist each observation so interruption cannot silently remove failures.
        args.output.parent.mkdir(parents=True, exist_ok=True)
        report = {
            "schema_version": 1, "created_at": datetime.now(timezone.utc).isoformat(),
            "corpus_sha256": hashlib.sha256(raw).hexdigest(),
            "provider": str(args.provider.resolve()), "records": records,
            "limitations": [
                "Small independent smoke set, not the 500-task held-out evaluation contract.",
                "Intent scored by exact expected expression; kernel and Wasm checks are separate.",
                "Candidate order is a weak baseline, not the strongest deterministic search baseline.",
                "Each request launches a fresh process and loads the model; timing includes cold process startup.",
            ],
            "summary": {
                "tasks_completed": len(records),
                "model_correct": sum(item["first_candidate_matches_intent"] for item in records),
                "order_baseline_correct": sum(item["candidate_order_baseline_matches_intent"] for item in records),
                "errors": sum("error" in item["response"] for item in records),
                "median_end_to_end_seconds": statistics.median(item["end_to_end_seconds"] for item in records),
            },
        }
        args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")


if __name__ == "__main__":
    main()
