#!/usr/bin/env python3
"""Materialize bounded, independently checked synthesis and replay its receipt.

The provider is an untrusted local proposer. Only the compiler's synth-apply
operation can replace a hole, and a fresh complete check precedes publication.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from typing import Any


PROTOCOL_VERSION = 1
ALLOWED_AXIOMS = ["Nat"]
SOURCE_LIMIT = 256 * 1024
CANDIDATE_LIMIT = 16 * 1024
CHILD_OUTPUT_LIMIT = 1024 * 1024
RECEIPT_LIMIT = 4 * 1024 * 1024
MAX_CANDIDATES = 8
MAX_HOLES = 8
DEFAULT_PROVIDER = Path(__file__).resolve().parents[2] / "kanon-inference" / "provider"


class SynthesisError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message

    def as_json(self) -> dict[str, str]:
        return {"code": self.code, "message": self.message}


@dataclass(frozen=True)
class ProcessResult:
    returncode: int
    stdout: bytes
    stderr: bytes
    seconds: float


def bounded_process(
    argv: list[str], *, stdin: bytes = b"", timeout: float,
    output_limit: int = CHILD_OUTPUT_LIMIT,
) -> ProcessResult:
    """Drain both pipes and enforce one deadline over the entire process group.

    Nonblocking stdin prevents a child that never reads its request from
    bypassing the deadline. Descendant-held pipes remain covered after the
    direct child exits. The process group is killed on every exit path so an
    otherwise successful child cannot leave a background worker running.
    """
    started = time.monotonic()
    try:
        child = subprocess.Popen(
            argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=True,
        )
    except OSError as exc:
        raise SynthesisError("process_start", f"Cannot start {argv[0]}: {exc}") from exc
    selector = selectors.DefaultSelector()
    output = {"stdout": bytearray(), "stderr": bytearray()}
    sent = 0
    collected = 0
    try:
        for stream, name in ((child.stdout, "stdout"), (child.stderr, "stderr")):
            assert stream is not None
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, name)
        assert child.stdin is not None
        if stdin:
            os.set_blocking(child.stdin.fileno(), False)
            selector.register(child.stdin, selectors.EVENT_WRITE, "stdin")
        else:
            child.stdin.close()
        while selector.get_map() or child.poll() is None:
            remaining = timeout - (time.monotonic() - started)
            if remaining <= 0:
                raise SynthesisError("process_timeout", f"Worker exceeded {timeout:g} seconds")
            for key, _ in selector.select(min(remaining, 0.05)):
                stream = key.fileobj
                if key.data == "stdin":
                    try:
                        sent += os.write(stream.fileno(), stdin[sent:sent + 65536])
                    except BrokenPipeError:
                        sent = len(stdin)
                    except BlockingIOError:
                        continue
                    if sent == len(stdin):
                        selector.unregister(stream)
                        stream.close()
                else:
                    try:
                        chunk = os.read(stream.fileno(), 65536)
                    except BlockingIOError:
                        continue
                    if not chunk:
                        selector.unregister(stream)
                        stream.close()
                        continue
                    collected += len(chunk)
                    if collected > output_limit:
                        raise SynthesisError(
                            "process_output_limit", f"Worker exceeded {output_limit} output bytes"
                        )
                    output[key.data].extend(chunk)
        return ProcessResult(
            child.wait(), bytes(output["stdout"]), bytes(output["stderr"]),
            time.monotonic() - started,
        )
    finally:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        selector.close()
        for stream in (child.stdin, child.stdout, child.stderr):
            if stream is not None:
                stream.close()
        child.wait()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def strict_json(data: bytes, label: str) -> Any:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            if key in result:
                raise ValueError(f"Duplicate key: {key}")
            result[key] = value
        return result

    def constant(value: str) -> Any:
        raise ValueError(f"Nonfinite JSON value: {value}")

    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=pairs, parse_constant=constant)
        pending = [(value, 0)]
        while pending:
            node, depth = pending.pop()
            if depth > 64:
                raise ValueError("JSON nesting exceeds 64 levels")
            if isinstance(node, dict):
                pending.extend((key, depth + 1) for key in node)
                pending.extend((item, depth + 1) for item in node.values())
            elif isinstance(node, list):
                pending.extend((item, depth + 1) for item in node)
            elif isinstance(node, str):
                node.encode("utf-8")
            elif isinstance(node, float) and not math.isfinite(node):
                raise ValueError("Nonfinite JSON number")
        return value
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise SynthesisError("invalid_json", f"Invalid {label}: {exc}") from exc


def read_bounded(path: Path, limit: int, label: str) -> bytes:
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise SynthesisError("file_limit", f"{label} exceeds {limit} bytes")
    return data


def require_keys(value: Any, required: set[str], optional: set[str], label: str) -> None:
    if not isinstance(value, dict) or not required <= value.keys() or value.keys() - required - optional:
        raise SynthesisError("invalid_protocol", f"Malformed {label} fields")


def require_version(value: dict[str, Any], label: str) -> None:
    if type(value.get("protocol_version")) is not int or value["protocol_version"] != PROTOCOL_VERSION:
        raise SynthesisError("invalid_protocol", f"Unsupported {label} protocol version")


def validate_request(value: Any) -> dict[str, Any] | None:
    if value is None:
        return None
    require_keys(value, {"protocol_version", "declaration", "hint", "expected_type", "context", "allowed_axioms"}, set(), "compiler request")
    require_version(value, "compiler request")
    for key in ("declaration", "hint", "expected_type", "context"):
        if not isinstance(value[key], str):
            raise SynthesisError("invalid_protocol", f"Compiler request {key} must be a string")
    if not value["declaration"] or not value["expected_type"]:
        raise SynthesisError("invalid_protocol", "Compiler request has an empty declaration or expected type")
    if value["allowed_axioms"] != ALLOWED_AXIOMS:
        raise SynthesisError("axiom_policy", "Compiler request has an unsupported axiom policy")
    return value


def validate_candidates(value: Any, limit: int, label: str) -> list[str]:
    if not isinstance(value, list) or not 1 <= len(value) <= limit:
        raise SynthesisError("invalid_protocol", f"{label} requires between 1 and {limit} candidates")
    seen: set[str] = set()
    for candidate in value:
        if not isinstance(candidate, str) or not candidate.strip():
            raise SynthesisError("invalid_protocol", f"{label} candidates must be nonempty strings")
        if len(candidate.encode("utf-8")) > CANDIDATE_LIMIT:
            raise SynthesisError("candidate_limit", f"Candidate exceeds {CANDIDATE_LIMIT} bytes")
        if candidate in seen:
            raise SynthesisError("invalid_protocol", f"{label} contains duplicate candidates")
        seen.add(candidate)
    return value


def validate_provider(value: Any, limit: int, pool: list[str] | None) -> dict[str, Any]:
    if isinstance(value, dict) and "error" in value:
        require_keys(value, {"error"}, {"protocol_version"}, "provider failure")
        if "protocol_version" in value:
            require_version(value, "provider failure")
        require_keys(value["error"], {"code", "message"}, set(), "provider error")
        if not all(isinstance(value["error"][key], str) and value["error"][key] for key in ("code", "message")):
            raise SynthesisError("invalid_protocol", "Provider error code and message must be nonempty strings")
        raise SynthesisError("provider_error", f"{value['error']['code']}: {value['error']['message']}")
    require_keys(value, {"protocol_version", "candidates", "provenance", "metrics"}, set(), "provider response")
    require_version(value, "provider response")
    candidates = validate_candidates(value["candidates"], limit, "provider response")
    if pool is not None and any(candidate not in pool for candidate in candidates):
        raise SynthesisError("candidate_pool", "Provider returned a candidate outside the frozen pool")
    if not isinstance(value["provenance"], dict) or not isinstance(value["metrics"], dict):
        raise SynthesisError("invalid_protocol", "Provider provenance and metrics must be objects")
    return value


def diagnostic(result: ProcessResult) -> str:
    message = (result.stderr or result.stdout).decode("utf-8", errors="replace").strip()
    return message[:4096] or f"Worker exited with status {result.returncode}"


def validate_receipt(value: Any, source_digest: str, compiler_digest: str) -> dict[str, Any]:
    require_keys(value, {"protocol_version", "source_sha256", "compiler_sha256", "output_sha256", "allowed_axioms", "expansions", "timing"}, set(), "receipt")
    require_version(value, "receipt")
    for key in ("source_sha256", "compiler_sha256", "output_sha256"):
        digest = value[key]
        if not isinstance(digest, str) or len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
            raise SynthesisError("invalid_receipt", f"Invalid {key}")
    if value["source_sha256"] != source_digest:
        raise SynthesisError("stale_source", "Receipt source digest does not match the source")
    if value["compiler_sha256"] != compiler_digest:
        raise SynthesisError("stale_compiler", "Receipt compiler digest does not match the compiler")
    if value["allowed_axioms"] != ALLOWED_AXIOMS:
        raise SynthesisError("axiom_policy", "Receipt has an unsupported axiom policy")
    if not isinstance(value["expansions"], list) or len(value["expansions"]) > MAX_HOLES:
        raise SynthesisError("invalid_receipt", "Receipt expansions must be a bounded list")
    validate_timing(value["timing"])
    for entry in value["expansions"]:
        require_keys(entry, {"request", "request_sha256", "candidate", "candidate_sha256", "provenance", "metrics", "rejected"}, set(), "receipt expansion")
        request = validate_request(entry["request"])
        if request is None or sha256(canonical_json(request)) != entry["request_sha256"]:
            raise SynthesisError("invalid_receipt", "Receipt request digest does not match its request")
        validate_candidates([entry["candidate"]], 1, "receipt expansion")
        if sha256(entry["candidate"].encode("utf-8")) != entry["candidate_sha256"]:
            raise SynthesisError("invalid_receipt", "Receipt candidate digest does not match its candidate")
        if not isinstance(entry["provenance"], dict) or not isinstance(entry["metrics"], dict):
            raise SynthesisError("invalid_receipt", "Receipt provenance and metrics must be objects")
        if not isinstance(entry["rejected"], list) or len(entry["rejected"]) >= MAX_CANDIDATES:
            raise SynthesisError("invalid_receipt", "Receipt rejected candidates must be a bounded list")
        for rejected in entry["rejected"]:
            require_keys(rejected, {"candidate_sha256", "error"}, set(), "rejected candidate")
            require_keys(rejected["error"], {"code", "message"}, set(), "rejected candidate error")
            if not all(isinstance(rejected["error"][key], str) for key in ("code", "message")):
                raise SynthesisError("invalid_receipt", "Rejected candidate error fields must be strings")
            digest = rejected["candidate_sha256"]
            if not isinstance(digest, str) or len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
                raise SynthesisError("invalid_receipt", "Invalid rejected candidate digest")
    return value


def validate_timing(value: Any) -> None:
    require_keys(value, {"total_seconds", "provider_seconds", "checking_seconds"}, set(), "timing")
    if any(type(item) not in (int, float) or (type(item) is float and not math.isfinite(item)) or item < 0 for item in value.values()):
        raise SynthesisError("invalid_receipt", "Timing values must be finite nonnegative numbers")


def publish(output: Path, data: bytes, receipt: bytes) -> None:
    """Use same-directory hard links to atomically create each file without clobbering.

    The receipt is published first and rolled back if output publication fails.
    A process crash between the links can leave a receipt alone, never unchecked
    source. The two names are not a filesystem-wide transaction.
    """
    receipt_path = Path(str(output) + ".synth.json")
    stages: list[Path] = []
    receipt_published = False
    complete = False
    try:
        for payload in (receipt, data):
            with tempfile.NamedTemporaryFile(prefix=".kanon-synth-", dir=output.parent, delete=False) as stream:
                stages.append(Path(stream.name))
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
        os.link(stages[0], receipt_path)
        receipt_published = True
        os.link(stages[1], output)
        complete = True
    except FileExistsError as exc:
        raise SynthesisError("output_exists", "Output or receipt already exists; choose a new output path") from exc
    finally:
        if receipt_published and not complete:
            try:
                if receipt_path.lstat().st_ino == stages[0].stat().st_ino:
                    receipt_path.unlink()
            except FileNotFoundError:
                pass
        for stage in stages:
            stage.unlink(missing_ok=True)


def positive_seconds(value: str) -> float:
    try:
        seconds = float(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Expected positive finite seconds") from exc
    if not math.isfinite(seconds) or seconds <= 0:
        raise argparse.ArgumentTypeError("Expected positive finite seconds")
    return seconds


def bounded_count(value: str) -> int:
    try:
        count = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Expected an integer from 1 through 8") from exc
    if not 1 <= count <= 8:
        raise argparse.ArgumentTypeError("Expected an integer from 1 through 8")
    return count


class StructuredParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise SynthesisError("arguments", message)


def parser() -> argparse.ArgumentParser:
    result = StructuredParser(description=__doc__)
    result.add_argument("--compiler", required=True, type=Path)
    result.add_argument("source", type=Path)
    result.add_argument("-o", "--output", required=True, type=Path)
    provider = result.add_mutually_exclusive_group()
    provider.add_argument("--provider", type=Path, default=DEFAULT_PROVIDER)
    provider.add_argument("--replay", type=Path)
    result.add_argument("--timeout", type=positive_seconds, default=30.0)
    result.add_argument("--check-timeout", type=positive_seconds, default=5.0)
    result.add_argument("--max-candidates", type=bounded_count, default=MAX_CANDIDATES)
    result.add_argument("--max-holes", type=bounded_count, default=MAX_HOLES)
    result.add_argument("--candidate-pool", type=Path)
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    started = time.monotonic()
    compiler = args.compiler.resolve(strict=True)
    source = args.source.resolve(strict=True)
    output = args.output.absolute()
    receipt_path = Path(str(output) + ".synth.json")
    if os.path.lexists(output) or os.path.lexists(receipt_path):
        raise SynthesisError("output_exists", "Output or receipt already exists; choose a new output path")
    source_bytes = read_bounded(source, SOURCE_LIMIT, "Source")
    try:
        source_bytes.decode("utf-8")
    except UnicodeError as exc:
        raise SynthesisError("invalid_source", "Source must be UTF-8") from exc
    source_digest = sha256(source_bytes)
    compiler_digest = file_sha256(compiler)
    replay = None
    if args.replay is not None:
        if args.candidate_pool is not None:
            raise SynthesisError("arguments", "Replay cannot use a candidate pool")
        replay = validate_receipt(
            strict_json(read_bounded(args.replay, RECEIPT_LIMIT, "Receipt"), "receipt"),
            source_digest, compiler_digest,
        )
    pool = None
    if args.candidate_pool is not None:
        pool = validate_candidates(
            strict_json(read_bounded(args.candidate_pool, CHILD_OUTPUT_LIMIT, "Candidate pool"), "candidate pool"),
            MAX_CANDIDATES, "candidate pool",
        )
    expansions: list[dict[str, Any]] = []
    timing = {"total_seconds": 0.0, "provider_seconds": 0.0, "checking_seconds": 0.0}

    def compiler_call(arguments: list[str]) -> ProcessResult:
        call_started = time.monotonic()
        try:
            return bounded_process([str(compiler), *arguments], timeout=args.check_timeout)
        finally:
            timing["checking_seconds"] += time.monotonic() - call_started

    with tempfile.TemporaryDirectory(prefix="kanon-synth-") as directory:
        work = Path(directory)
        current = work / "source-0.kan"
        current.write_bytes(source_bytes)
        while True:
            requested = compiler_call(["synth-request", str(current)])
            if requested.returncode != 0:
                raise SynthesisError("request_rejected", diagnostic(requested))
            request = validate_request(strict_json(requested.stdout, "compiler request"))
            if request is None:
                break
            hole = len(expansions)
            if hole >= args.max_holes:
                raise SynthesisError("hole_limit", f"Source exceeds {args.max_holes} synthesis holes")
            request_digest = sha256(canonical_json(request))
            if replay is not None:
                if hole >= len(replay["expansions"]):
                    raise SynthesisError("invalid_receipt", "Receipt is missing an expansion")
                entry = replay["expansions"][hole]
                if entry["request_sha256"] != request_digest or canonical_json(entry["request"]) != canonical_json(request):
                    raise SynthesisError("stale_request", "Receipt request does not match the current frozen context and goal")
                candidates = [entry["candidate"]]
                provenance, metrics = entry["provenance"], entry["metrics"]
                rejected = entry["rejected"]
            else:
                provider_request = dict(request, max_candidates=args.max_candidates, max_new_tokens=96)
                if pool is not None:
                    provider_request["candidates"] = pool
                call_started = time.monotonic()
                try:
                    proposed = bounded_process(
                        [str(args.provider.absolute())], stdin=canonical_json(provider_request) + b"\n", timeout=args.timeout
                    )
                finally:
                    timing["provider_seconds"] += time.monotonic() - call_started
                # A provider that failed without a document to parse is reported
                # with its own diagnostic, never as a parser message.
                if proposed.returncode != 0 and not proposed.stdout.strip():
                    raise SynthesisError("provider_failed", diagnostic(proposed))
                # Parse structured provider errors even when the process exits nonzero.
                try:
                    document = strict_json(proposed.stdout, "provider response")
                except SynthesisError as exc:
                    if proposed.returncode == 0:
                        raise
                    raise SynthesisError(
                        "provider_failed", f"{diagnostic(proposed)}: {exc.message}"
                    ) from exc
                response = validate_provider(document, args.max_candidates, pool)
                if proposed.returncode != 0:
                    raise SynthesisError("provider_failed", diagnostic(proposed))
                candidates = response["candidates"]
                provenance, metrics = response["provenance"], response["metrics"]
                rejected = []
            accepted = None
            for index, candidate in enumerate(candidates):
                candidate_file = work / f"candidate-{hole}-{index}.txt"
                candidate_file.write_text(candidate, encoding="utf-8")
                expanded = work / f"source-{hole + 1}-try-{index}.kan"
                try:
                    checked = compiler_call([
                        "synth-apply", str(current), "--candidate", str(candidate_file), "-o", str(expanded)
                    ])
                    if checked.returncode != 0:
                        raise SynthesisError("candidate_rejected", diagnostic(checked))
                    expanded_bytes = read_bounded(expanded, SOURCE_LIMIT, "Expanded source")
                    expanded_bytes.decode("utf-8")
                    accepted = candidate
                    current = expanded
                    break
                except SynthesisError as exc:
                    if replay is not None:
                        raise SynthesisError("replay_rejected", exc.message) from exc
                    rejected.append({"candidate_sha256": sha256(candidate.encode("utf-8")), "error": exc.as_json()})
            if accepted is None:
                raise SynthesisError("candidates_exhausted", f"All {len(candidates)} candidates failed for {request['declaration']}")
            expansions.append({
                "request": request, "request_sha256": request_digest,
                "candidate": accepted, "candidate_sha256": sha256(accepted.encode("utf-8")),
                "provenance": provenance, "metrics": metrics, "rejected": rejected,
            })
        if replay is not None and len(expansions) != len(replay["expansions"]):
            raise SynthesisError("invalid_receipt", "Receipt has extra expansions")
        final_check = compiler_call(["check", str(current)])
        if final_check.returncode != 0:
            raise SynthesisError("final_check_rejected", diagnostic(final_check))
        final_bytes = read_bounded(current, SOURCE_LIMIT, "Expanded source")
        output_digest = sha256(final_bytes)
        if replay is not None and output_digest != replay["output_sha256"]:
            raise SynthesisError("replay_output", "Replayed source digest does not match the receipt")
        if file_sha256(compiler) != compiler_digest:
            raise SynthesisError("compiler_changed", "Compiler changed while synthesis was running")
        timing["total_seconds"] = time.monotonic() - started
        receipt = {
            "protocol_version": PROTOCOL_VERSION, "source_sha256": source_digest,
            "compiler_sha256": compiler_digest, "output_sha256": output_digest,
            "allowed_axioms": ALLOWED_AXIOMS, "expansions": expansions, "timing": timing,
        }
        receipt_bytes = canonical_json(receipt) + b"\n"
        if len(receipt_bytes) > RECEIPT_LIMIT:
            raise SynthesisError("receipt_limit", f"Receipt exceeds {RECEIPT_LIMIT} bytes")
        publish(output, final_bytes, receipt_bytes)
    return {
        "protocol_version": PROTOCOL_VERSION, "output": str(output), "receipt": str(receipt_path),
        "expansions": len(expansions), "replay": replay is not None, "timing": timing,
    }


def main(argv: list[str] | None = None) -> int:
    try:
        result = run(parser().parse_args(argv))
        print(canonical_json(result).decode("utf-8"))
        return 0
    except SynthesisError as exc:
        print(json.dumps({"error": exc.as_json()}, ensure_ascii=True), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print(json.dumps({"error": {"code": "interrupted", "message": "Synthesis interrupted"}}), file=sys.stderr)
        return 130
    except (OSError, UnicodeError, ValueError, RecursionError) as exc:
        print(json.dumps({"error": {"code": "io_or_encoding", "message": str(exc)}}, ensure_ascii=True), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
