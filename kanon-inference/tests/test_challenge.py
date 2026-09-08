"""Pin the authored challenge fixture and validate its finite behavior examples.

These are corpus quality checks. Intended indices stay in this test module and
are never supplied to a model or used to select a benchmark proposal.
"""

from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location("kan_challenge_benchmark", ROOT / "benchmark.py")
benchmark = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = benchmark
spec.loader.exec_module(benchmark)

CORPUS_PATH = ROOT / "benchmarks" / "challenge-v1.json"
MANIFEST_PATH = ROOT / "benchmarks" / "challenge-v1.splits.json"
CORPUS_SHA256 = "9210f281dc8109c1bbbcc4e1b5fa5b4f9e19b418f6722cb7a736fbd3c9d5d7d8"
INTENDED_INDEX = {
    "tariff_3_2": 0,
    "tariff_5_1": 1,
    "tariff_2_4": 2,
    "tariff_4_3": 3,
    "capacity_5": 0,
    "capacity_9": 1,
    "capacity_3": 2,
    "capacity_7": 3,
    "gap_1": 0,
    "gap_2": 1,
    "gap_3": 2,
    "gap_4": 3,
    "refill_3_2": 0,
    "refill_2_5": 1,
    "refill_5_3": 2,
    "refill_4_6": 3,
    "interior_1": 0,
    "interior_2": 1,
    "interior_3": 2,
    "interior_4": 3,
    "clamp_2_6": 0,
    "clamp_3_8": 1,
    "clamp_5_9": 2,
    "clamp_4_10": 3,
}


def corpus():
    return json.loads(CORPUS_PATH.read_text(encoding="utf-8"))


def split_of(task):
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    return {item["module_id"]: item["split"] for item in manifest["modules"]}[task["module_id"]]


class ChallengeFixtureTests(unittest.TestCase):
    def test_corpus_and_manifest_pin_exact_frozen_bytes(self):
        digest = hashlib.sha256(CORPUS_PATH.read_bytes()).hexdigest()
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        self.assertEqual(digest, CORPUS_SHA256)
        self.assertEqual(manifest["corpus_sha256"], CORPUS_SHA256)
        self.assertEqual(manifest["schema_version"], 1)
        self.assertEqual(manifest["name"], "challenge-v1-splits")
        self.assertEqual(
            manifest["split_unit"], "independent_module_before_synthetic_augmentation")
        value = benchmark.validate_corpus(corpus())
        self.assertEqual(value["purpose"], "diagnostic")
        self.assertEqual(len(value["tasks"]), 24)
        self.assertEqual(sum(len(task["tests"]) for task in value["tasks"]), 120)

    def test_module_and_template_groups_stay_in_one_split(self):
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        assignments = manifest["modules"]
        modules = {item["module_id"]: item for item in assignments}
        self.assertEqual(len(assignments), 12)
        self.assertEqual(len(modules), len(assignments))
        self.assertEqual(set(modules), {task["module_id"] for task in corpus()["tasks"]})
        templates = {}
        for item in assignments:
            self.assertIn(item["split"], {"train", "validation", "test"})
            templates.setdefault(item["template_group"], set()).add(item["split"])
        self.assertEqual(len(templates), 6)
        self.assertTrue(all(len(splits) == 1 for splits in templates.values()))
        split_counts = Counter(modules[task["module_id"]]["split"] for task in corpus()["tasks"])
        self.assertEqual(split_counts, {"train": 8, "validation": 8, "test": 8})
        self.assertEqual(Counter(item["split"] for item in assignments),
                         {"train": 4, "validation": 4, "test": 4})
        for task in corpus()["tasks"]:
            with self.subTest(task=task["id"]):
                self.assertEqual(modules[task["module_id"]]["template_group"], task["family"])

    def test_zero_boundaries_and_intended_positions_are_balanced(self):
        tasks = corpus()["tasks"]
        self.assertEqual(set(INTENDED_INDEX), {task["id"] for task in tasks})
        self.assertEqual(Counter(INTENDED_INDEX.values()), {0: 6, 1: 6, 2: 6, 3: 6})
        for task in tasks:
            with self.subTest(task=task["id"]):
                self.assertEqual(len(task["candidates"]), 4)
                self.assertTrue(any(all(n == 0 for n in case["arguments"])
                                    for case in task["tests"]))
                self.assertIn("let ", task["candidates"][INTENDED_INDEX[task["id"]]])
        positions = {name: Counter() for name in ("train", "validation", "test")}
        for task in tasks:
            positions[split_of(task)][INTENDED_INDEX[task["id"]]] += 1
        for name, counts in positions.items():
            with self.subTest(split=name):
                self.assertEqual(counts, {0: 2, 1: 2, 2: 2, 3: 2})

    def test_no_surface_cue_selects_the_intended_candidate(self):
        unique_let = Counter()
        unique_longest = Counter()
        for task in corpus()["tasks"]:
            intended = INTENDED_INDEX[task["id"]]
            bound = [index for index, candidate in enumerate(task["candidates"])
                     if "let " in candidate]
            lengths = [len(candidate) for candidate in task["candidates"]]
            longest = [index for index, size in enumerate(lengths) if size == max(lengths)]
            with self.subTest(task=task["id"]):
                self.assertGreaterEqual(len(bound), 2)
                self.assertEqual(len(set(task["candidates"])), 4)
            unique_let[split_of(task)] += bound == [intended]
            unique_longest[split_of(task)] += longest == [intended]
        for name in ("train", "validation", "test"):
            with self.subTest(split=name):
                self.assertLessEqual(unique_let[name], 2)
                self.assertLessEqual(unique_longest[name], 2)

    def test_candidate_pools_and_intended_terms_differ_between_tasks(self):
        tasks = corpus()["tasks"]
        pools = [tuple(sorted(task["candidates"])) for task in tasks]
        intended = [task["candidates"][INTENDED_INDEX[task["id"]]] for task in tasks]
        self.assertEqual(len(set(pools)), len(tasks))
        self.assertEqual(len(set(intended)), len(tasks))

    def test_unchanged_development_baseline_preserves_challenge_pool_order(self):
        import baseline

        for task in corpus()["tasks"]:
            declaration, hint_json = task["source"].split(" := synth ", 1)
            expected_type = declaration.split(" : ", 1)[1]
            request = {
                "hint": json.loads(hint_json),
                "expected_type": expected_type,
                "candidates": task["candidates"],
            }
            with self.subTest(task=task["id"]):
                self.assertEqual(baseline.rank_candidates(request), task["candidates"])


