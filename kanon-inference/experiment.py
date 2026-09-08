#!/usr/bin/env python3
"""Compare frozen prompt profiles on train/validation, then replay the winner.

Hashes detect local changes. They do not authenticate an author, conceal test
data, or establish independence of developer-authored diagnostic tasks.
"""

from __future__ import annotations

import argparse
import math
import os
from pathlib import Path
import re
import sys
import tempfile
from typing import Any

import benchmark
import splits


ROOT = Path(__file__).resolve().parents[1]
driver = benchmark.driver
Error = benchmark.Error
LIMIT = benchmark.CORPUS_LIMIT
RULE = "maximum_validation_semantic_count_then_plan_order"
PROVIDERS = {
    "source-v3": "kanon-inference/provider",
    "kanon-primer-v1": "kanon-inference/provider-primer",
}
PROMPT_VERSIONS = {"source-v3": "kanon-source-completion-v3", "kanon-primer-v1": "kanon-primer-v1"}
IMPLEMENTATION = (
    "kanon-inference/runtime.py", "kanon-inference/prompts.py",
    "kanon-inference/provider", "kanon-inference/provider-primer",
    "kanon-inference/benchmark.py", "kanon-inference/splits.py",
    "kanon-inference/baseline.py", "kanon-inference/experiment.py",
    "kanon-synth/dev/synth.py",
)
IDENTITY_KEYS = (
    "model_id", "revision", "sha256", "tokenizer_sha256", "backend",
    "backend_version", "tokenizers_version", "numpy_version", "quantization",
    "model_size_bytes", "tokenizer_size_bytes", "cpu_threads", "python", "platform",
)
STRATEGIES = ["candidate_order", "deterministic", "provider"]
REPORT_KEYS = {
    "schema_version", "complete", "purpose", "strategies", "configuration", "corpus", "split",
    "compiler", "provider", "implementation", "results", "summary", "failure", "total_seconds",
    "gate", "confidence_note", "timing_note",
}
METRICS = (
    "first_attempt_type_accepted", "type_accepted", "first_attempt_semantic_correct",
    "semantic_correct", "host_disagreement",
)
INTEGRITY_NOTE = "Local byte integrity only; no cryptographic authorship, secrecy, or independent generalization claim"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise Error("invalid_experiment", message)


def keys(value: Any, expected: set[str], label: str) -> None:
    require(type(value) is dict and set(value) == expected, f"Malformed {label} fields")


def digest(value: Any) -> bool:
    return type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def relative_path(value: Any, directory: Path = ROOT) -> Path:
    require(type(value) is str and bool(value) and "\\" not in value,
            "Expected a relative POSIX path")
    path = Path(value)
    require(not path.is_absolute() and path.as_posix() == value
            and all(part not in (".", "..") for part in path.parts),
            "Paths must be normalized and relative without parent traversal")
    resolved = (directory / path).resolve()
    require(resolved.exists(), f"Missing file: {value}")
    require(resolved.is_relative_to(directory.resolve()), "Relative path escapes its directory")
    require(resolved.is_file(), "Expected a regular file")
    return resolved


def source_path(value: Any) -> Path:
    return relative_path(value, ROOT)


def read_json(path: Path, label: str) -> tuple[bytes, Any]:
    data = driver.read_bounded(path, LIMIT, label)
    return data, driver.strict_json(data, label)


def validate_plan(value: Any) -> dict[str, Any]:
    keys(value, {"schema_version", "name", "corpus", "split_manifest", "approaches",
                 "hosts", "provider_timeout", "check_timeout", "selection_rule",
                 "exposure_disclosure"}, "plan")
    require(type(value["schema_version"]) is int and value["schema_version"] == 1,
            "Unsupported plan version")
    for field, maximum in (("name", 200), ("exposure_disclosure", 8192)):
        require(type(value[field]) is str and 0 < len(value[field].strip()) <= maximum,
                f"Plan {field} must be bounded nonempty text")
    require(value["selection_rule"] == RULE, "Unsupported selection rule")
    for field in ("corpus", "split_manifest"):
        source_path(value[field])
    require(type(value["hosts"]) is list and bool(value["hosts"])
            and all(type(host) is str and host in benchmark.HOSTS for host in value["hosts"])
            and len(set(value["hosts"])) == len(value["hosts"]), "Invalid hosts")
    for field in ("provider_timeout", "check_timeout"):
        require(type(value[field]) in (int, float) and math.isfinite(value[field])
                and 0 < value[field] <= 3600, f"Invalid {field}")
    approaches = value["approaches"]
    require(type(approaches) is list and len(approaches) == len(PROVIDERS),
            "Declare both supported prompt approaches exactly once")
    seen_ids: set[str] = set()
    seen_profiles: set[str] = set()
    for approach in approaches:
        keys(approach, {"id", "provider", "prompt_profile"}, "approach")
        identifier = approach["id"]
        profile = approach["prompt_profile"]
        require(type(identifier) is str and re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", identifier)
                is not None and identifier not in seen_ids, "Invalid or duplicate approach id")
        require(type(profile) is str and profile in PROVIDERS and profile not in seen_profiles,
                "Invalid or duplicate prompt profile")
        require(approach["provider"] == PROVIDERS[profile], "Prompt profile requires its fixed provider")
        source_path(approach["provider"])
        seen_ids.add(identifier)
        seen_profiles.add(profile)
    return value


