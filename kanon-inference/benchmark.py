#!/usr/bin/env python3
"""Run a bounded diagnostic synthesis evaluation with separate semantic oracles.

Each strategy selects its first compiler-valid proposal before seeing test
results. Every selected task remains in the denominator, including timeouts.
Each compiler/provider call starts a fresh process; these are cold timings.
"""

from __future__ import annotations

import argparse
import importlib.util
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import sys
import tempfile
import time
from typing import Any

import splits


def load_driver() -> Any:
    path = Path(os.environ.get(
        "KANON_SYNTH_DRIVER",
        str(Path(__file__).resolve().parents[1] / "kanon-synth" / "dev" / "synth.py"),
    )).resolve(strict=True)
    spec = importlib.util.spec_from_file_location("kanon_benchmark_synth_driver", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load synthesis driver: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


driver = load_driver()
Error = driver.SynthesisError
CORPUS_LIMIT = 64 * 1024 * 1024
MAX_TASKS = 10000
MAX_CASES = 32
MAX_ARGUMENTS = 16
MAX_NAT = 1073741823
HOSTS = {"kernel", "node", "wasmtime"}
# Hosts that need an external binary. The kernel evaluates inside the compiler.
HOST_BINARIES = {"node": "node", "wasmtime": "wasmtime"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise Error("invalid_corpus", message)


def validate_corpus(value: Any) -> dict[str, Any]:
    driver.require_keys(value, {"schema_version", "name", "purpose", "tasks"}, set(), "corpus")
    require(type(value["schema_version"]) is int and value["schema_version"] == 1,
            "Unsupported corpus schema version")
    require(isinstance(value["name"], str) and 0 < len(value["name"]) <= 200,
            "Corpus name must be a nonempty string of at most 200 characters")
    require(value["purpose"] == "diagnostic", "Only diagnostic corpora are supported")
    require(isinstance(value["tasks"], list) and 1 <= len(value["tasks"]) <= MAX_TASKS,
            f"Corpus requires between 1 and {MAX_TASKS} tasks")
    seen: set[str] = set()
    for task in value["tasks"]:
        driver.require_keys(task, {"id", "family", "module_id", "source", "candidates", "tests"},
                            set(), "task")
        for key in ("id", "family", "module_id"):
            require(isinstance(task[key], str) and bool(task[key].strip()) and len(task[key]) <= 200,
                    f"Task {key} must be a nonempty string of at most 200 characters")
        require(task["id"] not in seen, f"Duplicate task id: {task['id']}")
        seen.add(task["id"])
        require(isinstance(task["source"], str) and bool(task["source"].strip()),
                "Task source must be a nonempty string")
        require(len(task["source"].encode("utf-8")) <= driver.SOURCE_LIMIT,
                "Task source exceeds the synthesis source limit")
        driver.validate_candidates(task["candidates"], driver.MAX_CANDIDATES, "task pool")
        require(isinstance(task["tests"], list) and 1 <= len(task["tests"]) <= MAX_CASES,
                f"Task requires between 1 and {MAX_CASES} tests")
        arity = None
        cases: set[tuple[int, ...]] = set()
        for case in task["tests"]:
            driver.require_keys(case, {"arguments", "expected"}, set(), "test case")
            require(isinstance(case["arguments"], list) and len(case["arguments"]) <= MAX_ARGUMENTS,
                    f"Test arguments must be a list of at most {MAX_ARGUMENTS} natural numbers")
            require(all(type(n) is int and 0 <= n <= MAX_NAT
                        for n in [*case["arguments"], case["expected"]]),
                    f"Test values must be natural integers at most {MAX_NAT}")
            if arity is None:
                arity = len(case["arguments"])
            require(len(case["arguments"]) == arity, "Test arity must be consistent within a task")
            key = tuple(case["arguments"])
            require(key not in cases, "Task contains duplicate test arguments")
            cases.add(key)
    return value


def provider_request(request: dict[str, Any], pool: list[str]) -> dict[str, Any]:
    """The only provider inputs are compiler context, the frozen pool and budgets."""
    validated = driver.validate_request(request)
    if validated is None:
        raise Error("missing_hole", "Task source has no synthesis hole")
    return dict(validated, candidates=list(pool), max_candidates=driver.MAX_CANDIDATES,
                max_new_tokens=96)


def validate_source_shape(source: str, request: dict[str, Any]) -> None:
    """Restrict compiler-validated input to one declaration, without shadowing.

    The lexer uses ASCII identifiers, double quoted strings with backslash
    escapes, and -- line comments. Skip strings/comments before counting
    declaration keywords. The compiler remains responsible for full parsing.
    """
    tokens = re.findall(r'--[^\n]*|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z_0-9\']*',
                        source, flags=re.DOTALL)
    words = [token for token in tokens if not token.startswith(('"', '--'))]
    if words.count("synth") != 1:
        raise Error("multiple_holes", "Task source must contain exactly one synthesis hole")
    declarations = [word for word in words if word in {"def", "axiom", "mu", "mutual"}]
    if declarations != ["def"] or "rec" in words or request["context"].strip():
        raise Error("multiple_declarations", "Diagnostic task source must contain only its nonrecursive synth definition")


def wilson(successes: int, count: int) -> list[float] | None:
    if count == 0:
        return None
    z = 1.959963984540054
    p = successes / count
    denominator = 1 + z * z / count
    center = (p + z * z / (2 * count)) / denominator
    half = z * math.sqrt(p * (1 - p) / count + z * z / (4 * count * count)) / denominator
    return [max(0.0, center - half), min(1.0, center + half)]


def counts(results: list[dict[str, Any]], planned: int) -> dict[str, Any]:
    metrics = ("first_attempt_type_accepted", "type_accepted", "first_attempt_semantic_correct",
               "semantic_correct", "host_disagreement")
    value: dict[str, Any] = {"tasks": planned, "completed": len(results),
                             "pending": planned - len(results),
                             "failures": sum(bool(item["failure"]) for item in results)}
    for key in metrics:
        numerator = sum(bool(item[key]) for item in results)
        value[key] = {"count": numerator, "denominator": planned,
                      "rate": numerator / planned if planned else None,
                      "wilson_95": wilson(numerator, planned)}
    value["attempts"] = sum(len(item["attempts"]) for item in results)
    value["rejections"] = sum(sum(not attempt["type_valid"] for attempt in item["attempts"])
                              for item in results)
    value["cold_process_seconds"] = {
        key: sum(item["cold_process_seconds"][key] for item in results)
        for key in ("provider", "compiler")
    }
    durations = sorted(item["total_seconds"] for item in results)
    value["cold_task_seconds"] = {
        "median": statistics.median(durations) if durations else None,
        "p95": durations[math.ceil(0.95 * len(durations)) - 1] if durations else None,
    }
    return value


def summarize(report: dict[str, Any], tasks: list[dict[str, Any]]) -> dict[str, Any]:
    summary: dict[str, Any] = {}
    for strategy in report["strategies"]:
        completed = [(item, item["strategies"][strategy]) for item in report["results"]
                     if strategy in item["strategies"]]
        summary[strategy] = {"overall": counts([result for _, result in completed], len(tasks))}
        for field in ("family", "module_id"):
            groups = sorted({task[field] for task in tasks})
            summary[strategy]["by_" + field] = {
                name: counts([result for item, result in completed if item[field] == name],
                             sum(task[field] == name for task in tasks))
                for name in groups
            }
    return summary


class ReportFile:
    """Reserve the output exclusively, then replace only the report we created."""

    def __init__(self, path: Path):
        self.path = path.absolute()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        try:
            fd = os.open(self.path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError as exc:
            raise Error("output_exists", "Report already exists; choose a new output path") from exc
        with os.fdopen(fd, "wb") as stream:
            stream.write(b'{"schema_version":1,"complete":false}\n')
            stream.flush()
            os.fsync(stream.fileno())
            status = os.fstat(stream.fileno())
        self.identity = (status.st_dev, status.st_ino)

    def write(self, report: dict[str, Any]) -> None:
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(prefix=".kan-benchmark-", dir=self.path.parent,
                                             delete=False) as stream:
                temporary = Path(stream.name)
                stream.write(driver.canonical_json(report) + b"\n")
                stream.flush()
                os.fsync(stream.fileno())
                status = os.fstat(stream.fileno())
                next_identity = (status.st_dev, status.st_ino)
            previous = self.path.lstat()
            if (previous.st_dev, previous.st_ino) != self.identity:
                raise Error("output_changed", "Report path was replaced externally")
            os.replace(temporary, self.path)
            self.identity = next_identity
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


def empty_result() -> dict[str, Any]:
    return {"first_attempt_type_accepted": False, "type_accepted": False,
            "first_attempt_semantic_correct": False, "semantic_correct": False,
            "host_disagreement": False, "attempts": [], "selected": None,
            "tests": [], "failure": None, "provenance": {}, "provider_metrics": {},
            "cold_process_seconds": {"provider": 0.0, "compiler": 0.0}}


def checked_call(compiler: Path, arguments: list[str], timeout: float,
                 timing: dict[str, float]) -> Any:
    started = time.monotonic()
    try:
        return driver.bounded_process([str(compiler), *arguments], timeout=timeout)
    finally:
        timing["compiler"] += time.monotonic() - started


def compiler_request(compiler: Path, source: Path, timeout: float,
                     timing: dict[str, float]) -> dict[str, Any] | None:
    result = checked_call(compiler, ["synth-request", str(source)], timeout, timing)
    if result.returncode != 0:
        raise Error("request_rejected", driver.diagnostic(result))
    return driver.validate_request(driver.strict_json(result.stdout, "compiler request"))


def rank(request: dict[str, Any], strategy: str, args: argparse.Namespace,
         result: dict[str, Any]) -> list[str]:
    if strategy == "candidate_order":
        result["provenance"] = {"method": "frozen candidate order"}
        return list(request["candidates"])
    if strategy == "deterministic":
        import baseline
        candidates = baseline.rank_candidates(request)
        driver.validate_candidates(candidates, driver.MAX_CANDIDATES, "deterministic ranking")
        if set(candidates) != set(request["candidates"]):
            raise Error("candidate_pool", "Deterministic ranking must preserve the frozen pool")
        result["provenance"] = {"method": "deterministic ranking"}
        return candidates
    started = time.monotonic()
    try:
        process = driver.bounded_process([str(args.provider.resolve())],
            stdin=driver.canonical_json(request) + b"\n", timeout=args.timeout)
    finally:
        result["cold_process_seconds"]["provider"] += time.monotonic() - started
    result["provider_exit_status"] = process.returncode
    response = driver.validate_provider(driver.strict_json(process.stdout, "provider response"),
                                        driver.MAX_CANDIDATES, request["candidates"])
    result["provenance"] = response["provenance"]
    result["provider_metrics"] = response["metrics"]
    if process.returncode != 0:
        raise Error("provider_failed", driver.diagnostic(process))
    return response["candidates"]


def evaluate(task: dict[str, Any], strategy: str, args: argparse.Namespace,
             compiler: Path, work: Path) -> dict[str, Any]:
    result = empty_result()
    started = time.monotonic()
    timing = result["cold_process_seconds"]
    source = work / "source.kan"
    source.write_text(task["source"], encoding="utf-8")
    try:
        request = compiler_request(compiler, source, args.check_timeout, timing)
        if request is None:
            raise Error("missing_hole", "Task source has no synthesis hole")
        validate_source_shape(task["source"], request)
        if re.fullmatch(r"[A-Za-z_][A-Za-z_0-9']*", request["declaration"]) is None:
            raise Error("unsupported_declaration", "Benchmark requires an ASCII declaration name")
        if re.search(r"\bbenchCase[0-9]+\b", task["source"]):
            raise Error("reserved_declaration", "Source uses a reserved benchCase name")
        result["request"] = request
        result["request_sha256"] = driver.sha256(driver.canonical_json(request))
        candidates = rank(provider_request(request, task["candidates"]), strategy, args, result)
        result["ranking"] = candidates
        expanded = None
        for index, candidate in enumerate(candidates):
            candidate_file = work / f"candidate-{index}.txt"
            candidate_file.write_text(candidate, encoding="utf-8")
            output = work / f"expanded-{index}.kan"
            attempt = {"index": index, "candidate_sha256": driver.sha256(candidate.encode("utf-8")),
                       "type_valid": False, "error": None}
            result["attempts"].append(attempt)
            try:
                applied = checked_call(compiler, ["synth-apply", str(source), "--candidate",
                    str(candidate_file), "-o", str(output)], args.check_timeout, timing)
                if applied.returncode != 0:
                    raise Error("candidate_rejected", driver.diagnostic(applied))
                expanded = driver.read_bounded(output, driver.SOURCE_LIMIT, "Expanded source").decode("utf-8")
                attempt["type_valid"] = True
                result["selected"] = {"index": index, "candidate": candidate,
                                      "candidate_sha256": attempt["candidate_sha256"]}
                # Match production selection: no later candidate after apply succeeds.
                break
            except Error as exc:
                attempt["error"] = exc.as_json()
        if expanded is None:
            raise Error("candidates_exhausted", f"All {len(candidates)} candidates failed")
        if compiler_request(compiler, output, args.check_timeout, timing) is not None:
            raise Error("multiple_holes", "Task source must contain exactly one synthesis hole")
        checked = checked_call(compiler, ["check", str(output)], args.check_timeout, timing)
        if checked.returncode != 0:
            raise Error("final_check_rejected", driver.diagnostic(checked))
        result["type_accepted"] = True
        result["first_attempt_type_accepted"] = result["selected"]["index"] == 0
        result["expanded_source"] = expanded
        result["expanded_sha256"] = driver.sha256(expanded.encode("utf-8"))
        test_source = work / "tests.kan"
        declarations = []
        for index, case in enumerate(task["tests"]):
            application = " ".join([request["declaration"], *map(str, case["arguments"])])
            declarations.append(f"def benchCase{index} : Nat := {application}\n")
        test_source.write_text(expanded + "\n" + "".join(declarations), encoding="utf-8")
        checked = checked_call(compiler, ["check", str(test_source)], args.check_timeout, timing)
        if checked.returncode != 0:
            raise Error("test_check_rejected", driver.diagnostic(checked))
        for index, case in enumerate(task["tests"]):
            observed: dict[str, Any] = {}
            for host in args.hosts:
                try:
                    execution = checked_call(compiler, ["run", str(test_source), "--export",
                        f"benchCase{index}", "--host", host], args.check_timeout, timing)
                    if execution.returncode != 0:
                        raise Error("host_failed", driver.diagnostic(execution))
                    text = execution.stdout.decode("utf-8").strip()
                    if re.fullmatch(r"-?[0-9]{1,20}", text) is None:
                        raise Error("host_output", "Host did not return a bounded decimal integer")
                    observed[host] = {"value": int(text), "error": None}
                except Error as exc:
                    observed[host] = {"value": None, "error": exc.as_json()}
            # Compare outcomes only: two hosts that fail in the same way agree,
            # even when their diagnostic text differs.
            outcomes = {driver.canonical_json([item["value"], (item["error"] or {}).get("code")])
                        for item in observed.values()}
            disagreement = len(outcomes) > 1
            passed = all(item["error"] is None and item["value"] == case["expected"]
                         for item in observed.values())
            result["tests"].append(dict(case, hosts=observed, passed=passed,
                                         host_disagreement=disagreement))
        result["host_disagreement"] = any(case["host_disagreement"] for case in result["tests"])
        result["semantic_correct"] = all(case["passed"] for case in result["tests"])
        result["first_attempt_semantic_correct"] = (result["first_attempt_type_accepted"]
                                                       and result["semantic_correct"])
        if not result["semantic_correct"]:
            code = "semantic_mismatch"
            if result["host_disagreement"]:
                code = "host_disagreement"
            elif any(host["error"] is not None for case in result["tests"] for host in case["hosts"].values()):
                code = "host_failed"
            result["failure"] = {"code": code, "message": "Selected candidate did not pass every semantic test"}
    except Error as exc:
        result["failure"] = exc.as_json()
    except (OSError, UnicodeError, ValueError, RecursionError) as exc:
        result["failure"] = {"code": "io_or_encoding", "message": str(exc)[:4096]}
    finally:
        result["total_seconds"] = time.monotonic() - started
    return result


def positive_count(text: str) -> int:
    try:
        count = int(text)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Expected an integer from 1 through 10000") from exc
    if not 1 <= count <= MAX_TASKS:
        raise argparse.ArgumentTypeError("Expected an integer from 1 through 10000")
    return count


def host_list(text: str) -> list[str]:
    hosts = text.split(",")
    if not hosts or len(hosts) != len(set(hosts)) or any(host not in HOSTS for host in hosts):
        raise argparse.ArgumentTypeError("Expected distinct hosts from kernel,node,wasmtime")
    return hosts


def parser() -> argparse.ArgumentParser:
    result = driver.StructuredParser(description=__doc__)
    result.add_argument("--corpus", required=True, type=Path)
    result.add_argument("--compiler", required=True, type=Path)
    result.add_argument("--output", required=True, type=Path)
    result.add_argument("--provider", type=Path)
    result.add_argument("--limit", type=positive_count)
    result.add_argument("--split-manifest", type=Path,
                        help="Frozen corpus hash and module/template split assignments")
    result.add_argument("--split", choices=splits.SPLITS,
                        help="Evaluate this split only; requires --split-manifest")
    result.add_argument("--hosts", type=host_list, default=["kernel"])
    result.add_argument("--timeout", type=driver.positive_seconds, default=60.0)
    result.add_argument("--check-timeout", type=driver.positive_seconds, default=5.0)
    return result


def missing_host_binaries(hosts: list[str]) -> list[str]:
    """Name every requested host whose external binary is absent from PATH."""
    names = [HOST_BINARIES[host] for host in hosts if host in HOST_BINARIES]
    return sorted({name for name in names if shutil.which(name) is None})


def run(args: argparse.Namespace) -> dict[str, Any]:
    missing = missing_host_binaries(args.hosts)
    if missing:
        raise Error("host_unavailable",
                    "Requested host binaries are not on PATH: " + ", ".join(missing))
    corpus_bytes = driver.read_bounded(args.corpus, CORPUS_LIMIT, "Corpus")
    corpus = validate_corpus(driver.strict_json(corpus_bytes, "corpus"))
    if (args.split_manifest is None) != (args.split is None):
        raise Error("invalid_split_selection", "Use --split-manifest and --split together")
    eligible = corpus["tasks"]
    split_record = None
    if args.split_manifest is not None:
        manifest_bytes = driver.read_bounded(args.split_manifest, CORPUS_LIMIT, "Split manifest")
        try:
            manifest = splits.validate_manifest(
                driver.strict_json(manifest_bytes, "split manifest"), corpus,
                driver.sha256(corpus_bytes))
            eligible = splits.select_tasks(corpus, manifest, args.split)
        except splits.SplitError as exc:
            raise Error("invalid_split_manifest", str(exc)) from exc
        assignments = [module for module in manifest["modules"] if module["split"] == args.split]
        split_record = {
            "name": args.split, "manifest_path": str(args.split_manifest.resolve()),
            "manifest_name": manifest["name"], "manifest_sha256": driver.sha256(manifest_bytes),
            "split_unit": manifest["split_unit"], "available_tasks": len(eligible),
            "available_modules": sorted(module["module_id"] for module in assignments),
            "template_groups": sorted({module["template_group"] for module in assignments}),
            "independence": "Assignments are checked; independent authorship and semantic separation are not established",
        }
    compiler = args.compiler.resolve(strict=True)
    compiler_hash = driver.file_sha256(compiler)
    tasks = eligible[:args.limit]
    if split_record is not None:
        split_record.update(selected_tasks=len(tasks), limited=len(tasks) < len(eligible),
                            selected_modules=sorted({task["module_id"] for task in tasks}))
    report: dict[str, Any] = {
        "schema_version": 1, "complete": False, "purpose": "diagnostic",
        "gate": {"status": "unmet", "reason": "Diagnostic corpus; independent 500-task contract is not established"},
        "corpus": {"path": str(args.corpus.resolve()), "name": corpus["name"],
                   "sha256": driver.sha256(corpus_bytes), "available_tasks": len(corpus["tasks"]),
                   "selected_tasks": len(tasks)},
        "split": split_record,
        "compiler": {"path": str(compiler), "sha256": compiler_hash},
        "implementation": {"benchmark_sha256": driver.file_sha256(Path(__file__)),
                           "splits_sha256": driver.file_sha256(Path(splits.__file__)),
                           "driver_sha256": driver.file_sha256(Path(driver.__file__)),
                           "baseline_sha256": driver.file_sha256(Path(__file__).with_name("baseline.py"))},
        "configuration": {"hosts": args.hosts, "provider_timeout": args.timeout,
                          "check_timeout": args.check_timeout, "max_candidates": driver.MAX_CANDIDATES,
                          "max_new_tokens": 96},
        "timing_note": "Fresh processes only; no warm latency or model usefulness claim",
        "confidence_note": "Wilson 95% intervals describe task-level results on correlated developer-authored diagnostic families; they do not establish independent generalization",
        "strategies": ["candidate_order", "deterministic"] + (["provider"] if args.provider else []),
        "provider": None, "results": [], "summary": {}, "failure": None,
    }
    if args.provider:
        provider = args.provider.resolve(strict=True)
        report["provider"] = {"path": str(provider), "sha256": driver.file_sha256(provider)}
    report_file = ReportFile(args.output)
    started = time.monotonic()
    try:
        report["summary"] = summarize(report, tasks)
        report_file.write(report)
        with tempfile.TemporaryDirectory(prefix="kan-benchmark-") as temporary:
            work = Path(temporary)
            for index, task in enumerate(tasks):
                item = {key: task[key] for key in ("id", "family", "module_id")}
                item["source_sha256"] = driver.sha256(task["source"].encode("utf-8"))
                item["pool_sha256"] = driver.sha256(driver.canonical_json(task["candidates"]))
                item["strategies"] = {}
                report["results"].append(item)
                for strategy in report["strategies"]:
                    strategy_work = work / f"task-{index}-{strategy}"
                    strategy_work.mkdir()
                    item["strategies"][strategy] = evaluate(task, strategy, args, compiler, strategy_work)
                    shutil.rmtree(strategy_work)
                    report["summary"] = summarize(report, tasks)
                    report["total_seconds"] = time.monotonic() - started
                    report_file.write(report)
        if driver.file_sha256(compiler) != compiler_hash:
            raise Error("compiler_changed", "Compiler changed during evaluation")
        if args.provider and driver.file_sha256(args.provider.resolve()) != report["provider"]["sha256"]:
            raise Error("provider_changed", "Provider executable changed during evaluation")
        report["complete"] = True
    except KeyboardInterrupt:
        report["failure"] = {"code": "interrupted", "message": "Evaluation interrupted"}
        raise
    except (Error, OSError, UnicodeError, ValueError, RecursionError) as exc:
        report["failure"] = exc.as_json() if isinstance(exc, Error) else {"code": "evaluation_failed", "message": str(exc)}
        raise
    finally:
        report["total_seconds"] = time.monotonic() - started
        report["summary"] = summarize(report, tasks)
        report_file.write(report)
    return report


def main(argv: list[str] | None = None) -> int:
    try:
        args = parser().parse_args(argv)
        report = run(args)
        print(driver.canonical_json({"output": str(args.output.absolute()),
                                     "complete": report["complete"], "gate": report["gate"],
                                     "summary": {strategy: summary["overall"] for strategy, summary
                                                 in report["summary"].items()}}).decode("utf-8"))
        return 0
    except Error as exc:
        print(driver.canonical_json({"error": exc.as_json()}).decode("utf-8"), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    except (OSError, UnicodeError, ValueError, RecursionError) as exc:
        print(driver.canonical_json({"error": {"code": "io_or_encoding", "message": str(exc)}}).decode("utf-8"), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
