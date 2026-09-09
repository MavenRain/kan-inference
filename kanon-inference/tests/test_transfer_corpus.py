"""Pin the transfer development corpus and check every candidate with Kanon.

Intended indices are quality-check data confined to this test module. They are
never provided to a model or used to rank proposals during a benchmark run.
"""

from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from types import SimpleNamespace
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location("kan_transfer_benchmark", ROOT / "benchmark.py")
benchmark = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = benchmark
spec.loader.exec_module(benchmark)

CORPUS_PATH = ROOT / "benchmarks" / "transfer-v1.json"
AUTHORSHIP_PATH = ROOT / "benchmarks" / "transfer-v1.authorship.json"
MANIFEST_PATH = ROOT / "benchmarks" / "transfer-v1.splits.json"
CORPUS_SHA256 = "fca112bd8b1c887a36849cf92668129ff48e05bf10f0ea8a38852ebaa86f7956"
INTENDED_INDEX = {
    "transfer_reject_cartons": 0,
    "transfer_reject_labels": 1,
    "transfer_reject_cards": 2,
    "transfer_reject_badges": 3,
    "transfer_ordered_reviewers": 0,
    "transfer_ordered_medals": 1,
    "transfer_ordered_greetings": 2,
    "transfer_ordered_chairs": 3,
    "transfer_fanout_topics": 0,
    "transfer_fanout_tree": 1,
    "transfer_fanout_archives": 2,
    "transfer_fanout_endpoints": 3,
    "transfer_pairwise_isolated": 0,
    "transfer_pairwise_merged": 1,
    "transfer_pairwise_repeated": 2,
    "transfer_pairwise_forward": 3,
}
FAMILIES = {
    "group_rejection", "ordered_selection", "message_fanout", "pairwise_analysis",
}


def corpus():
    return json.loads(CORPUS_PATH.read_text(encoding="utf-8"))


class TransferFixtureTests(unittest.TestCase):
    def test_frozen_corpus_hash_and_strict_shape(self):
        self.assertEqual(hashlib.sha256(CORPUS_PATH.read_bytes()).hexdigest(), CORPUS_SHA256)
        value = benchmark.validate_corpus(corpus())
        self.assertEqual(set(value), {"schema_version", "name", "purpose", "tasks"})
        self.assertEqual(value["schema_version"], 1)
        self.assertEqual(value["name"], "transfer-v1")
        self.assertEqual(value["purpose"], "diagnostic")
        tasks = value["tasks"]
        self.assertEqual(len(tasks), 16)
        self.assertEqual({task["family"] for task in tasks}, FAMILIES)
        self.assertEqual(Counter(task["family"] for task in tasks),
                         {family: 4 for family in FAMILIES})
        self.assertEqual(len({task["module_id"] for task in tasks}), len(tasks))
        for task in tasks:
            with self.subTest(task=task["id"]):
                self.assertEqual(set(task),
                                 {"id", "family", "module_id", "source", "candidates", "tests"})
                self.assertEqual(len(task["tests"]), 6)
                arity = len(task["tests"][0]["arguments"])
                self.assertIn(arity, (2, 3))
                self.assertEqual(task["source"].count("synth "), 1)
                self.assertEqual(task["source"].count(" -> "), arity)
                self.assertTrue(task["source"].endswith("\n"))
                self.assertEqual(len(re.findall(r"\([xyz] : Nat\)", task["source"])), arity)
                self.assertTrue(any(0 in case["arguments"] for case in task["tests"]))
                self.assertEqual(len({tuple(case["arguments"]) for case in task["tests"]}), 6)
                for case in task["tests"]:
                    self.assertEqual(set(case), {"arguments", "expected"})
                    self.assertEqual(len(case["arguments"]), arity)
                    self.assertTrue(all(type(n) is int and n >= 0 for n in case["arguments"]))
                    self.assertIs(type(case["expected"]), int)
                    self.assertGreaterEqual(case["expected"], 0)
        self.assertEqual(sum(len(task["tests"]) for task in tasks), 96)

    def test_authorship_discloses_development_scope_and_pins_corpus(self):
        value = json.loads(AUTHORSHIP_PATH.read_text(encoding="utf-8"))
        self.assertEqual(set(value),
                         {"schema_version", "corpus_sha256", "author_role", "process",
                          "exposure_disclosure"})
        self.assertEqual(value["schema_version"], 1)
        self.assertEqual(value["corpus_sha256"], CORPUS_SHA256)
        for key in ("author_role", "process", "exposure_disclosure"):
            self.assertIsInstance(value[key], str)
            self.assertTrue(value[key].strip())
        self.assertIn("Same-project AI collaborator", value["author_role"])
        self.assertIn("not a sealed test", value["exposure_disclosure"])
        self.assertIn("before any benchmark model run", value["process"])
        for family in FAMILIES:
            self.assertIn(family, value["process"])

    def test_all_module_and_family_assignments_are_development_train(self):
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        self.assertEqual(manifest["schema_version"], 1)
        self.assertEqual(manifest["name"], "transfer-v1-development")
        self.assertEqual(manifest["corpus_sha256"], CORPUS_SHA256)
        self.assertEqual(manifest["split_unit"],
                         "independent_module_before_synthetic_augmentation")
        assignments = manifest["modules"]
        by_module = {item["module_id"]: item for item in assignments}
        self.assertEqual(len(assignments), 16)
        self.assertEqual(len(by_module), len(assignments))
        self.assertEqual(set(by_module), {task["module_id"] for task in corpus()["tasks"]})
        self.assertEqual({item["split"] for item in assignments}, {"train"})
        for task in corpus()["tasks"]:
            with self.subTest(task=task["id"]):
                self.assertEqual(by_module[task["module_id"]]["template_group"], task["family"])

    def test_positions_are_balanced_and_pools_and_answers_are_distinct(self):
        tasks = corpus()["tasks"]
        self.assertEqual(set(INTENDED_INDEX), {task["id"] for task in tasks})
        self.assertEqual(Counter(INTENDED_INDEX.values()), {0: 4, 1: 4, 2: 4, 3: 4})
        for family in FAMILIES:
            self.assertEqual(Counter(INTENDED_INDEX[task["id"]] for task in tasks
                                     if task["family"] == family),
                             {0: 1, 1: 1, 2: 1, 3: 1})
        pools = [tuple(sorted(task["candidates"])) for task in tasks]
        intended = [task["candidates"][INTENDED_INDEX[task["id"]]] for task in tasks]
        self.assertEqual(len(set(pools)), len(tasks))
        self.assertEqual(len(set(intended)), len(tasks))

    def test_no_unique_let_or_longest_intended_candidate(self):
        for task in corpus()["tasks"]:
            with self.subTest(task=task["id"]):
                candidates = task["candidates"]
                intended = INTENDED_INDEX[task["id"]]
                self.assertEqual(len(candidates), 4)
                self.assertEqual(len(set(candidates)), 4)
                let_indices = [i for i, candidate in enumerate(candidates) if "let " in candidate]
                self.assertNotEqual(let_indices, [intended])
                lengths = [len(candidate) for candidate in candidates]
                longest = [i for i, length in enumerate(lengths) if length == max(lengths)]
                self.assertNotEqual(longest, [intended])