class ChallengeRealCompilerTests(unittest.TestCase):
    def compiler(self):
        configured = os.environ.get("KANON_TEST_COMPILER")
        compiler = (Path(configured) if configured else
                    ROOT.parent / "kanon-synth" / "_build" / "default" / "bin" / "kanon.exe")
        if configured:
            self.assertTrue(compiler.is_file(), "KANON_TEST_COMPILER must name a compiler file")
        elif not compiler.is_file():
            self.skipTest("Set KANON_TEST_COMPILER or build the compiler for challenge validation")
        return compiler.resolve()

    def test_every_pool_has_one_passing_candidate_and_three_semantic_decoys(self):
        compiler = self.compiler()
        args = SimpleNamespace(check_timeout=10.0, hosts=["kernel"])
        with tempfile.TemporaryDirectory(prefix="kan-challenge-real-") as temporary:
            root = Path(temporary)
            for task in corpus()["tasks"]:
                for index, candidate in enumerate(task["candidates"]):
                    with self.subTest(task=task["id"], candidate=index):
                        work = root / task["id"] / str(index)
                        work.mkdir(parents=True)
                        isolated = dict(task, candidates=[candidate])
                        result = benchmark.evaluate(
                            isolated, "candidate_order", args, compiler, work)
                        self.assertTrue(result["type_accepted"], result["failure"])
                        self.assertEqual(len(result["tests"]), len(task["tests"]))
                        expected = index == INTENDED_INDEX[task["id"]]
                        self.assertEqual(result["semantic_correct"], expected,
                                         {"task": task["id"], "index": index,
                                          "failure": result["failure"], "tests": result["tests"]})
                        if expected:
                            self.assertIsNone(result["failure"])
                        else:
                            self.assertEqual(result["failure"]["code"], "semantic_mismatch")


if __name__ == "__main__":
    unittest.main()
