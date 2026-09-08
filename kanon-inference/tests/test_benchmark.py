"""Exercise selection semantics, protocol failures, and diagnostic accounting."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location("kan_benchmark_under_test", ROOT / "benchmark.py")
benchmark = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = benchmark
spec.loader.exec_module(benchmark)


FAKE_COMPILER = r'''
import json
from pathlib import Path
import re
import sys

command, path, *rest = sys.argv[1:]
source = Path(path).read_text()
if command == "synth-request":
    if "synth " not in source:
        print("null")
    else:
        print(json.dumps({"protocol_version": 1, "declaration": "target",
            "hint": "Return one.", "expected_type": "Nat", "context": "",
            "allowed_axioms": ["Nat"]}))
elif command == "synth-apply":
    candidate = Path(rest[1]).read_text()
    if candidate not in ["0", "1", "2"]:
        print("candidate type rejected", file=sys.stderr)
        sys.exit(1)
    expanded = source.replace('synth "Return one."', candidate, 1)
    Path(rest[3]).write_text(expanded)
elif command == "check":
    if "BAD_SUFFIX" in source:
        sys.exit(1)
    if "BAD_TESTS" in source and "benchCase0" in source:
        print("generated test declaration rejected", file=sys.stderr)
        sys.exit(1)
elif command == "run":
    value = int(re.search(r"def target : Nat := ([0-9]+)", source).group(1))
    if "FAIL_HOST" in source and rest[-1] == "node":
        print("host trap", file=sys.stderr)
        sys.exit(4)
    if "FAIL_BOTH" in source:
        print("host trap on " + rest[-1], file=sys.stderr)
        sys.exit(4)
    if "DISAGREE" in source and rest[-1] == "node":
        value += 1
    print(value)
else:
    sys.exit(64)
'''


def task(identifier="task1", family="constant", module_id="module1"):
    return {"id": identifier, "family": family, "module_id": module_id,
            "source": 'def target : Nat := synth "Return one."\n',
            "candidates": ["0", "1"], "tests": [{"arguments": [], "expected": 1}]}


def corpus(tasks=None):
    return {"schema_version": 1, "name": "test diagnostic", "purpose": "diagnostic",
            "tasks": tasks if tasks is not None else [task()]}


class BenchmarkTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kan-benchmark-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.compiler = self.executable("compiler", FAKE_COMPILER)
        # The fake compiler needs no external host binary, so these fixtures
        # must not depend on Node or Wasmtime being installed.
        binaries = patch.dict(benchmark.HOST_BINARIES, {}, clear=True)
        binaries.start()
        self.addCleanup(binaries.stop)

    def executable(self, name, body):
        path = self.directory / name
        path.write_text("#!" + sys.executable + "\n" + textwrap.dedent(body))
        path.chmod(0o700)
        return path

    def arguments(self, value=None, provider=None, hosts="kernel", timeout="2"):
        path = self.directory / "corpus.json"
        path.write_text(json.dumps(value if value is not None else corpus()))
        argv = ["--corpus", str(path), "--compiler", str(self.compiler),
                "--output", str(self.directory / "report.json"),
                "--hosts", hosts, "--timeout", timeout]
        if provider:
            argv.extend(["--provider", str(provider)])
        return benchmark.parser().parse_args(argv)

    def run_report(self, value=None, **kwargs):
        args = self.arguments(value, **kwargs)
        report = benchmark.run(args)
        self.assertEqual(report, json.loads(args.output.read_text()))
        return report

    def test_wrong_well_typed_candidate_stops_selection_before_oracle(self):
        report = self.run_report()
        result = report["results"][0]["strategies"]["candidate_order"]
        self.assertTrue(result["type_accepted"])
        self.assertTrue(result["first_attempt_type_accepted"])
        self.assertFalse(result["semantic_correct"])
        self.assertEqual(result["selected"]["candidate"], "0")
        self.assertEqual(len(result["attempts"]), 1)
        self.assertEqual(result["tests"][0]["hosts"]["kernel"]["value"], 0)
        self.assertEqual(result["failure"]["code"], "semantic_mismatch")

    def test_first_attempt_and_first_valid_results_are_distinct(self):
        item = task()
        item["candidates"] = ["ill_typed", "1", "0"]
        report = self.run_report(corpus([item]))
        result = report["results"][0]["strategies"]["candidate_order"]
        self.assertTrue(result["semantic_correct"])
        self.assertFalse(result["first_attempt_semantic_correct"])
        self.assertFalse(result["first_attempt_type_accepted"])
        self.assertEqual(result["selected"]["index"], 1)
        self.assertEqual(len(result["attempts"]), 2)

    def test_provider_only_gets_compiler_request_pool_and_budgets(self):
        provider = self.executable("provider", '''
            import json, sys
            request = json.load(sys.stdin)
            expected = {"protocol_version", "declaration", "hint", "expected_type",
                        "context", "allowed_axioms", "candidates", "max_candidates", "max_new_tokens"}
            assert set(request) == expected
            assert request["max_candidates"] == 8 and request["max_new_tokens"] == 96
            assert "tests" not in request and "expected" not in request
            assert "arguments" not in request and "module_id" not in request
            print(json.dumps({"protocol_version": 1, "candidates": ["1", "0"],
                              "provenance": {"fixture": "oracle-separation"}, "metrics": {}}))
        ''')
        report = self.run_report(provider=provider)
        result = report["results"][0]["strategies"]["provider"]
        self.assertTrue(result["semantic_correct"])
        self.assertEqual(result["provenance"], {"fixture": "oracle-separation"})
        self.assertEqual(report["provider"]["sha256"], benchmark.driver.file_sha256(provider))

    def test_malformed_provider_is_persisted_and_kept_in_denominator(self):
        provider = self.executable("provider", 'print("malformed")')
        report = self.run_report(provider=provider)
        self.assertTrue(report["complete"])
        result = report["results"][0]["strategies"]["provider"]
        self.assertEqual(result["failure"]["code"], "invalid_json")
        summary = report["summary"]["provider"]["overall"]
        self.assertEqual(summary["semantic_correct"]["denominator"], 1)
        self.assertEqual(summary["semantic_correct"]["count"], 0)
        self.assertEqual(summary["failures"], 1)

    def test_provider_timeout_is_persisted(self):
        provider = self.executable("provider", "import time\ntime.sleep(10)")
        report = self.run_report(provider=provider, timeout="0.04")
        result = report["results"][0]["strategies"]["provider"]
        self.assertEqual(result["failure"]["code"], "process_timeout")
        self.assertTrue(report["complete"])

    def test_nonzero_provider_status_is_a_failure_even_with_valid_json(self):
        provider = self.executable("provider", '''
            import json, sys
            print(json.dumps({"protocol_version": 1, "candidates": ["1"],
                              "provenance": {}, "metrics": {}}))
            sys.exit(7)
        ''')
        report = self.run_report(provider=provider)
        result = report["results"][0]["strategies"]["provider"]
        self.assertEqual(result["failure"]["code"], "provider_failed")
        self.assertEqual(result["provider_exit_status"], 7)

    def test_existing_output_is_preserved(self):
        args = self.arguments()
        args.output.write_text("existing report\n")
        with self.assertRaises(benchmark.Error) as raised:
            benchmark.run(args)
        self.assertEqual(raised.exception.code, "output_exists")
        self.assertEqual(args.output.read_text(), "existing report\n")

    def test_per_family_and_module_totals_include_failed_tasks(self):
        second = task("task2", "other", "module2")
        second["candidates"] = ["invalid"]
        report = self.run_report(corpus([task(), second]))
        summary = report["summary"]["candidate_order"]
        self.assertEqual(summary["overall"]["tasks"], 2)
        self.assertEqual(summary["overall"]["failures"], 2)
        self.assertEqual(summary["by_family"]["other"]["type_accepted"]["denominator"], 1)
        self.assertEqual(summary["by_module_id"]["module1"]["type_accepted"]["count"], 1)
        self.assertEqual(report["gate"]["status"], "unmet")

    def test_host_disagreement_is_explicit(self):
        item = task()
        item["candidates"] = ["1"]
        item["source"] += "-- DISAGREE\n"
        report = self.run_report(corpus([item]), hosts="kernel,node")
        result = report["results"][0]["strategies"]["candidate_order"]
        self.assertTrue(result["host_disagreement"])
        self.assertEqual(result["failure"]["code"], "host_disagreement")
        self.assertFalse(result["semantic_correct"])

    def test_second_hole_rejects_task_before_candidate_selection(self):
        item = task()
        item["source"] += 'def second : Nat := synth "Return one."\n'
        report = self.run_report(corpus([item]))
        result = report["results"][0]["strategies"]["candidate_order"]
        self.assertEqual(result["failure"]["code"], "multiple_holes")
        self.assertFalse(result["type_accepted"])
        self.assertEqual(len(result["attempts"]), 0)

    def test_value_and_host_failure_are_a_disagreement(self):
        item = task()
        item["candidates"] = ["1"]
        item["source"] += "-- FAIL_HOST\n"
        report = self.run_report(corpus([item]), hosts="kernel,node")
        result = report["results"][0]["strategies"]["candidate_order"]
        self.assertTrue(result["host_disagreement"])
        self.assertEqual(result["failure"]["code"], "host_disagreement")

    def test_agreeing_hosts_are_not_a_disagreement(self):
        item = task()
        item["candidates"] = ["1"]
        report = self.run_report(corpus([item]), hosts="kernel,node")
        result = report["results"][0]["strategies"]["candidate_order"]
        self.assertFalse(result["host_disagreement"])
        self.assertTrue(result["semantic_correct"])
        self.assertIsNone(result["failure"])
        self.assertEqual(result["tests"][0]["hosts"]["node"]["value"], 1)

    def test_hosts_that_fail_alike_report_host_failed_not_disagreement(self):
        item = task()
        item["candidates"] = ["1"]
        item["source"] += "-- FAIL_BOTH\n"
        report = self.run_report(corpus([item]), hosts="kernel,node")
        result = report["results"][0]["strategies"]["candidate_order"]
        hosts = result["tests"][0]["hosts"]
        self.assertNotEqual(hosts["kernel"]["error"]["message"],
                            hosts["node"]["error"]["message"])
        self.assertEqual(hosts["kernel"]["error"]["code"], "host_failed")
        self.assertFalse(result["host_disagreement"])
        self.assertEqual(result["failure"]["code"], "host_failed")

    def test_missing_host_binary_stops_the_run_before_any_task(self):
        args = self.arguments(hosts="kernel,node")
        with patch.dict(benchmark.HOST_BINARIES, {"node": "kan-absent-host-binary"}):
            with self.assertRaises(benchmark.Error) as raised:
                benchmark.run(args)
        self.assertEqual(raised.exception.code, "host_unavailable")
        self.assertIn("kan-absent-host-binary", raised.exception.as_json()["message"])
        self.assertFalse(args.output.exists())

    def test_expanded_source_that_fails_the_final_check_is_rejected(self):
        item = task()
        item["candidates"] = ["1"]
        item["source"] += "-- BAD_SUFFIX\n"
        report = self.run_report(corpus([item]))
        result = report["results"][0]["strategies"]["candidate_order"]
        self.assertEqual(result["failure"]["code"], "final_check_rejected")
        self.assertFalse(result["type_accepted"])
        self.assertFalse(result["semantic_correct"])

    def test_generated_test_source_that_fails_the_check_is_rejected(self):
        item = task()
        item["candidates"] = ["1"]
        item["source"] += "-- BAD_TESTS\n"
        report = self.run_report(corpus([item]))
        result = report["results"][0]["strategies"]["candidate_order"]
        self.assertEqual(result["failure"]["code"], "test_check_rejected")
        self.assertTrue(result["type_accepted"])
        self.assertEqual(result["tests"], [])
        self.assertFalse(result["semantic_correct"])

    def test_source_keywords_in_strings_comments_and_names_are_not_declarations(self):
        request = {"context": ""}
        benchmark.validate_source_shape(
            'def answer : Nat := synth "def \\\" def mu synth \\\"" -- def suffix : Nat := 7\n', request)
        benchmark.validate_source_shape('def def_name : Nat := synth "Return one."', request)
        with self.assertRaises(benchmark.Error):
            benchmark.validate_source_shape(
                'def answer : Nat := synth "Return one."\ndef answer : Nat := 7', request)

    def test_output_parent_directories_are_created(self):
        args = self.arguments()
        args.output = self.directory / "new" / "nested" / "report.json"
        report = benchmark.run(args)
        self.assertTrue(report["complete"])
        self.assertTrue(args.output.is_file())

    def test_interrupted_evaluation_leaves_an_incomplete_report(self):
        args = self.arguments()
        with patch.object(benchmark, "evaluate", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                benchmark.run(args)
        report = json.loads(args.output.read_text())
        self.assertFalse(report["complete"])
        self.assertEqual(report["failure"]["code"], "interrupted")
        self.assertEqual(report["summary"]["candidate_order"]["overall"]["pending"], 1)

    def test_validation_rejects_ambiguous_metadata_and_unbounded_inputs(self):
        mutations = [
            lambda c: c.update(schema_version=True),
            lambda c: c.update(purpose="acceptance"),
            lambda c: c["tasks"].append(copy.deepcopy(c["tasks"][0])),
            lambda c: c["tasks"][0].update(module_id=""),
            lambda c: c["tasks"][0].update(candidates=["1", "1"]),
            lambda c: c["tasks"][0]["tests"][0].update(expected=True),
            lambda c: c["tasks"][0]["tests"][0].update(arguments=[-1]),
            lambda c: c["tasks"][0]["tests"][0].update(expected=benchmark.MAX_NAT + 1),
            lambda c: c["tasks"][0].update(tests=[]),
        ]
        for mutate in mutations:
            value = corpus()
            mutate(value)
            with self.subTest(value=value), self.assertRaises(benchmark.Error):
                benchmark.validate_corpus(value)

    def test_corpus_accepts_500_tasks_without_claiming_gate_success(self):
        value = corpus([task(f"task{index}") for index in range(500)])
        self.assertEqual(len(benchmark.validate_corpus(value)["tasks"]), 500)

    def test_wilson_interval_includes_uncertainty_at_extremes(self):
        low, high = benchmark.wilson(0, 32)
        self.assertAlmostEqual(low, 0)
        self.assertGreater(high, 0)
        low, high = benchmark.wilson(32, 32)
        self.assertLess(low, 1)
        self.assertAlmostEqual(high, 1)

    def test_wilson_interval_width_is_pinned_to_95_percent(self):
        self.assertIsNone(benchmark.wilson(0, 0))
        low, high = benchmark.wilson(8, 32)
        self.assertAlmostEqual(low, 0.132524, places=6)
        self.assertAlmostEqual(high, 0.421066, places=6)
        self.assertLess(low, 0.25)
        self.assertLess(0.25, high)
        larger_low, larger_high = benchmark.wilson(80, 320)
        self.assertLess(larger_high - larger_low, high - low)


class RealCompilerTests(unittest.TestCase):
    def compiler(self):
        compiler_text = os.environ.get("KANON_TEST_COMPILER")
        compiler = (Path(compiler_text) if compiler_text else
                    ROOT.parent / "kanon-synth" / "_build" / "default" / "bin" / "kanon.exe")
        if not compiler.is_file():
            self.skipTest("Set KANON_TEST_COMPILER or build the sibling compiler for this integration test")
        return compiler

    def test_redefinition_cannot_make_a_wrong_candidate_pass(self):
        compiler = self.compiler()
        with tempfile.TemporaryDirectory(prefix="kan-benchmark-shadow-") as temporary:
            directory = Path(temporary)
            item = task()
            item["source"] = 'def answer : Nat := synth "Return seven."\ndef answer : Nat := 7\n'
            item["candidates"] = ["3"]
            item["tests"] = [{"arguments": [], "expected": 7}]
            corpus_path = directory / "corpus.json"
            corpus_path.write_text(json.dumps(corpus([item])))
            args = benchmark.parser().parse_args(["--compiler", str(compiler), "--corpus",
                str(corpus_path), "--output", str(directory / "report.json")])
            report = benchmark.run(args)
            for result in report["results"][0]["strategies"].values():
                self.assertFalse(result["semantic_correct"])
                self.assertEqual(result["failure"]["code"], "multiple_declarations")

    def test_real_compiler_preserves_semantic_failure_after_type_acceptance(self):
        compiler = self.compiler()
        with tempfile.TemporaryDirectory(prefix="kan-benchmark-real-") as temporary:
            directory = Path(temporary)
            item = task()
            item["source"] = 'def target : (earlier : Nat) -> (later : Nat) -> Nat := synth "Return the later argument."\n'
            item["candidates"] = ["fun (earlier : Nat) (later : Nat) => earlier",
                                  "fun (earlier : Nat) (later : Nat) => later"]
            item["tests"] = [{"arguments": [17, 42], "expected": 42}]
            corpus_path = directory / "corpus.json"
            corpus_path.write_text(json.dumps(corpus([item])))
            args = benchmark.parser().parse_args(["--compiler", str(compiler), "--corpus",
                str(corpus_path), "--output", str(directory / "report.json")])
            report = benchmark.run(args)
            result = report["results"][0]["strategies"]["candidate_order"]
            self.assertTrue(result["type_accepted"], result)
            self.assertFalse(result["semantic_correct"])
            self.assertEqual(result["tests"][0]["hosts"]["kernel"]["value"], 17)
            self.assertEqual(len(result["attempts"]), 1)


if __name__ == "__main__":
    unittest.main()