def configuration(plan: dict[str, Any]) -> dict[str, Any]:
    return {"hosts": plan["hosts"], "provider_timeout": plan["provider_timeout"],
            "check_timeout": plan["check_timeout"], "max_candidates": driver.MAX_CANDIDATES,
            "max_new_tokens": 96}


def corpus_data(plan: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    raw, corpus = read_json(source_path(plan["corpus"]), "corpus")
    benchmark.validate_corpus(corpus)
    _, manifest = read_json(source_path(plan["split_manifest"]), "split manifest")
    try:
        splits.validate_manifest(manifest, corpus, driver.sha256(raw))
        for name in splits.SPLITS:
            splits.select_tasks(corpus, manifest, name)
    except splits.SplitError as exc:
        raise Error("invalid_experiment", str(exc)) from exc
    return corpus, manifest


def compiler_record(path: Path) -> dict[str, str]:
    path = path.resolve(strict=True)
    require(path.is_file(), "Compiler must be a file")
    relative = path.is_relative_to(ROOT.resolve())
    return {"path": path.relative_to(ROOT.resolve()).as_posix() if relative else str(path),
            "scope": "root" if relative else "absolute", "sha256": driver.file_sha256(path)}


def compiler_path(record: dict[str, Any]) -> Path:
    keys(record, {"path", "scope", "sha256"}, "compiler record")
    require(digest(record["sha256"]), "Invalid compiler hash")
    require(record["scope"] in ("root", "absolute"), "Invalid compiler scope")
    if record["scope"] == "root":
        path = source_path(record["path"])
    else:
        require(type(record["path"]) is str and Path(record["path"]).is_absolute(),
                "Compiler requires an absolute path")
        path = Path(record["path"]).resolve()
        require(path.exists(), f"Missing file: {record['path']}")
    require(path.is_file() and driver.file_sha256(path) == record["sha256"],
            "Frozen compiler changed")
    return path


def freeze(plan_path: Path, plan_raw: bytes, plan: dict[str, Any], compiler: Path) -> dict[str, Any]:
    plan_path = plan_path.resolve(strict=True)
    require(plan_path.is_relative_to(ROOT.resolve()), "Plan must be inside the checkout")
    plan_relative = plan_path.relative_to(ROOT.resolve()).as_posix()
    paths = {*IMPLEMENTATION, plan["corpus"], plan["split_manifest"], plan_relative}
    require(len(paths) == len(IMPLEMENTATION) + 3, "Plan, corpus and manifest require distinct files")
    frozen = {"plan_path": plan_relative, "plan_sha256": driver.sha256(plan_raw),
              "sources": {path: driver.file_sha256(source_path(path)) for path in sorted(paths)},
              "compiler": compiler_record(compiler)}
    require(frozen["sources"][plan_relative] == frozen["plan_sha256"], "Plan changed during freezing")
    return frozen


def check_frozen(frozen: dict[str, Any], plan: dict[str, Any], directory: Path) -> Path:
    keys(frozen, {"plan_path", "plan_sha256", "sources", "compiler"}, "frozen inputs")
    require(digest(frozen["plan_sha256"]), "Invalid plan hash")
    require(type(frozen["plan_path"]) is str, "Invalid plan path")
    expected = {*IMPLEMENTATION, plan["corpus"], plan["split_manifest"], frozen["plan_path"]}
    require(type(frozen["sources"]) is dict and set(frozen["sources"]) == expected
            and len(expected) == len(IMPLEMENTATION) + 3, "Incomplete frozen source set")
    for path, expected_hash in frozen["sources"].items():
        require(digest(expected_hash) and driver.file_sha256(source_path(path)) == expected_hash,
                f"Frozen source changed: {path}")
    raw, copied = read_json(relative_path("plan.json", directory), "frozen plan")
    require(driver.sha256(raw) == frozen["plan_sha256"]
            == frozen["sources"][frozen["plan_path"]] and copied == plan, "Frozen plan changed")
    # Bind executing modules as well as their source paths, including driver overrides.
    for module, path in ((benchmark, "kanon-inference/benchmark.py"),
                         (splits, "kanon-inference/splits.py"),
                         (driver, "kanon-synth/dev/synth.py")):
        require(driver.file_sha256(Path(module.__file__)) == frozen["sources"][path],
                f"Loaded implementation does not match frozen source: {path}")
    return compiler_path(frozen["compiler"])


def validate_result(result: Any, task: dict[str, Any], hosts: list[str]) -> None:
    require(type(result) is dict and all(type(result.get(key)) is bool for key in METRICS),
            "Incomplete or malformed strategy metrics")
    require("failure" in result and (result["failure"] is None or
            (type(result["failure"]) is dict and type(result["failure"].get("code")) is str)),
            "Missing strategy outcome")
    for field in ("total_seconds",):
        require(type(result.get(field)) in (int, float) and math.isfinite(result[field])
                and result[field] >= 0, "Invalid task timing")
    timing = result.get("cold_process_seconds")
    require(type(timing) is dict and set(timing) == {"provider", "compiler"}
            and all(type(v) in (int, float) and math.isfinite(v) and v >= 0 for v in timing.values()),
            "Invalid process timing")
    attempts = result.get("attempts")
    require(type(attempts) is list and len(attempts) <= driver.MAX_CANDIDATES,
            "Missing or oversized attempt evidence")
    for index, attempt in enumerate(attempts):
        require(type(attempt) is dict and type(attempt.get("index")) is int
                and attempt["index"] == index and type(attempt.get("type_valid")) is bool
                and digest(attempt.get("candidate_sha256")), "Invalid attempt evidence")
    ranking = result.get("ranking")
    if attempts:
        require(type(ranking) is list and len(ranking) >= len(attempts), "Attempts require ranking evidence")
        for index, attempt in enumerate(attempts):
            require(type(ranking[index]) is str
                    and attempt["candidate_sha256"] == driver.sha256(ranking[index].encode()),
                    "Attempt hash disagrees with ranked candidate")
    tests = result.get("tests")
    require(type(tests) is list and len(tests) <= len(task["tests"]), "Invalid behavioral evidence")
    for observed, expected in zip(tests, task["tests"]):
        require(type(observed) is dict and observed.get("arguments") == expected["arguments"]
                and type(observed.get("expected")) is int and observed["expected"] == expected["expected"],
                "Behavioral evidence differs from corpus oracle")
        outcomes = observed.get("hosts")
        require(type(outcomes) is dict and set(outcomes) == set(hosts), "Missing requested host evidence")
        for outcome in outcomes.values():
            require(type(outcome) is dict and set(outcome) == {"value", "error"}
                    and (type(outcome["value"]) is int or outcome["value"] is None)
                    and (outcome["error"] is None or type(outcome["error"]) is dict),
                    "Invalid host evidence")
        passed = all(outcome["error"] is None and outcome["value"] == expected["expected"]
                     for outcome in outcomes.values())
        comparison = {driver.canonical_json([outcome["value"], (outcome["error"] or {}).get("code")])
                      for outcome in outcomes.values()}
        require(type(observed.get("passed")) is bool and observed["passed"] == passed
                and type(observed.get("host_disagreement")) is bool
                and observed["host_disagreement"] == (len(comparison) > 1), "Incorrect behavioral outcome")
    semantic = len(tests) == len(task["tests"]) and all(test["passed"] for test in tests)
    require(result["semantic_correct"] == semantic
            and result["host_disagreement"] == any(test["host_disagreement"] for test in tests),
            "Incorrect semantic metric")
    require(not result["semantic_correct"] or result["type_accepted"], "Semantic success requires type acceptance")
    require((result["failure"] is None) == result["semantic_correct"], "Failure and success disagree")
    selected = result.get("selected")
    if selected is not None:
        require(type(selected) is dict and type(selected.get("index")) is int
                and 0 <= selected["index"] < len(attempts)
                and type(selected.get("candidate")) is str and selected["candidate"] in task["candidates"]
                and selected.get("candidate_sha256") == driver.sha256(selected["candidate"].encode())
                and attempts[selected["index"]]["type_valid"]
                and selected["candidate_sha256"] == attempts[selected["index"]]["candidate_sha256"]
                and selected["candidate"] == ranking[selected["index"]]
                and selected["index"] == len(attempts) - 1
                and not any(attempt["type_valid"] for attempt in attempts[:-1]),
                "Invalid selected candidate")
    else:
        require(not any(attempt["type_valid"] for attempt in attempts), "Accepted attempt lacks selected candidate")
    require(not result["type_accepted"] or selected is not None, "Type acceptance requires selected evidence")
    first_type = result["type_accepted"] and selected["index"] == 0
    require(result["first_attempt_type_accepted"] == first_type
            and result["first_attempt_semantic_correct"] == (first_type and semantic),
            "Incorrect first-attempt metric")


def provider_identity(result: dict[str, Any], approach: dict[str, Any], frozen: dict[str, Any]) -> dict[str, Any] | None:
    if "ranking" not in result:
        require(not result["type_accepted"] and bool(result["failure"]),
                "Provider result lacks ranking evidence")
        return None
    require(type(result.get("provider_exit_status")) is int and result["provider_exit_status"] == 0,
            "Successful provider protocol requires zero exit status")
    provenance = result.get("provenance")
    require(type(provenance) is dict and all(key in provenance for key in IDENTITY_KEYS),
            "Missing model runtime provenance")
    require(provenance.get("prompt_profile") == approach["prompt_profile"]
            and provenance.get("provider_code_sha256") == frozen["sources"]["kanon-inference/runtime.py"]
            and provenance.get("prompts_code_sha256") == frozen["sources"]["kanon-inference/prompts.py"]
            and digest(provenance.get("prompt_sha256"))
            and provenance.get("prompt_version") == PROMPT_VERSIONS[approach["prompt_profile"]],
            "Prompt or runtime provenance differs from frozen approach")
    identity = {key: provenance[key] for key in IDENTITY_KEYS}
    for key, value in identity.items():
        if key in ("model_size_bytes", "tokenizer_size_bytes", "cpu_threads"):
            require(type(value) is int and value > 0, "Invalid model runtime numeric provenance")
        else:
            require(type(value) is str and 0 < len(value) <= 1000, "Invalid model runtime text provenance")
    require(digest(identity["sha256"]) and digest(identity["tokenizer_sha256"]), "Invalid model hashes")
    return identity


def validate_report(report: Any, plan: dict[str, Any], frozen: dict[str, Any],
                    approach: dict[str, Any], split: str, corpus: dict[str, Any],
                    manifest: dict[str, Any], identity: dict[str, Any] | None) -> dict[str, Any] | None:
    keys(report, REPORT_KEYS, "evaluation report")
    require(report["gate"] == benchmark.GATE and report["timing_note"] == benchmark.TIMING_NOTE
            and report["confidence_note"] == benchmark.CONFIDENCE_NOTE,
            "Evaluation gate or disclosure notes differ from the benchmark")
    require(type(report) is dict and type(report.get("schema_version")) is int
            and report["schema_version"] == 1 and report.get("complete") is True
            and report.get("failure") is None and report.get("purpose") == "diagnostic",
            "Evaluation report is incomplete or failed")
    require(report.get("strategies") == STRATEGIES and report.get("configuration") == configuration(plan),
            "Evaluation strategies or budgets differ from plan")
    require(all(type(report["configuration"][field]) in (int, float)
                for field in ("provider_timeout", "check_timeout")), "Invalid evaluation timeout evidence")
    tasks = splits.select_tasks(corpus, manifest, split)
    source_hashes = frozen["sources"]
    corpus_record = report.get("corpus", {})
    require(type(corpus_record) is dict and corpus_record.get("sha256") == source_hashes[plan["corpus"]]
            and corpus_record.get("name") == corpus["name"]
            and type(corpus_record.get("available_tasks")) is int
            and corpus_record["available_tasks"] == len(corpus["tasks"])
            and type(corpus_record.get("selected_tasks")) is int
            and corpus_record["selected_tasks"] == len(tasks), "Wrong corpus or task denominator")
    record = report.get("split", {})
    modules = sorted({task["module_id"] for task in tasks})
    templates = sorted({module["template_group"] for module in manifest["modules"] if module["split"] == split})
    require(type(record) is dict and record.get("name") == split
            and record.get("manifest_sha256") == source_hashes[plan["split_manifest"]]
            and record.get("manifest_name") == manifest["name"]
            and record.get("split_unit") == splits.SPLIT_UNIT
            and type(record.get("available_tasks")) is int and record["available_tasks"] == len(tasks)
            and type(record.get("selected_tasks")) is int and record["selected_tasks"] == len(tasks)
            and record.get("limited") is False and record.get("available_modules") == modules
            and record.get("selected_modules") == modules and record.get("template_groups") == templates,
            "Wrong, limited or incomplete split evidence")
    require(type(report.get("compiler")) is dict
            and report["compiler"].get("sha256") == frozen["compiler"]["sha256"]
            and type(report.get("provider")) is dict
            and report["provider"].get("sha256") == source_hashes[approach["provider"]],
            "Wrong compiler or provider evidence")
    expected_implementation = {name + "_sha256": source_hashes[path] for name, path in (
        ("benchmark", "kanon-inference/benchmark.py"), ("splits", "kanon-inference/splits.py"),
        ("driver", "kanon-synth/dev/synth.py"), ("baseline", "kanon-inference/baseline.py"))}
    require(report.get("implementation") == expected_implementation, "Wrong benchmark implementation evidence")
    results = report.get("results")
    require(type(results) is list and len(results) == len(tasks), "Incomplete task evidence")
    for item, task in zip(results, tasks):
        require(type(item) is dict and all(item.get(key) == task[key] for key in ("id", "family", "module_id"))
                and item.get("source_sha256") == driver.sha256(task["source"].encode())
                and item.get("pool_sha256") == driver.sha256(driver.canonical_json(task["candidates"])),
                "Wrong, duplicate or reordered task evidence")
        require(type(item.get("strategies")) is dict and set(item["strategies"]) == set(STRATEGIES),
                "Pending or missing strategy evidence")
        for result in item["strategies"].values():
            validate_result(result, task, plan["hosts"])
            if "ranking" in result:
                require(type(result["ranking"]) is list and len(result["ranking"]) == len(task["candidates"])
                        and all(type(value) is str for value in result["ranking"])
                        and set(result["ranking"]) == set(task["candidates"]), "Ranking changed the candidate pool")
        observed = provider_identity(item["strategies"]["provider"], approach, frozen)
        if observed is not None:
            require(identity is None or identity == observed, "Model runtime identity changed between tasks or approaches")
            identity = observed
    require(driver.canonical_json(report.get("summary")) == driver.canonical_json(benchmark.summarize(report, tasks)),
            "Summary disagrees with complete task evidence")
    return identity


def evidence_record(path: Path, directory: Path, approach: dict[str, Any], split: str) -> dict[str, Any]:
    return {"approach_id": approach["id"], "split": split,
            "path": path.relative_to(directory).as_posix(), "sha256": driver.file_sha256(path)}


def evidence_data(record: Any, directory: Path, approach: dict[str, Any], split: str) -> dict[str, Any]:
    keys(record, {"approach_id", "split", "path", "sha256"}, "evaluation evidence")
    require(record["approach_id"] == approach["id"] and record["split"] == split
            and digest(record["sha256"]), "Wrong evaluation evidence assignment")
    raw, report = read_json(relative_path(record["path"], directory), "evaluation evidence")
    require(driver.sha256(raw) == record["sha256"], "Evaluation evidence bytes changed")
    return report


def validate_selection(path: Path) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any]]:
    _, selection = read_json(path, "selection")
    keys(selection, {"schema_version", "complete", "plan", "frozen", "evidence",
                     "model_identity", "scores", "winner", "integrity_note"}, "selection")
    require(type(selection["schema_version"]) is int and selection["schema_version"] == 1
            and selection["complete"] is True and selection["integrity_note"] == INTEGRITY_NOTE,
            "Incomplete or unsupported selection")
    plan = validate_plan(selection["plan"])
    directory = path.resolve(strict=True).parent
    check_frozen(selection["frozen"], plan, directory)
    corpus, manifest = corpus_data(plan)
    evidence = selection["evidence"]
    require(type(evidence) is list and len(evidence) == 2 * len(plan["approaches"]),
            "Selection requires complete train and validation reports")
    identity = None
    scores = []
    used_paths: set[Path] = set()
    for index, (split, approach) in enumerate((split, approach) for split in ("train", "validation")
                                             for approach in plan["approaches"]):
        record = evidence[index]
        report = evidence_data(record, directory, approach, split)
        report_path = relative_path(record["path"], directory)
        require(report_path not in used_paths, "Duplicate evidence path")
        used_paths.add(report_path)
        identity = validate_report(report, plan, selection["frozen"], approach, split,
                                   corpus, manifest, identity)
        if index == len(plan["approaches"]) - 1:
            require(identity is not None, "No successful provider protocol on train; model runtime cannot be pinned")
        if split == "validation":
            overall = report["summary"]["provider"]["overall"]
            scores.append({"approach_id": approach["id"],
                           "semantic_correct": overall["semantic_correct"]["count"],
                           "denominator": overall["semantic_correct"]["denominator"],
                           "failures": overall["failures"]})
    winner = max(scores, key=lambda item: item["semantic_correct"])["approach_id"]
    require(driver.canonical_json(selection["model_identity"]) == driver.canonical_json(identity)
            and driver.canonical_json(selection["scores"]) == driver.canonical_json(scores)
            and selection["winner"] == winner, "Edited selection disagrees with deterministic evidence")
    check_frozen(selection["frozen"], plan, directory)
    return selection, plan, corpus, manifest


