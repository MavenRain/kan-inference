#!/usr/bin/env python3
"""Boundary tests. Fixture proposers provide no evidence of model capability.

Set KANON_TEST_COMPILER to an already built compiler for real kernel rejection
tests. This suite never builds the compiler and never downloads a model.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import synth


# This deliberately small fake compiler isolates orchestration invariants.
# Logical soundness is tested against the real compiler below, not this fixture.
FIXTURE_COMPILER = r'''
import json
import pathlib
import re
import sys
import time

command, source = sys.argv[1:3]
text = pathlib.Path(source).read_text()
pattern = re.compile(r'def (\w+) : ([^\n]+?) := synth "([^"\n]*)"')
hole = pattern.search(text)
if command == "synth-request":
    if "BAD_SOURCE" in text:
        print("invalid source", file=sys.stderr)
        sys.exit(1)
    request = None if hole is None else {
        "protocol_version": 1, "declaration": hole[1], "expected_type": hole[2],
        "hint": hole[3], "context": text[:hole.start()], "allowed_axioms": ["Nat"]}
    print(json.dumps(request))
elif command == "synth-apply":
    candidate = pathlib.Path(sys.argv[4]).read_text()
    if candidate == "HANG":
        time.sleep(60)
    if candidate not in ("0", "1", "2", "42"):
        print("fixture candidate rejected", file=sys.stderr)
        sys.exit(1)
    replacement = "def " + hole[1] + " : " + hole[2] + " := " + candidate
    pathlib.Path(sys.argv[6]).write_text(text[:hole.start()] + replacement + text[hole.end():])
elif command == "check":
    if hole is not None or "FAIL_FINAL" in text:
        print("fixture final check rejected", file=sys.stderr)
        sys.exit(1)
else:
    sys.exit(2)
'''


def executable(path: Path, body: str) -> Path:
    path.write_text(f"#!{sys.executable}\n" + body, encoding="utf-8")
    path.chmod(0o700)
    return path


def fixture_provider(path: Path, candidates: list[str]) -> Path:
    """A fixed untrusted response, not an embedded model or capability test."""
    response = {
        "protocol_version": 1, "candidates": candidates,
        "provenance": {"kind": "fixture", "model_capability_evidence": False},
        "metrics": {"fixture": True},
    }
    return executable(path, "import json, sys\njson.load(sys.stdin)\nprint(" + repr(json.dumps(response)) + ")\n")


class ProcessBoundaryTests(unittest.TestCase):
    def run_python(self, script: str, **kwargs: object) -> synth.ProcessResult:
        return synth.bounded_process([sys.executable, "-c", script], **kwargs)

    def test_drains_both_streams(self) -> None:
        result = self.run_python(
            "import os\nfor _ in range(16):\n os.write(1,b'a'*8192)\n os.write(2,b'b'*8192)",
            timeout=5,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"a" * 131072)
        self.assertEqual(result.stderr, b"b" * 131072)

    def test_combined_output_limit(self) -> None:
        with self.assertRaises(synth.SynthesisError) as raised:
            self.run_python(
                "import os\nwhile True:\n os.write(1,b'a'*32768)\n os.write(2,b'b'*32768)",
                timeout=3, output_limit=100000,
            )
        self.assertEqual(raised.exception.code, "process_output_limit")

    def test_hard_deadline_covers_nonreading_stdin(self) -> None:
        started = time.monotonic()
        with self.assertRaises(synth.SynthesisError) as raised:
            self.run_python("import time; time.sleep(60)", stdin=b"x" * 1000000, timeout=0.2)
        self.assertEqual(raised.exception.code, "process_timeout")
        self.assertLess(time.monotonic() - started, 2)

    @unittest.skipUnless(hasattr(os, "fork"), "Requires POSIX process groups")
    def test_deadline_covers_descendant_held_pipes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pidfile = Path(directory) / "pid"
            heartbeat = Path(directory) / "heartbeat"
            script = (
                "import os, time\n"
                "pid = os.fork()\n"
                "if pid:\n"
                f" open({str(pidfile)!r}, 'w').write(str(pid))\n"
                " os._exit(0)\n"
                "while True:\n"
                f" open({str(heartbeat)!r}, 'w').write(str(time.monotonic_ns()))\n"
                " time.sleep(0.02)\n"
            )
            started = time.monotonic()
            try:
                with self.assertRaises(synth.SynthesisError) as raised:
                    self.run_python(script, timeout=2)
                self.assertEqual(raised.exception.code, "process_timeout")
                self.assertLess(time.monotonic() - started, 4)
                self.assertTrue(pidfile.exists())
                # Observable child activity avoids relying on platform ps access
                # or whether the operating system has reaped the killed orphan.
                time.sleep(0.05)
                last_heartbeat = heartbeat.read_bytes()
                time.sleep(0.15)
                self.assertEqual(heartbeat.read_bytes(), last_heartbeat)
            finally:
                if pidfile.exists():
                    try:
                        os.kill(int(pidfile.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_invalid_json_rejected(self) -> None:
        for raw in (b'{"x":1,"x":2}', b'{"x":{"y":1,"y":2}}', b'NaN', b'Infinity', b'1e9999', b'{', b'"\\ud800"'):
            with self.subTest(raw=raw), self.assertRaises(synth.SynthesisError):
                synth.strict_json(raw, "fixture response")

    def test_malformed_provider_schema_rejected(self) -> None:
        valid = {"protocol_version": 1, "candidates": ["1"], "provenance": {}, "metrics": {}}
        invalid = [
            dict(valid, protocol_version=True), dict(valid, candidates=[]),
            dict(valid, candidates=["1", "1"]), dict(valid, candidates=[1]),
            dict(valid, candidates=[" " ]), dict(valid, candidates=["x" * (synth.CANDIDATE_LIMIT + 1)]),
            dict(valid, provenance=[]), dict(valid, metrics="fast"),
            dict(valid, candidates=[str(index) for index in range(9)]), dict(valid, unrecognized=True),
        ]
        for response in invalid:
            with self.subTest(response=str(response)[:100]), self.assertRaises(synth.SynthesisError):
                synth.validate_provider(response, 8, None)


class OrchestrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.compiler = executable(self.root / "fixture-compiler", FIXTURE_COMPILER)
        self.provider = fixture_provider(self.root / "fixture-provider", ["1"])
        self.source = self.root / "source.kan"
        self.source.write_text('def one : Nat := synth "return one"\n')
        self.output = self.root / "resolved.kan"

    def args(self, *extra: str, output: Path | None = None) -> list[str]:
        args = ["--compiler", str(self.compiler), str(self.source), "-o", str(output or self.output),
                "--check-timeout", "10", "--timeout", "10"]
        if "--replay" not in extra:
            args += ["--provider", str(self.provider)]
        return args + list(extra)

    def invoke(self, *extra: str, output: Path | None = None) -> tuple[int, dict]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = synth.main(self.args(*extra, output=output))
        payload = json.loads(out.getvalue() if code == 0 else err.getvalue())
        return code, payload

    def receipt(self, output: Path | None = None) -> Path:
        return Path(str(output or self.output) + ".synth.json")

    def assert_no_outputs(self, output: Path | None = None) -> None:
        self.assertFalse((output or self.output).exists())
        self.assertFalse(self.receipt(output).exists())

    def successful_receipt(self) -> dict:
        code, result = self.invoke()
        self.assertEqual(code, 0, result)
        return json.loads(self.receipt().read_text())

    def rewrite_receipt(self, value: dict) -> Path:
        modified = self.root / "modified.json"
        modified.write_text(json.dumps(value))
        return modified

    def test_wrong_candidate_then_valid(self) -> None:
        fixture_provider(self.provider, ["wrong", "1"])
        receipt = self.successful_receipt()
        self.assertEqual(self.output.read_text(), "def one : Nat := 1\n")
        self.assertEqual(receipt["expansions"][0]["candidate"], "1")
        self.assertEqual(len(receipt["expansions"][0]["rejected"]), 1)
        self.assertEqual(receipt["allowed_axioms"], ["Nat"])
        self.assertEqual(receipt["output_sha256"], synth.sha256(self.output.read_bytes()))
        self.assertIn("synth", self.source.read_text())

    def test_all_candidates_invalid_has_no_artifacts(self) -> None:
        fixture_provider(self.provider, ["wrong", "also wrong"])
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "candidates_exhausted")
        self.assert_no_outputs()

    def test_checker_timeout_rejects_candidate_then_continues(self) -> None:
        fixture_provider(self.provider, ["HANG", "1"])
        code, result = self.invoke("--check-timeout", "3")
        self.assertEqual(code, 0, result)
        receipt = json.loads(self.receipt().read_text())
        self.assertEqual(receipt["expansions"][0]["rejected"][0]["error"]["code"], "process_timeout")

    def test_multiple_holes_freeze_updated_context(self) -> None:
        self.source.write_text('def one : Nat := synth "return one"\ndef two : Nat := synth "return two"\n')
        receipt = self.successful_receipt()
        self.assertEqual(len(receipt["expansions"]), 2)
        self.assertEqual(receipt["expansions"][0]["request"]["context"], "")
        self.assertIn("def one : Nat := 1", receipt["expansions"][1]["request"]["context"])
        self.assertNotIn("synth", self.output.read_text())

    def test_replay_does_not_need_executable_provider(self) -> None:
        self.successful_receipt()
        self.provider.unlink()
        replay_output = self.root / "replay.kan"
        with mock.patch.object(synth, "DEFAULT_PROVIDER", self.root / "missing-provider"):
            code, result = self.invoke("--replay", str(self.receipt()), output=replay_output)
        self.assertEqual(code, 0, result)
        self.assertTrue(result["replay"])
        self.assertEqual(self.output.read_bytes(), replay_output.read_bytes())

    def test_replay_changed_source_goal_rejected(self) -> None:
        self.successful_receipt()
        self.source.write_text('def one : Type 0 := synth "return one"\n')
        replay_output = self.root / "replay.kan"
        code, result = self.invoke("--replay", str(self.receipt()), output=replay_output)
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "stale_source")
        self.assert_no_outputs(replay_output)

    def test_replay_request_goal_tamper_with_updated_digest_rejected(self) -> None:
        receipt = self.successful_receipt()
        entry = receipt["expansions"][0]
        entry["request"]["expected_type"] = "Type 0"
        entry["request_sha256"] = synth.sha256(synth.canonical_json(entry["request"]))
        replay_output = self.root / "replay.kan"
        code, result = self.invoke("--replay", str(self.rewrite_receipt(receipt)), output=replay_output)
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "stale_request")
        self.assert_no_outputs(replay_output)

    def test_tampered_candidate_digest_rejected(self) -> None:
        receipt = self.successful_receipt()
        receipt["expansions"][0]["candidate"] = "2"
        replay_output = self.root / "replay.kan"
        code, result = self.invoke("--replay", str(self.rewrite_receipt(receipt)), output=replay_output)
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "invalid_receipt")
        self.assert_no_outputs(replay_output)

    def test_tampered_candidate_with_updated_digest_is_rechecked(self) -> None:
        receipt = self.successful_receipt()
        entry = receipt["expansions"][0]
        entry["candidate"] = "wrong"
        entry["candidate_sha256"] = synth.sha256(b"wrong")
        replay_output = self.root / "replay.kan"
        code, result = self.invoke("--replay", str(self.rewrite_receipt(receipt)), output=replay_output)
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "replay_rejected")
        self.assert_no_outputs(replay_output)

    def test_stale_compiler_hash_rejected(self) -> None:
        self.successful_receipt()
        self.compiler.write_text(self.compiler.read_text() + "\n# changed compiler\n")
        replay_output = self.root / "replay.kan"
        code, result = self.invoke("--replay", str(self.receipt()), output=replay_output)
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "stale_compiler")
        self.assert_no_outputs(replay_output)

    def test_extra_and_missing_replay_expansions_rejected(self) -> None:
        receipt = self.successful_receipt()
        for name, entries in (("missing", []), ("extra", receipt["expansions"] * 2)):
            modified = dict(receipt, expansions=entries)
            replay_output = self.root / f"{name}.kan"
            code, result = self.invoke("--replay", str(self.rewrite_receipt(modified)), output=replay_output)
            self.assertEqual(code, 1, result)
            self.assertEqual(result["error"]["code"], "invalid_receipt")
            self.assert_no_outputs(replay_output)

    def test_replay_policy_tamper_rejected(self) -> None:
        receipt = self.successful_receipt()
        receipt["allowed_axioms"] = ["Nat", "False"]
        replay_output = self.root / "replay.kan"
        code, result = self.invoke("--replay", str(self.rewrite_receipt(receipt)), output=replay_output)
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "axiom_policy")
        self.assert_no_outputs(replay_output)

    def test_final_output_digest_tamper_rejected(self) -> None:
        receipt = self.successful_receipt()
        receipt["output_sha256"] = "0" * 64
        replay_output = self.root / "replay.kan"
        code, result = self.invoke("--replay", str(self.rewrite_receipt(receipt)), output=replay_output)
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "replay_output")
        self.assert_no_outputs(replay_output)

    def test_no_holes_has_no_provider_call(self) -> None:
        self.source.write_text("def one : Nat := 1\n")
        self.provider.unlink()
        receipt = self.successful_receipt()
        self.assertEqual(receipt["expansions"], [])
        self.assertEqual(self.output.read_bytes(), self.source.read_bytes())

    def test_existing_output_preserved(self) -> None:
        self.output.write_text("preserve this")
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "output_exists")
        self.assertEqual(self.output.read_text(), "preserve this")
        self.assertFalse(self.receipt().exists())

    def test_existing_receipt_preserved(self) -> None:
        self.receipt().write_text("preserve receipt")
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "output_exists")
        self.assertFalse(self.output.exists())
        self.assertEqual(self.receipt().read_text(), "preserve receipt")

    def test_output_cannot_overwrite_source(self) -> None:
        original = self.source.read_bytes()
        code, result = self.invoke(output=self.source)
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "output_exists")
        self.assertEqual(self.source.read_bytes(), original)

    def test_publication_race_cleans_receipt(self) -> None:
        original_link = os.link
        calls = 0

        def racing_link(source: Path, destination: Path) -> None:
            nonlocal calls
            calls += 1
            if calls == 2:
                Path(destination).write_text("concurrent writer")
            original_link(source, destination)

        with mock.patch.object(synth.os, "link", side_effect=racing_link):
            code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "output_exists")
        self.assertEqual(self.output.read_text(), "concurrent writer")
        self.assertFalse(self.receipt().exists())
        self.assertFalse(list(self.root.glob(".kanon-synth-*")))

    def test_provider_malformed_and_duplicate_json_leave_no_outputs(self) -> None:
        for raw in ('{', '{"protocol_version":1,"protocol_version":1}', 'NaN'):
            executable(self.provider, f"print({raw!r})\n")
            code, result = self.invoke()
            self.assertEqual(code, 1)
            self.assertEqual(result["error"]["code"], "invalid_json")
            self.assert_no_outputs()

    def test_provider_structured_failure(self) -> None:
        executable(self.provider, 'import sys\nprint(\'{"error":{"code":"model_missing","message":"fixture model unavailable"}}\')\nsys.exit(1)\n')
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "provider_error")
        self.assert_no_outputs()

    def test_provider_request_is_one_newline_terminated_json_object(self) -> None:
        executable(self.provider, '''import json, sys
wire = sys.stdin.buffer.read()
if not wire.endswith(b"\\n") or wire.count(b"\\n") != 1:
    print(json.dumps({"error": {"code": "invalid_request", "message": "newline required"}}))
    sys.exit(1)
request = json.loads(wire)
assert request["max_candidates"] == 8
assert request["max_new_tokens"] == 96
assert request["allowed_axioms"] == ["Nat"]
print(json.dumps({"protocol_version": 1, "candidates": ["1"], "provenance": {"kind": "fixture"}, "metrics": {}}))
''')
        code, result = self.invoke()
        self.assertEqual(code, 0, result)
        self.assertEqual(self.output.read_text(), "def one : Nat := 1\n")

    def test_candidate_pool_membership_enforced(self) -> None:
        pool = self.root / "pool.json"
        pool.write_text('["2", "42"]')
        code, result = self.invoke("--candidate-pool", str(pool))
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "candidate_pool")
        self.assert_no_outputs()
        fixture_provider(self.provider, ["42"])
        code, result = self.invoke("--candidate-pool", str(pool), "--max-candidates", "1")
        self.assertEqual(code, 0, result)

    def test_final_fresh_check_required(self) -> None:
        self.source.write_text(self.source.read_text() + "FAIL_FINAL\n")
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "final_check_rejected")
        self.assert_no_outputs()

    def test_hole_limit_leaves_no_outputs(self) -> None:
        self.source.write_text(self.source.read_text() + 'def two : Nat := synth "return two"\n')
        code, result = self.invoke("--max-holes", "1")
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "hole_limit")
        self.assert_no_outputs()

    def test_source_limit_leaves_no_outputs(self) -> None:
        self.source.write_bytes(b" " * (synth.SOURCE_LIMIT + 1))
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "file_limit")
        self.assert_no_outputs()

    def test_provider_crash_without_stdout_reports_its_stderr(self) -> None:
        executable(
            self.provider,
            'import sys\nsys.stderr.write("Traceback: ModuleNotFoundError: onnxruntime\\n")\nsys.exit(3)\n',
        )
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "provider_failed")
        self.assertIn("onnxruntime", result["error"]["message"])
        self.assert_no_outputs()

    def test_provider_failure_with_unparsable_stdout_reports_its_stderr(self) -> None:
        executable(
            self.provider,
            'import sys\nsys.stdout.write("segmentation fault\\n")\n'
            'sys.stderr.write("provider loader failed\\n")\nsys.exit(4)\n',
        )
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "provider_failed")
        self.assertIn("provider loader failed", result["error"]["message"])
        self.assert_no_outputs()

    def test_provider_deeply_nested_json_rejected(self) -> None:
        executable(self.provider, 'print("[" * 100 + "]" * 100)\n')
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "invalid_json")
        self.assertIn("nesting", result["error"]["message"])
        self.assert_no_outputs()

    def test_compiler_replaced_during_the_run_rejected(self) -> None:
        executable(
            self.compiler,
            FIXTURE_COMPILER
            + '\nif command == "check":\n'
            + '    running = pathlib.Path(sys.argv[0])\n'
            + '    running.write_text(running.read_text() + "# replaced compiler\\n")\n',
        )
        code, result = self.invoke()
        self.assertEqual(code, 1, result)
        self.assertEqual(result["error"]["code"], "compiler_changed")
        self.assert_no_outputs()

    def test_non_utf8_source_rejected(self) -> None:
        self.source.write_bytes(b'def one : Nat := synth "\xff"\n')
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "invalid_source")
        self.assert_no_outputs()

    def test_oversized_receipt_leaves_no_outputs(self) -> None:
        with mock.patch.object(synth, "RECEIPT_LIMIT", 16):
            code, result = self.invoke()
        self.assertEqual(code, 1, result)
        self.assertEqual(result["error"]["code"], "receipt_limit")
        self.assert_no_outputs()

    def test_receipt_expansion_count_bound_enforced(self) -> None:
        receipt = self.successful_receipt()
        modified = dict(receipt, expansions=receipt["expansions"] * (synth.MAX_HOLES + 1))
        replay_output = self.root / "expansions.kan"
        code, result = self.invoke("--replay", str(self.rewrite_receipt(modified)), output=replay_output)
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "invalid_receipt")
        self.assertIn("expansions must be a bounded list", result["error"]["message"])
        self.assert_no_outputs(replay_output)

    def test_receipt_rejected_list_bound_enforced(self) -> None:
        receipt = self.successful_receipt()
        entry = dict(
            receipt["expansions"][0],
            rejected=[
                {"candidate_sha256": synth.sha256(str(index).encode("utf-8")),
                 "error": {"code": "candidate_rejected", "message": "fixture"}}
                for index in range(synth.MAX_CANDIDATES + 1)
            ],
        )
        modified = dict(receipt, expansions=[entry])
        replay_output = self.root / "rejected.kan"
        code, result = self.invoke("--replay", str(self.rewrite_receipt(modified)), output=replay_output)
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "invalid_receipt")
        self.assertIn("rejected candidates must be a bounded list", result["error"]["message"])
        self.assert_no_outputs(replay_output)

    def test_receipt_timing_values_validated(self) -> None:
        for index, timing in enumerate(
            ({"total_seconds": -1.0, "provider_seconds": 0.0, "checking_seconds": 0.0},
             {"total_seconds": "fast", "provider_seconds": 0.0, "checking_seconds": 0.0})
        ):
            receipt = self.successful_receipt() if index == 0 else json.loads(self.receipt().read_text())
            modified = dict(receipt, timing=timing)
            replay_output = self.root / f"timing-{index}.kan"
            code, result = self.invoke(
                "--replay", str(self.rewrite_receipt(modified)), output=replay_output
            )
            self.assertEqual(code, 1)
            self.assertEqual(result["error"]["code"], "invalid_receipt")
            self.assertIn("Timing values", result["error"]["message"])
            self.assert_no_outputs(replay_output)

    def test_output_exists_precheck_runs_before_the_provider(self) -> None:
        self.output.write_text("preserve this")
        self.provider.unlink()
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["error"]["code"], "output_exists")
        self.assertEqual(self.output.read_text(), "preserve this")
        self.assertFalse(self.receipt().exists())

    def test_candidate_pool_is_sent_to_the_provider(self) -> None:
        pool = self.root / "pool.json"
        pool.write_text('["42", "1"]')
        executable(self.provider, '''import json, sys
request = json.loads(sys.stdin.buffer.read())
if request.get("candidates") != ["42", "1"]:
    sys.stderr.write("frozen pool missing from the request\\n")
    sys.exit(7)
print(json.dumps({"protocol_version": 1, "candidates": ["1"], "provenance": {"kind": "fixture"}, "metrics": {}}))
''')
        code, result = self.invoke("--candidate-pool", str(pool))
        self.assertEqual(code, 0, result)
        receipt = json.loads(self.receipt().read_text())
        self.assertIn(receipt["expansions"][0]["candidate"], ["42", "1"])

    def test_bad_arguments_are_structured(self) -> None:
        for extra in (("--timeout", "nan"), ("--max-candidates", "9"), ("--max-holes", "0")):
            code, result = self.invoke(*extra)
            self.assertEqual(code, 1)
            self.assertEqual(result["error"]["code"], "arguments")


@unittest.skipUnless(os.environ.get("KANON_TEST_COMPILER"), "Set KANON_TEST_COMPILER to run real compiler tests")
class RealCompilerBoundaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.compiler = Path(os.environ["KANON_TEST_COMPILER"]).resolve()
        self.source = self.root / "source.kan"
        self.source.write_text('def main : Nat := synth "return forty-two"\n')
        self.provider = self.root / "fixture-provider"
        self.output = self.root / "resolved.kan"

    def invoke(self, candidates: list[str]) -> tuple[int, dict]:
        fixture_provider(self.provider, candidates)
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = synth.main([
                "--compiler", str(self.compiler), str(self.source), "-o", str(self.output),
                "--provider", str(self.provider), "--check-timeout", "5",
            ])
        return code, json.loads(out.getvalue() if code == 0 else err.getvalue())

    def test_real_compiler_rejects_injection_and_wrong_type_then_accepts(self) -> None:
        code, result = self.invoke([
            "Type 0", "42\naxiom unsound : Nat", "42\ndef injected : Nat := 0",
            'synth "recursive request"', "42",
        ])
        self.assertEqual(code, 0, result)
        receipt = json.loads(Path(str(self.output) + ".synth.json").read_text())
        self.assertEqual(receipt["expansions"][0]["candidate"], "42")
        self.assertEqual(len(receipt["expansions"][0]["rejected"]), 4)
        self.assertNotIn("unsound", self.output.read_text())
        self.assertNotIn("injected", self.output.read_text())
        checked = synth.bounded_process([str(self.compiler), "check", str(self.output)], timeout=5)
        self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_real_compiler_all_injections_leave_no_outputs(self) -> None:
        code, result = self.invoke(["42\naxiom unsound : Nat", 'synth "recursive request"'])
        self.assertEqual(code, 1, result)
        self.assertEqual(result["error"]["code"], "candidates_exhausted")
        self.assertFalse(self.output.exists())
        self.assertFalse(Path(str(self.output) + ".synth.json").exists())

    def test_real_compiler_rejects_invalid_utf8_hint_before_protocol(self) -> None:
        self.source.write_text('def main : Nat := synth "\\255"\n')
        requested = synth.bounded_process([str(self.compiler), "synth-request", str(self.source)], timeout=5)
        self.assertNotEqual(requested.returncode, 0)
        self.assertEqual(requested.stdout, b"")
        self.assertTrue(requested.stderr)
        code, result = self.invoke(["42"])
        self.assertEqual(code, 1, result)
        self.assertFalse(self.output.exists())

    def test_real_compiler_unicode_hint_roundtrips(self) -> None:
        hint = "Return 42: λ ∀ 日本語"
        self.source.write_text(f'def main : Nat := synth "{hint}"\n', encoding="utf-8")
        requested = synth.bounded_process([str(self.compiler), "synth-request", str(self.source)], timeout=5)
        self.assertEqual(requested.returncode, 0, requested.stderr)
        self.assertEqual(synth.strict_json(requested.stdout, "compiler request")["hint"], hint)


if __name__ == "__main__":
    unittest.main()