class TransferRealCompilerTests(unittest.TestCase):
    def compiler(self):
        configured = os.environ.get("KANON_TEST_COMPILER")
        compiler = (Path(configured) if configured else
                    ROOT.parent / "kanon-synth" / "_build" / "default" / "bin" / "kanon.exe")
        if configured:
            self.assertTrue(compiler.is_file(), "KANON_TEST_COMPILER must name a compiler file")
        elif not compiler.is_file() and os.environ.get("KANON_SKIP_COMPILER_TESTS") == "1":
            self.skipTest("KANON_SKIP_COMPILER_TESTS=1 skips transfer corpus compiler validation")
        elif not compiler.is_file():
            self.fail("Build the compiler (make build) or set KANON_TEST_COMPILER; "
                      "set KANON_SKIP_COMPILER_TESTS=1 to skip")
        return compiler.resolve()

    def test_every_candidate_compiles_and_exactly_one_per_task_matches_all_examples(self):
        compiler = self.compiler()
        check_timeout = float(os.environ.get("KANON_TEST_CHECK_TIMEOUT", "10"))
        self.assertGreater(check_timeout, 0, "KANON_TEST_CHECK_TIMEOUT must be positive")
        args = SimpleNamespace(check_timeout=check_timeout, hosts=["kernel"])
        with tempfile.TemporaryDirectory(prefix="kan-transfer-real-") as temporary:
            root = Path(temporary)
            for task in corpus()["tasks"]:
                passing = []
                for index, candidate in enumerate(task["candidates"]):
                    with self.subTest(task=task["id"], candidate=index):
                        work = root / task["id"] / str(index)
                        work.mkdir(parents=True)
                        result = benchmark.evaluate(dict(task, candidates=[candidate]),
                                                    "candidate_order", args, compiler, work)
                        self.assertTrue(result["type_accepted"],
                                        {"failure": result["failure"], "attempts": result["attempts"]})
                        self.assertEqual(len(result["tests"]), len(task["tests"]))
                        expected = index == INTENDED_INDEX[task["id"]]
                        self.assertEqual(result["semantic_correct"], expected,
                                         {"task": task["id"], "index": index,
                                          "failure": result["failure"], "tests": result["tests"]})
                        if result["semantic_correct"]:
                            passing.append(index)
                            self.assertIsNone(result["failure"])
                        else:
                            self.assertEqual(result["failure"]["code"], "semantic_mismatch")
                self.assertEqual(passing, [INTENDED_INDEX[task["id"]]], task["id"])


if __name__ == "__main__":
    unittest.main()