def benchmark_args(plan: dict[str, Any], compiler: Path, approach: dict[str, Any], split: str, output: Path) -> argparse.Namespace:
    return benchmark.parser().parse_args([
        "--corpus", str(source_path(plan["corpus"])), "--split-manifest", str(source_path(plan["split_manifest"])),
        "--split", split, "--compiler", str(compiler), "--provider", str(source_path(approach["provider"])),
        "--hosts", ",".join(plan["hosts"]), "--timeout", str(plan["provider_timeout"]),
        "--check-timeout", str(plan["check_timeout"]), "--output", str(output),
    ])


def replay(args: argparse.Namespace) -> dict[str, Any]:
    selection_raw, _ = read_json(args.selection, "selection")
    selection, plan, corpus, manifest = validate_selection(args.selection)
    frozen = selection["frozen"]
    directory = args.selection.resolve(strict=True).parent
    compiler = check_frozen(frozen, plan, directory)
    approach = next(approach for approach in plan["approaches"] if approach["id"] == selection["winner"])
    output_file = benchmark.ReportFile(args.output)
    # Reserve the public output before starting, and publish success only after
    # all postflight checks. On interruption, retain the benchmark's partial data.
    with tempfile.TemporaryDirectory(prefix=".kan-experiment-test-", dir=args.output.absolute().parent) as temporary:
        pending = Path(temporary) / "test.json"
        try:
            report = benchmark.run(benchmark_args(plan, compiler, approach, "test", pending))
            check_frozen(frozen, plan, directory)
            require(driver.read_bounded(args.selection, LIMIT, "selection") == selection_raw,
                    "Selection changed during test evaluation")
            validate_selection(args.selection)
            _, saved = read_json(pending, "test report")
            require(saved == report, "Saved test report differs from evaluation")
            validate_report(saved, plan, frozen, approach, "test", corpus, manifest, selection["model_identity"])
            check_frozen(frozen, plan, directory)
            output_file.write(saved)
        except (KeyboardInterrupt, Error, OSError, UnicodeError, ValueError, RecursionError) as exc:
            incomplete = {"schema_version": 1, "complete": False}
            if pending.exists():
                try:
                    _, partial = read_json(pending, "partial test report")
                    if type(partial) is dict:
                        incomplete = partial
                except (Error, OSError, UnicodeError, ValueError, RecursionError) as read_exc:
                    incomplete["partial_read_failure"] = (
                        read_exc.as_json() if isinstance(read_exc, Error)
                        else {"code": "partial_unreadable", "message": str(read_exc)[:4096]})
            incomplete["complete"] = False
            incomplete["failure"] = (exc.as_json() if isinstance(exc, Error) else
                {"code": "interrupted" if isinstance(exc, KeyboardInterrupt) else "test_validation_failed",
                 "message": "Test interrupted" if isinstance(exc, KeyboardInterrupt) else str(exc)})
            output_file.write(incomplete)
            raise
    return {"complete": True, "winner": approach["id"], "selection_sha256": driver.sha256(selection_raw),
            "output": args.output.name, "sha256": driver.file_sha256(args.output),
            "summary": report["summary"]["provider"]["overall"]}


