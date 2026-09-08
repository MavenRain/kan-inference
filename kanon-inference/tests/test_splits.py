"""Check frozen byte binding, complete partitioning, and simple leakage detection."""

import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import splits


def corpus():
    return {"schema_version": 1, "name": "split fixture", "purpose": "diagnostic",
            "tasks": [{"id": f"task{index}", "family": "constant", "module_id": f"module{index}",
                       "source": f'def target : Nat := synth "Return {index}."\n',
                       "candidates": ["0", str(index)],
                       "tests": [{"arguments": [], "expected": index}]} for index in (1, 2, 3)]}


def byte_hash(value):
    return hashlib.sha256(json.dumps(value).encode("utf-8")).hexdigest()


def manifest(value):
    return {"schema_version": 1, "name": "frozen fixture", "corpus_sha256": byte_hash(value),
            "split_unit": splits.SPLIT_UNIT,
            "modules": [{"module_id": f"module{index}", "split": split,
                         "template_group": f"template{index}"}
                        for index, split in enumerate(("train", "validation", "test"), 1)]}


class SplitTests(unittest.TestCase):
    def setUp(self):
        self.corpus = corpus()
        self.manifest = manifest(self.corpus)

    def validate(self):
        return splits.validate_manifest(self.manifest, self.corpus, byte_hash(self.corpus))

    def test_valid_manifest_is_returned_without_modification(self):
        original = copy.deepcopy(self.manifest)
        self.assertIs(self.validate(), self.manifest)
        self.assertEqual(self.manifest, original)

    def test_each_split_selects_only_its_module(self):
        self.validate()
        for index, split in enumerate(("train", "validation", "test")):
            with self.subTest(split=split):
                selected = splits.select_tasks(self.corpus, self.manifest, split)
                self.assertEqual(selected, [self.corpus["tasks"][index]])
                self.assertIs(selected[0], self.corpus["tasks"][index])

    def test_selection_preserves_corpus_order_and_whole_modules(self):
        extra = copy.deepcopy(self.corpus["tasks"][0])
        extra["id"] = "augmentation"
        self.corpus["tasks"].insert(2, extra)
        self.manifest["modules"][2]["split"] = "train"
        self.manifest["modules"].reverse()
        self.manifest["corpus_sha256"] = byte_hash(self.corpus)
        self.validate()
        selected = splits.select_tasks(self.corpus, self.manifest, "train")
        self.assertEqual([task["id"] for task in selected], ["task1", "augmentation", "task3"])

    def test_source_pool_and_oracle_tampering_break_frozen_hash(self):
        mutations = [lambda task: task.update(source=task["source"] + "\n"),
                     lambda task: task["candidates"].reverse(),
                     lambda task: task["tests"][0].update(expected=7)]
        for mutate in mutations:
            changed = copy.deepcopy(self.corpus)
            mutate(changed["tasks"][0])
            with self.subTest(mutate=mutate), self.assertRaisesRegex(splits.SplitError, "actual corpus bytes"):
                splits.validate_manifest(self.manifest, changed, byte_hash(changed))

    def test_binding_uses_file_bytes_including_json_whitespace(self):
        changed_bytes = json.dumps(self.corpus, indent=2).encode("utf-8")
        self.assertEqual(json.loads(changed_bytes), self.corpus)
        with self.assertRaisesRegex(splits.SplitError, "actual corpus bytes"):
            splits.validate_manifest(self.manifest, self.corpus, hashlib.sha256(changed_bytes).hexdigest())

    def test_template_groups_cannot_span_splits(self):
        self.manifest["modules"][1]["template_group"] = "template1"
        with self.assertRaisesRegex(splits.SplitError, "Template group spans splits"):
            self.validate()
        self.manifest["modules"][1]["split"] = "train"
        self.validate()

    def test_identical_payload_relabeling_is_rejected_between_modules(self):
        for split in ("train", "validation"):
            with self.subTest(split=split):
                self.corpus = corpus()
                self.manifest = manifest(self.corpus)
                duplicate = copy.deepcopy(self.corpus["tasks"][0])
                duplicate.update(id="different-id", family="different-family", module_id="module2")
                self.corpus["tasks"][1] = duplicate
                self.manifest["modules"][1]["split"] = split
                self.manifest["corpus_sha256"] = byte_hash(self.corpus)
                with self.assertRaisesRegex(splits.SplitError, "Duplicate task payload across modules"):
                    self.validate()

    def test_payload_dictionary_order_cannot_hide_duplicates(self):
        duplicate = copy.deepcopy(self.corpus["tasks"][0])
        duplicate.update(id="duplicate", module_id="module2")
        duplicate["tests"][0] = {"expected": 1, "arguments": []}
        self.corpus["tasks"][1] = dict(reversed(list(duplicate.items())))
        self.manifest["corpus_sha256"] = byte_hash(self.corpus)
        with self.assertRaisesRegex(splits.SplitError, "Duplicate task payload across modules"):
            self.validate()

    def test_duplicate_unknown_and_missing_modules_are_rejected(self):
        mutations = [lambda value: value["modules"].append(copy.deepcopy(value["modules"][0])),
                     lambda value: value["modules"].append(
                         {"module_id": "unknown", "split": "train", "template_group": "unknown"}),
                     lambda value: value["modules"].pop()]
        for mutate in mutations:
            value = copy.deepcopy(self.manifest)
            mutate(value)
            with self.subTest(mutate=mutate), self.assertRaises(splits.SplitError):
                splits.validate_manifest(value, self.corpus, byte_hash(self.corpus))

    def test_manifest_requires_exact_keys_and_bounded_types(self):
        mutations = [lambda value: value.update(extra=True),
                     lambda value: value.pop("name"),
                     lambda value: value.update(schema_version=True),
                     lambda value: value.update(schema_version=1.0),
                     lambda value: value.update(schema_version=2),
                     lambda value: value.update(name=" " * 3),
                     lambda value: value.update(name="x" * 201),
                     lambda value: value.update(name=[]),
                     lambda value: value.update(name="a\x00b"),
                     lambda value: value.update(name="\ud800"),
                     lambda value: value.update(corpus_sha256="A" * 64),
                     lambda value: value.update(corpus_sha256="0" * 63),
                     lambda value: value.update(corpus_sha256=[]),
                     lambda value: value.update(split_unit="task"),
                     lambda value: value.update(split_unit=[]),
                     lambda value: value.update(modules={}),
                     lambda value: value.update(modules=[]),
                     lambda value: value.update(modules=[None]),
                     lambda value: value.update(modules=value["modules"] * (splits.MAX_MODULES + 1))]
        for index, mutate in enumerate(mutations):
            value = copy.deepcopy(self.manifest)
            mutate(value)
            with self.subTest(mutation=index), self.assertRaises(splits.SplitError):
                splits.validate_manifest(value, self.corpus, byte_hash(self.corpus))
        for value in (None, [], True, "manifest"):
            with self.subTest(value=value), self.assertRaises(splits.SplitError):
                splits.validate_manifest(value, self.corpus, byte_hash(self.corpus))

    def test_assignment_requires_exact_keys_and_bounded_types(self):
        for key, malformed in (("module_id", [None, "", "x" * 201]),
                               ("template_group", [[], " ", "x" * 201]),
                               ("split", [[], True, "holdout", "TEST"])):
            for bad in malformed:
                value = copy.deepcopy(self.manifest)
                value["modules"][0][key] = bad
                with self.subTest(key=key, value=bad), self.assertRaises(splits.SplitError):
                    splits.validate_manifest(value, self.corpus, byte_hash(self.corpus))
        for entry in ({"module_id": "module1", "split": "train"},
                      dict(self.manifest["modules"][0], extra="unexpected")):
            value = copy.deepcopy(self.manifest)
            value["modules"][0] = entry
            with self.subTest(entry=entry), self.assertRaises(splits.SplitError):
                splits.validate_manifest(value, self.corpus, byte_hash(self.corpus))

    def test_module_and_task_counts_are_bounded(self):
        with patch.object(splits, "MAX_MODULES", 2):
            with self.assertRaisesRegex(splits.SplitError, "Manifest requires between"):
                self.validate()
        with patch.object(splits, "MAX_TASKS", 2):
            with self.assertRaisesRegex(splits.SplitError, "Corpus requires between"):
                self.validate()

    def test_task_metadata_requires_bounded_strings(self):
        for key in ("id", "family", "module_id"):
            for bad in ([], "", " ", "x" * 201, "a\x00b", "\ud800"):
                self.corpus = corpus()
                self.corpus["tasks"][0][key] = bad
                self.manifest["corpus_sha256"] = byte_hash(self.corpus)
                with self.subTest(key=key, value=bad), self.assertRaises(splits.SplitError):
                    self.validate()

    def test_duplicate_task_id_is_rejected(self):
        self.corpus["tasks"][1]["id"] = self.corpus["tasks"][0]["id"]
        self.corpus["tasks"][1]["source"] = 'def target : Nat := synth "Return two again."\n'
        self.manifest["corpus_sha256"] = byte_hash(self.corpus)
        with self.assertRaisesRegex(splits.SplitError, "Duplicate task id"):
            self.validate()

    def test_invalid_actual_hash_is_rejected(self):
        for digest in (None, [], "x" * 64, "A" * 64, "0" * 63):
            with self.subTest(digest=digest), self.assertRaises(splits.SplitError):
                splits.validate_manifest(self.manifest, self.corpus, digest)

    def test_empty_or_invalid_selected_split_is_rejected(self):
        for entry in self.manifest["modules"]:
            entry["split"] = "train"
        self.validate()
        for split in ("validation", "test", "holdout", [], None, True):
            with self.subTest(split=split), self.assertRaises(splits.SplitError):
                splits.select_tasks(self.corpus, self.manifest, split)

    def test_selection_rechecks_complete_assignments(self):
        self.validate()
        self.manifest["modules"].pop()
        with self.assertRaisesRegex(splits.SplitError, "Missing module assignment"):
            splits.select_tasks(self.corpus, self.manifest, "train")

    def test_invalid_corpus_structure_is_reported_as_split_error(self):
        for value in (None, [], {}, {"tasks": []}, {"tasks": [None]},
                      {"tasks": [{}]}, {"tasks": self.corpus["tasks"] * (splits.MAX_TASKS + 1)}):
            with self.subTest(value=type(value)), self.assertRaises(splits.SplitError):
                splits.validate_manifest(self.manifest, value, self.manifest["corpus_sha256"])

    def test_payload_serialization_and_size_are_bounded(self):
        self.corpus["tasks"][0]["tests"][0]["expected"] = float("nan")
        with self.assertRaisesRegex(splits.SplitError, "finite JSON"):
            self.validate()
        self.corpus = corpus()
        with patch.object(splits, "MAX_PAYLOAD_BYTES", 10):
            with self.assertRaisesRegex(splits.SplitError, "byte limit"):
                self.validate()


if __name__ == "__main__":
    unittest.main()
