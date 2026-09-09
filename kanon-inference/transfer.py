#!/usr/bin/env python3
"""Compare two fixed scoring methods on an entirely exposed development corpus.

Verification checks saved numerical evidence and local byte integrity. It neither
reruns the compiler nor establishes independent authorship or generalization.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import tempfile
from typing import Any

import experiment


benchmark = experiment.benchmark
driver = experiment.driver
Error = experiment.Error
require = experiment.require
keys = experiment.keys
read_json = experiment.read_json
source_path = experiment.source_path
RULE = "fixed_development_comparison_no_selection"
IMPLEMENTATION = (*experiment.IMPLEMENTATION, "kanon-inference/transfer.py")
APPROACHES = [
    {"id": "source-v3", "provider": "kanon-inference/provider",
     "prompt_profile": "source-v3", "scoring_profile": "conditional-v1"},
    {"id": "hint-calibrated-v1", "provider": "kanon-inference/provider-calibrated",
     "prompt_profile": "source-v3", "scoring_profile": "hint-calibrated-v1"},
]
REPORT_KEYS = {"schema_version", "complete", "purpose", "plan", "frozen", "evidence",
               "model_identity", "scoring_identities", "summary", "failure", "integrity_note"}
NOTE = ("Development comparison only: both fixed methods see the full exposed corpus; "
        "no training, validation selection, promotion, unseen test, or generalization claim")
PAIRED_METRICS = ("first_attempt_semantic_correct", "semantic_correct")


def validate_plan(value: Any) -> dict[str, Any]:
    keys(value, {"schema_version", "name", "corpus", "split_manifest", "authorship",
                 "approaches", "hosts", "provider_timeout", "check_timeout",
                 "comparison_rule", "exposure_disclosure"}, "transfer plan")
    require(type(value["schema_version"]) is int and value["schema_version"] == 1,
            "Unsupported transfer plan version")
    require(value["comparison_rule"] == RULE, "Unsupported transfer comparison rule")
    require(value["approaches"] == APPROACHES, "Transfer requires the two fixed scoring approaches in order")
    # Reuse the frozen experiment's path, text, host and budget validation without
    # invoking its split selection or its winner-selection workflow.
    compatible = {key: item for key, item in value.items()
                  if key not in ("authorship", "comparison_rule")}
    compatible["selection_rule"] = experiment.RULE
    experiment.validate_plan(compatible)
    source_path(value["authorship"])
    return value


def corpus_data(plan: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    raw, corpus = read_json(source_path(plan["corpus"]), "transfer corpus")
    benchmark.validate_corpus(corpus)
    _, manifest = read_json(source_path(plan["split_manifest"]), "transfer split manifest")
    try:
        experiment.splits.validate_manifest(manifest, corpus, driver.sha256(raw))
        require(all(module["split"] == "train" for module in manifest["modules"]),
                "Transfer must assign every module to exposed development data (train)")
        experiment.splits.select_tasks(corpus, manifest, "train")
    except experiment.splits.SplitError as exc:
        raise Error("invalid_experiment", str(exc)) from exc
    _, authorship = read_json(source_path(plan["authorship"]), "transfer authorship")
    keys(authorship, {"schema_version", "corpus_sha256", "author_role", "process",
                      "exposure_disclosure"}, "transfer authorship")
    require(type(authorship["schema_version"]) is int and authorship["schema_version"] == 1
            and authorship["corpus_sha256"] == driver.sha256(raw), "Wrong authorship corpus binding")
    for field in ("author_role", "process", "exposure_disclosure"):
        require(type(authorship[field]) is str and 0 < len(authorship[field].strip()) <= 8192,
                f"Authorship {field} must be bounded nonempty text")
    return corpus, manifest


def frozen_paths(plan: dict[str, Any], plan_path: str) -> set[str]:
    paths = {*IMPLEMENTATION, plan_path, plan["corpus"], plan["split_manifest"], plan["authorship"]}
    require(len(paths) == len(IMPLEMENTATION) + 4, "Transfer inputs require distinct files")
    return paths


def freeze(path: Path, raw: bytes, plan: dict[str, Any], compiler: Path) -> dict[str, Any]:
    path = path.resolve(strict=True)
    require(path.is_relative_to(experiment.ROOT.resolve()), "Plan must be inside the checkout")
    relative = path.relative_to(experiment.ROOT.resolve()).as_posix()
    frozen = {"plan_path": relative, "plan_sha256": driver.sha256(raw),
              "sources": {name: driver.file_sha256(source_path(name))
                          for name in sorted(frozen_paths(plan, relative))},
              "compiler": experiment.compiler_record(compiler)}
    require(frozen["sources"][relative] == frozen["plan_sha256"], "Plan changed during freezing")
    return frozen


def check_frozen(frozen: Any, plan: dict[str, Any], directory: Path) -> Path:
    keys(frozen, {"plan_path", "plan_sha256", "sources", "compiler"}, "transfer frozen inputs")
    require(type(frozen["plan_path"]) is str and experiment.digest(frozen["plan_sha256"]),
            "Invalid frozen transfer plan identity")
    require(type(frozen["sources"]) is dict
            and set(frozen["sources"]) == frozen_paths(plan, frozen["plan_path"]),
            "Incomplete frozen transfer source set")
    for path, expected in frozen["sources"].items():
        require(experiment.digest(expected) and driver.file_sha256(source_path(path)) == expected,
                f"Frozen source changed: {path}")
    raw, copied = read_json(experiment.relative_path("plan.json", directory), "frozen transfer plan")
    require(driver.sha256(raw) == frozen["plan_sha256"]
            == frozen["sources"][frozen["plan_path"]] and copied == plan, "Frozen plan changed")
    for module, path in ((benchmark, "kanon-inference/benchmark.py"),
                         (experiment, "kanon-inference/experiment.py"),
                         (experiment.prompts, "kanon-inference/prompts.py"),
                         (experiment.scoring, "kanon-inference/scoring.py"),
                         (experiment.splits, "kanon-inference/splits.py"),
                         (driver, "kanon-synth/dev/synth.py")):
        require(driver.file_sha256(Path(module.__file__)) == frozen["sources"][path],
                f"Loaded implementation does not match frozen source: {path}")
    require(driver.file_sha256(Path(__file__)) == frozen["sources"]["kanon-inference/transfer.py"],
            "Loaded implementation does not match frozen source: kanon-inference/transfer.py")
    return experiment.compiler_path(frozen["compiler"])


def paired(left: list[dict[str, Any]], right: list[dict[str, Any]], metric: str) -> dict[str, int]:
    require(len(left) == len(right), "Paired comparison requires matching task denominators")
    outcomes = [(a[metric], b[metric]) for a, b in zip(left, right)]
    return {"denominator": len(outcomes),
            "both_correct": sum(a and b for a, b in outcomes),
            "left_only_correct": sum(a and not b for a, b in outcomes),
            "right_only_correct": sum(b and not a for a, b in outcomes),
            "neither_correct": sum(not a and not b for a, b in outcomes),
            "left_minus_right": sum(a - b for a, b in outcomes)}


def summarize(reports: list[dict[str, Any]], plan: dict[str, Any],
              corpus: dict[str, Any]) -> dict[str, Any]:
    tasks = corpus["tasks"]
    families = sorted({task["family"] for task in tasks})
    comparisons = []
    pairs = [(index, "provider", index, baseline) for index in range(len(reports))
             for baseline in ("candidate_order", "deterministic")]
    pairs.append((0, "provider", 1, "provider"))
    for left_index, left_strategy, right_index, right_strategy in pairs:
        left = [item["strategies"][left_strategy] for item in reports[left_index]["results"]]
        right = [item["strategies"][right_strategy] for item in reports[right_index]["results"]]
        comparisons.append({
            "left": {"approach_id": plan["approaches"][left_index]["id"], "strategy": left_strategy},
            "right": {"approach_id": plan["approaches"][right_index]["id"], "strategy": right_strategy},
            "metrics": {metric: {"overall": paired(left, right, metric),
                "by_family": {family: paired(
                    [value for task, value in zip(tasks, left) if task["family"] == family],
                    [value for task, value in zip(tasks, right) if task["family"] == family], metric)
                    for family in families}} for metric in PAIRED_METRICS}})
    return {"tasks": len(tasks), "modules": len({task["module_id"] for task in tasks}),
            "approaches": [{"approach_id": approach["id"], "strategies": report["summary"]}
                           for approach, report in zip(plan["approaches"], reports)],
            "paired_comparisons": comparisons, "interpretation": NOTE}


def validate_evidence(report: dict[str, Any], directory: Path, plan: dict[str, Any],
                      corpus: dict[str, Any], manifest: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    evidence = report["evidence"]
    require(type(evidence) is list and len(evidence) == len(plan["approaches"]),
            "Transfer requires one complete report per fixed approach")
    reports = []
    identity = None
    used_paths: set[Path] = set()
    for record, approach in zip(evidence, plan["approaches"]):
        saved = experiment.evidence_data(record, directory, approach, "train")
        path = experiment.relative_path(record["path"], directory)
        require(path not in used_paths, "Duplicate evidence path")
        used_paths.add(path)
        observed = experiment.validate_report(saved, plan, report["frozen"], approach,
                                               "train", corpus, manifest, None)
        require(observed is not None, "No successful provider protocol for a fixed approach")
        require(identity is None or identity == observed, "Model runtime identity changed between approaches")
        identity = observed
        reports.append(saved)
    # Identical source bytes must also have identical recorded compiler requests
    # across both model methods, not only across the strategies within each run.
    for items in zip(*(saved["results"] for saved in reports)):
        requests = {driver.canonical_json(result["request"]) for item in items
                    for result in item["strategies"].values() if "request" in result}
        require(len(requests) <= 1, "Compiler request differs between approaches")
    return reports, identity


def validate_transfer(path: Path) -> dict[str, Any]:
    original, report = read_json(path, "transfer report")
    keys(report, REPORT_KEYS, "transfer report")
    require(type(report["schema_version"]) is int and report["schema_version"] == 1
            and report["complete"] is True and report["failure"] is None
            and report["purpose"] == "development_comparison"
            and report["integrity_note"] == experiment.INTEGRITY_NOTE,
            "Incomplete or unsupported transfer report")
    plan = validate_plan(report["plan"])
    directory = path.resolve(strict=True).parent
    check_frozen(report["frozen"], plan, directory)
    corpus, manifest = corpus_data(plan)
    reports, identity = validate_evidence(report, directory, plan, corpus, manifest)
    require(driver.canonical_json(report["model_identity"]) == driver.canonical_json(identity),
            "Transfer model identity disagrees with evidence")
    require(report["scoring_identities"] == experiment.scoring_identities(plan, report["frozen"]),
            "Transfer scoring identity disagrees with frozen sources")
    require(driver.canonical_json(report["summary"]) == driver.canonical_json(summarize(reports, plan, corpus)),
            "Transfer summary disagrees with paired evidence")
    check_frozen(report["frozen"], plan, directory)
    # Recheck recorded report hashes after validation, including the public report.
    for record, approach in zip(report["evidence"], plan["approaches"]):
        experiment.evidence_data(record, directory, approach, "train")
    require(driver.read_bounded(path, experiment.LIMIT, "transfer report") == original,
            "Transfer report changed during verification")
    return report


def run(args: argparse.Namespace) -> dict[str, Any]:
    raw, value = read_json(args.plan, "transfer plan")
    plan = validate_plan(value)
    corpus, manifest = corpus_data(plan)
    frozen = freeze(args.plan, raw, plan, args.compiler)
    directory = args.output_dir.absolute()
    try:
        directory.mkdir(parents=True, exist_ok=False)
    except FileExistsError as exc:
        raise Error("output_exists", "Transfer directory already exists; choose a new directory") from exc
    output = benchmark.ReportFile(directory / "transfer.json")
    report = {"schema_version": 1, "complete": False, "purpose": "development_comparison",
              "plan": plan, "frozen": frozen, "evidence": [], "model_identity": None,
              "scoring_identities": experiment.scoring_identities(plan, frozen), "summary": None,
              "failure": None, "integrity_note": experiment.INTEGRITY_NOTE}
    output.write(report)
    try:
        with (directory / "plan.json").open("xb") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        for approach in plan["approaches"]:
            compiler = check_frozen(frozen, plan, directory)
            path = directory / f"development-{approach['id']}.json"
            result = benchmark.run(experiment.benchmark_args(plan, compiler, approach, "train", path))
            check_frozen(frozen, plan, directory)
            _, saved = read_json(path, "development evaluation report")
            require(saved == result, "Saved report differs from evaluation")
            observed = experiment.validate_report(saved, plan, frozen, approach, "train", corpus, manifest, None)
            require(observed is not None, "No successful provider protocol for a fixed approach")
            require(report["model_identity"] is None or report["model_identity"] == observed,
                    "Model runtime identity changed between approaches")
            report["model_identity"] = observed
            report["evidence"].append(experiment.evidence_record(path, directory, approach, "train"))
            output.write(report)
        reports, identity = validate_evidence(report, directory, plan, corpus, manifest)
        report["model_identity"] = identity
        report["summary"] = summarize(reports, plan, corpus)
        check_frozen(frozen, plan, directory)
        candidate = {**report, "complete": True}
        # Validate the complete candidate privately while the public result stays
        # incomplete. The temporary file shares the evidence directory so the
        # public verifier exercises the same relative-path checks.
        with tempfile.NamedTemporaryFile(prefix=".kan-transfer-validation-", suffix=".json",
                                         dir=directory) as stream:
            stream.write(driver.canonical_json(candidate) + b"\n")
            stream.flush()
            validated = validate_transfer(Path(stream.name))
            require(validated == candidate, "Validated transfer differs from evaluation")
        output.write(candidate)
        report = candidate
    except KeyboardInterrupt:
        report["complete"] = False
        report["failure"] = {"code": "interrupted", "message": "Transfer interrupted; retained outputs are incomplete"}
        raise
    except (Error, OSError, UnicodeError, ValueError, RecursionError) as exc:
        report["complete"] = False
        report["failure"] = exc.as_json() if isinstance(exc, Error) else {"code": "transfer_failed", "message": str(exc)}
        raise
    finally:
        if not report["complete"]:
            output.write(report)
    return report


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    launch = commands.add_parser("run", help="run both fixed methods on the full development corpus")
    launch.add_argument("--plan", type=Path, required=True)
    launch.add_argument("--compiler", type=Path, required=True)
    launch.add_argument("--output-dir", type=Path, required=True)
    verify = commands.add_parser("verify", help="verify saved evidence and frozen bytes without executing a model or compiler")
    verify.add_argument("--report", type=Path, required=True)
    return result


def main(argv: list[str] | None = None) -> int:
    try:
        args = parser().parse_args(argv)
        report = run(args) if args.command == "run" else validate_transfer(args.report)
        print(driver.canonical_json({"complete": report["complete"], "comparison_rule": RULE,
            "tasks": report["summary"]["tasks"], "paired_comparisons": report["summary"]["paired_comparisons"],
            "integrity_note": report["integrity_note"]}).decode())
        return 0
    except Error as exc:
        print(driver.canonical_json({"error": exc.as_json()}).decode(), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    except (OSError, UnicodeError, ValueError, RecursionError) as exc:
        print(driver.canonical_json({"error": {"code": "io_or_encoding", "message": str(exc)}}).decode(), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