def run(args: argparse.Namespace) -> dict[str, Any]:
    plan_raw, value = read_json(args.plan, "plan")
    plan = validate_plan(value)
    corpus, manifest = corpus_data(plan)
    frozen = freeze(args.plan, plan_raw, plan, args.compiler)
    directory = args.output_dir.absolute()
    try:
        directory.mkdir(parents=True, exist_ok=False)
    except FileExistsError as exc:
        raise Error("output_exists", "Experiment directory already exists; choose a new directory") from exc
    report_file = benchmark.ReportFile(directory / "experiment.json")
    report: dict[str, Any] = {"schema_version": 1, "complete": False, "plan": plan, "frozen": frozen,
                              "evidence": [], "selection": None, "test": None,
                              "failure": None, "integrity_note": INTEGRITY_NOTE}
    report_file.write(report)
    try:
        with (directory / "plan.json").open("xb") as stream:
            stream.write(plan_raw)
            stream.flush()
            os.fsync(stream.fileno())
        identity = None
        scores = []
        for split in ("train", "validation"):
            for approach in plan["approaches"]:
                compiler = check_frozen(frozen, plan, directory)
                output = directory / f"{split}-{approach['id']}.json"
                result = benchmark.run(benchmark_args(plan, compiler, approach, split, output))
                check_frozen(frozen, plan, directory)
                _, saved = read_json(output, "evaluation report")
                require(saved == result, "Saved report differs from evaluation")
                identity = validate_report(saved, plan, frozen, approach, split, corpus, manifest, identity)
                report["evidence"].append(evidence_record(output, directory, approach, split))
                if split == "validation":
                    overall = saved["summary"]["provider"]["overall"]
                    scores.append({"approach_id": approach["id"],
                                   "semantic_correct": overall["semantic_correct"]["count"],
                                   "denominator": overall["semantic_correct"]["denominator"],
                                   "failures": overall["failures"]})
                report_file.write(report)
            if split == "train":
                require(identity is not None, "No successful provider protocol on train; model runtime cannot be pinned")
        selection = {"schema_version": 1, "complete": True, "plan": plan, "frozen": frozen,
                     "evidence": report["evidence"], "model_identity": identity, "scores": scores,
                     "winner": max(scores, key=lambda item: item["semantic_correct"])["approach_id"],
                     "integrity_note": INTEGRITY_NOTE}
        selection_path = directory / "selection.json"
        benchmark.ReportFile(selection_path).write(selection)
        report["selection"] = {"path": "selection.json", "sha256": driver.file_sha256(selection_path),
                               "winner": selection["winner"]}
        report_file.write(report)
        report["test"] = replay(argparse.Namespace(selection=selection_path, output=directory / "test.json"))
        check_frozen(frozen, plan, directory)
        require(driver.file_sha256(selection_path) == report["selection"]["sha256"], "Selection changed before publication")
        report["complete"] = True
    except KeyboardInterrupt:
        report["failure"] = {"code": "interrupted", "message": "Experiment interrupted; retained outputs are incomplete"}
        raise
    except (Error, OSError, UnicodeError, ValueError, RecursionError) as exc:
        report["failure"] = exc.as_json() if isinstance(exc, Error) else {"code": "experiment_failed", "message": str(exc)}
        raise
    finally:
        report_file.write(report)
    return report


def parser() -> argparse.ArgumentParser:
    result = driver.StructuredParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    run_parser = commands.add_parser("run", help="Freeze a plan, compare approaches and evaluate the selected test split")
    run_parser.add_argument("--plan", required=True, type=Path)
    run_parser.add_argument("--compiler", required=True, type=Path)
    run_parser.add_argument("--output-dir", required=True, type=Path)
    test_parser = commands.add_parser("test", help="Verify frozen selection evidence and replay only its test approach")
    test_parser.add_argument("--selection", required=True, type=Path)
    test_parser.add_argument("--output", required=True, type=Path)
    return result


def main(argv: list[str] | None = None) -> int:
    try:
        args = parser().parse_args(argv)
        result = run(args) if args.command == "run" else replay(args)
        print(driver.canonical_json({"complete": result["complete"],
              "output": str((args.output_dir / "experiment.json" if args.command == "run" else args.output).absolute())}).decode())
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
