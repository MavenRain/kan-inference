"""Adversarial evidence and interruption checks without loading model weights."""

import argparse
import copy
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SOURCE))
spec = importlib.util.spec_from_file_location("kan_experiment_under_test", SOURCE / "experiment.py")
experiment = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = experiment
spec.loader.exec_module(experiment)
benchmark = experiment.benchmark
driver = experiment.driver
import prompts


class ExperimentTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kan-experiment-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "checkout"
        self.root.mkdir()
        for relative in experiment.IMPLEMENTATION:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE.parent / relative, target)
        root_patch = patch.object(experiment, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)
        self.compiler = self.root / "compiler"
        self.compiler.write_text("fixture compiler, never executed\n")
        self.corpus_path = self.root / "corpus.json"
        tasks = []
        for split in ("train", "validation", "test"):
            for number in range(2):
                tasks.append({"id": f"{split}-{number}", "family": "constant", "module_id": split,
                    "source": f'def target : Nat := synth "Return one."\n-- {split}-{number}\n',
                    "candidates": ["0", "1"], "tests": [{"arguments": [], "expected": 1}]})
        self.corpus = {"schema_version": 1, "name": "fixture", "purpose": "diagnostic", "tasks": tasks}
        self.write(self.corpus_path, self.corpus)
        self.manifest_path = self.root / "splits.json"
        self.write(self.manifest_path, {"schema_version": 1, "name": "fixture splits",
            "corpus_sha256": driver.file_sha256(self.corpus_path), "split_unit": experiment.splits.SPLIT_UNIT,
            "modules": [{"module_id": split, "split": split, "template_group": split}
                        for split in ("train", "validation", "test")]})
        self.plan = {"schema_version": 1, "name": "fixture experiment", "corpus": "corpus.json",
            "split_manifest": "splits.json",
            "approaches": [{"id": profile, "provider": provider, "prompt_profile": profile}
                           for profile, provider in experiment.PROVIDERS.items()],
            "hosts": ["kernel"], "provider_timeout": 1, "check_timeout": 1,
            "selection_rule": experiment.RULE, "exposure_disclosure": "Developer-authored fixture; all splits exposed."}
        self.plan_path = self.root / "plan-original.json"
        self.write(self.plan_path, self.plan)
        self.directory = self.root / "output"
        self.args = argparse.Namespace(plan=self.plan_path, compiler=self.compiler, output_dir=self.directory)
        self.calls = []
        self.no_protocol = False
        self.change_identity = False
        self.after_run = None
        self.real_run = benchmark.run
        evaluation = patch.object(benchmark, "evaluate", side_effect=self.evaluate)
        evaluation.start()
        self.addCleanup(evaluation.stop)
        runs = patch.object(benchmark, "run", side_effect=self.run_benchmark)
        runs.start()
        self.addCleanup(runs.stop)

    @staticmethod
    def write(path, value):
        path.write_bytes(driver.canonical_json(value) + b"\n")

    def provenance(self, args):
        profile = "source-v3" if args.provider.name == "provider" else "kanon-primer-v1"
        identity = {key: "fixture" for key in experiment.IDENTITY_KEYS}
        identity.update(sha256="1" * 64, tokenizer_sha256="2" * 64,
                        model_size_bytes=100, tokenizer_size_bytes=100, cpu_threads=4)
        if self.change_identity and args.split == "validation":
            identity["model_id"] = "different model"
        return {**identity, "prompt_profile": profile, "prompt_version": experiment.PROMPT_VERSIONS[profile],
            "provider_code_sha256": driver.file_sha256(self.root / "kanon-inference/runtime.py"),
            "prompts_code_sha256": driver.file_sha256(self.root / "kanon-inference/prompts.py"),
            "prompt_sha256": "3" * 64}

    def evaluate(self, task, strategy, args, compiler, work):
        result = benchmark.empty_result()
        result["total_seconds"] = 0.0
        if strategy == "provider" and (self.no_protocol or task["id"].endswith("-1")):
            result["failure"] = {"code": "process_timeout", "message": "fixture timeout"}
            return result
        candidate_hash = driver.sha256(b"1")
        result.update(first_attempt_type_accepted=True, type_accepted=True,
            first_attempt_semantic_correct=True, semantic_correct=True,
            attempts=[{"index": 0, "candidate_sha256": candidate_hash, "type_valid": True, "error": None}],
            selected={"index": 0, "candidate": "1", "candidate_sha256": candidate_hash}, ranking=["1", "0"],
            tests=[{"arguments": [], "expected": 1, "hosts": {"kernel": {"value": 1, "error": None}},
                    "passed": True, "host_disagreement": False}])
        if strategy == "provider":
            result.update(provider_exit_status=0, provenance=self.provenance(args))
        return result

    def run_benchmark(self, args):
        self.calls.append((args.split, args.provider.name))
        self.assertIsNone(args.limit)
        if args.split == "test":
            self.assertTrue((self.directory / "selection.json").is_file())
            self.assertTrue(json.loads((self.directory / "selection.json").read_text())["complete"])
            if (self.directory / "experiment.json").exists():
                self.assertFalse(json.loads((self.directory / "experiment.json").read_text())["complete"])
        report = self.real_run(args)
        if self.after_run:
            self.after_run(args, report)
        return report

    def completed(self):
        result = experiment.run(self.args)
        self.assertTrue(result["complete"])
        return self.directory / "selection.json"

    def replay(self, selection=None):
        return experiment.replay(argparse.Namespace(selection=selection or self.directory / "selection.json",
                                                     output=self.directory / "replay.json"))

    def reject_replay(self, message=None):
        before = len(self.calls)
        with self.assertRaises(experiment.Error) as caught:
            self.replay()
        if message is not None:
            self.assertIn(message, str(caught.exception))
        self.assertEqual(len(self.calls), before, "Invalid evidence reached test evaluation")
        self.assertFalse((self.directory / "replay.json").exists())

    def edit_selection(self, mutate):
        path = self.directory / "selection.json"
        value = json.loads(path.read_text())
        mutate(value)
        self.write(path, value)
        return path

    def edit_evidence(self, mutate, index=2):
        selection_path = self.directory / "selection.json"
        selection = json.loads(selection_path.read_text())
        record = selection["evidence"][index]
        path = self.directory / record["path"]
        report = json.loads(path.read_text())
        mutate(report)
        self.write(path, report)
        record["sha256"] = driver.file_sha256(path)
        self.write(selection_path, selection)

    def test_full_run_freezes_bytes_orders_splits_and_retains_failed_denominators(self):
        selection_path = self.completed()
        self.assertEqual(self.calls, [("train", "provider"), ("train", "provider-primer"),
            ("validation", "provider"), ("validation", "provider-primer"), ("test", "provider")])
        self.assertEqual((self.directory / "plan.json").read_bytes(), self.plan_path.read_bytes())
        selection = json.loads(selection_path.read_text())
        self.assertEqual(selection["winner"], "source-v3")
        self.assertEqual(selection["scores"], [
            {"approach_id": "source-v3", "semantic_correct": 1, "denominator": 2, "failures": 1},
            {"approach_id": "kanon-primer-v1", "semantic_correct": 1, "denominator": 2, "failures": 1}])
        self.assertTrue(all(not Path(item["path"]).is_absolute() for item in selection["evidence"]))

    def test_replay_evaluates_only_frozen_winner(self):
        self.completed()
        self.after_run = None
        # The enclosing experiment was already published; replay itself needs no wrapper.
        original = self.directory / "experiment.json"
        original.rename(self.directory / "published.json")
        self.assertTrue(self.replay()["complete"])
        self.assertEqual(self.calls[-1], ("test", "provider"))
        self.assertEqual(len(self.calls), 6)

    def test_selection_rule_uses_plan_order_for_ties(self):
        self.plan["approaches"].reverse()
        self.write(self.plan_path, self.plan)
        selection = json.loads(self.completed().read_text())
        self.assertEqual(selection["winner"], "kanon-primer-v1")
        self.assertEqual(self.calls[-1], ("test", "provider-primer"))

    def test_edited_winner_is_rejected_before_test(self):
        path = self.completed()
        selection = json.loads(path.read_text())
        selection["winner"] = "kanon-primer-v1"
        self.write(path, selection)
        self.reject_replay()

    def test_wrong_validation_split_is_rejected_even_with_updated_report_hash(self):
        self.completed()
        original_selection = (self.directory / "selection.json").read_bytes()
        record = json.loads(original_selection)["evidence"][2]
        report_path = self.directory / record["path"]
        original_report = report_path.read_bytes()
        for split in ("train", "test"):
            with self.subTest(split=split):
                (self.directory / "selection.json").write_bytes(original_selection)
                report_path.write_bytes(original_report)
                self.edit_evidence(lambda report: report["split"].update(name=split))
                self.reject_replay()

    def test_incomplete_duplicate_pending_and_inconsistent_evidence_is_rejected(self):
        self.completed()
        selection_path = self.directory / "selection.json"
        original_selection = selection_path.read_bytes()
        record = json.loads(original_selection)["evidence"][2]
        report_path = self.directory / record["path"]
        original_report = report_path.read_bytes()
        mutations = [
            lambda report: report.update(complete=False),
            lambda report: report["results"].pop(),
            lambda report: report["results"].__setitem__(1, copy.deepcopy(report["results"][0])),
            lambda report: report["results"][1]["strategies"].pop("provider"),
            lambda report: report["summary"]["provider"]["overall"].update(pending=1),
            lambda report: report["summary"]["provider"]["overall"]["semantic_correct"].update(denominator=1),
            lambda report: report["results"][0]["strategies"]["provider"].update(semantic_correct=False),
            lambda report: report["results"][0]["strategies"]["provider"]["tests"][0]["hosts"]["kernel"].update(value=0),
            lambda report: report["results"][0]["strategies"]["provider"]["provenance"].update(prompt_profile="kanon-primer-v1"),
            lambda report: report["results"][0]["strategies"]["provider"]["provenance"].update(provider_code_sha256="4" * 64),
            lambda report: report["results"][0]["strategies"]["provider"]["provenance"].update(prompts_code_sha256="4" * 64),
            lambda report: report["implementation"].update(benchmark_sha256="4" * 64),
            lambda report: report["results"][0]["strategies"]["provider"].update(ranking=["0", "1"]),
            lambda report: report["results"][0]["strategies"]["provider"]["provenance"].update(prompt_version="wrong"),
            lambda report: report.update(corpus=[]),
            lambda report: report["results"][0]["strategies"]["provider"].update(provider_exit_status=1),
            lambda report: report["gate"].update(status="met"),
            lambda report: report.update(confidence_note="rewritten: results generalize"),
            lambda report: report.update(rewritten_by_operator=True),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                selection_path.write_bytes(original_selection)
                report_path.write_bytes(original_report)
                self.edit_evidence(mutate)
                self.reject_replay()

    def test_changed_frozen_files_and_report_bytes_are_rejected(self):
        self.completed()
        paths = [*(self.root / path for path in experiment.IMPLEMENTATION), self.compiler,
                 self.corpus_path, self.manifest_path, self.plan_path, self.directory / "plan.json",
                 self.directory / "validation-source-v3.json"]
        for path in paths:
            with self.subTest(path=path.name):
                original = path.read_bytes()
                path.write_bytes(original + b"\n")
                try:
                    self.reject_replay()
                finally:
                    path.write_bytes(original)

    def test_changes_during_train_prevent_next_run_and_leave_incomplete_state(self):
        def change(_args, _report):
            with (self.root / "kanon-inference/prompts.py").open("ab") as stream:
                stream.write(b"\n# changed\n")
        self.after_run = change
        with self.assertRaises(experiment.Error):
            experiment.run(self.args)
        self.assertEqual(len(self.calls), 1)
        report = json.loads((self.directory / "experiment.json").read_text())
        self.assertFalse(report["complete"])
        self.assertTrue(report["failure"])
        self.assertFalse((self.directory / "selection.json").exists())

    def test_replay_postflight_failure_preserves_test_data_as_incomplete(self):
        self.completed()
        (self.directory / "experiment.json").rename(self.directory / "published.json")
        def change(args, _report):
            if args.split == "test":
                with (self.root / "kanon-inference/prompts.py").open("ab") as stream:
                    stream.write(b"\n# changed during replay\n")
        self.after_run = change
        with self.assertRaisesRegex(experiment.Error, "Frozen source changed"):
            self.replay()
        retained = json.loads((self.directory / "replay.json").read_text())
        self.assertFalse(retained["complete"])
        self.assertEqual(retained["failure"]["code"], "invalid_experiment")
        self.assertEqual(len(retained["results"]), 2)

    def test_selected_candidate_must_be_first_successful_attempt(self):
        self.completed()
        def impossible(report):
            result = report["results"][0]["strategies"]["provider"]
            result["ranking"] = ["0", "1"]
            first = {"index": 0, "candidate_sha256": driver.sha256(b"0"), "type_valid": True, "error": None}
            result["attempts"] = [first, dict(result["attempts"][0], index=1)]
            result["selected"]["index"] = 1
            result["first_attempt_type_accepted"] = False
            result["first_attempt_semantic_correct"] = False
            tasks = [task for task in self.corpus["tasks"] if task["module_id"] == "validation"]
            report["summary"] = benchmark.summarize(report, tasks)
        self.edit_evidence(impossible)
        self.reject_replay()

    def test_no_successful_train_protocol_does_not_select_or_test(self):
        self.no_protocol = True
        with self.assertRaisesRegex(experiment.Error, "No successful provider protocol"):
            experiment.run(self.args)
        self.assertEqual(len(self.calls), 2)
        self.assertFalse((self.directory / "selection.json").exists())
        report = json.loads((self.directory / "experiment.json").read_text())
        self.assertFalse(report["complete"])
        self.assertEqual(len(report["evidence"]), 2)

    def test_runtime_identity_drift_prevents_selection(self):
        self.change_identity = True
        with self.assertRaisesRegex(experiment.Error, "identity changed"):
            experiment.run(self.args)
        self.assertEqual(len(self.calls), 3)
        self.assertFalse((self.directory / "selection.json").exists())

    def test_interrupt_before_selection_preserves_incomplete_outputs(self):
        with patch.object(benchmark, "evaluate", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                experiment.run(self.args)
        report = json.loads((self.directory / "experiment.json").read_text())
        self.assertFalse(report["complete"])
        self.assertEqual(report["failure"]["code"], "interrupted")
        train = json.loads((self.directory / "train-source-v3.json").read_text())
        self.assertFalse(train["complete"])
        self.assertFalse((self.directory / "selection.json").exists())

    def test_interrupt_on_test_keeps_saved_selection_and_incomplete_experiment(self):
        original = self.evaluate
        def interrupt(task, strategy, args, compiler, work):
            if args.split == "test":
                raise KeyboardInterrupt
            return original(task, strategy, args, compiler, work)
        with patch.object(benchmark, "evaluate", side_effect=interrupt):
            with self.assertRaises(KeyboardInterrupt):
                experiment.run(self.args)
        self.assertTrue(json.loads((self.directory / "selection.json").read_text())["complete"])
        self.assertFalse(json.loads((self.directory / "experiment.json").read_text())["complete"])
        self.assertFalse(json.loads((self.directory / "test.json").read_text())["complete"])

    def test_existing_output_directory_is_preserved(self):
        self.directory.mkdir()
        marker = self.directory / "keep"
        marker.write_text("preserved")
        with self.assertRaises(experiment.Error) as caught:
            experiment.run(self.args)
        self.assertEqual(caught.exception.code, "output_exists")
        self.assertEqual(marker.read_text(), "preserved")
        self.assertEqual(self.calls, [])

    def test_existing_replay_report_is_preserved(self):
        self.completed()
        (self.directory / "experiment.json").rename(self.directory / "published.json")
        output = self.directory / "replay.json"
        output.write_text("preserved")
        with self.assertRaises(experiment.Error) as caught:
            self.replay()
        self.assertEqual(caught.exception.code, "output_exists")
        self.assertEqual(output.read_text(), "preserved")

    def test_selection_replays_after_identical_checkout_is_relocated(self):
        self.completed()
        relocated = Path(self.temporary.name) / "relocated"
        shutil.copytree(self.root, relocated)
        self.root = relocated
        self.directory = relocated / "output"
        (self.directory / "experiment.json").rename(self.directory / "published.json")
        with patch.object(experiment, "ROOT", relocated):
            self.assertTrue(self.replay()["complete"])

    def test_selection_rejects_missing_extra_and_traversal_fields(self):
        path = self.completed()
        original = path.read_bytes()
        mutations = [lambda value: value.pop("model_identity"),
                     lambda value: value.update(unknown=True),
                     lambda value: value["evidence"][0].update(path="../plan-original.json"),
                     lambda value: value["evidence"].pop(),
                     lambda value: value["scores"][0].update(semantic_correct=True)]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                value = json.loads(original)
                mutate(value)
                self.write(path, value)
                self.reject_replay()

    def test_plan_defects_are_rejected_before_any_evaluation(self):
        mutations = [
            lambda plan: plan["approaches"][0].update(provider="kanon-inference/provider-primer"),
            lambda plan: plan.update(selection_rule="maximum_train_semantic_count"),
            lambda plan: plan.update(hosts=["kernel", "unknown"]),
            lambda plan: plan.update(hosts=["kernel", "kernel"]),
            lambda plan: plan["approaches"][1].update(id=plan["approaches"][0]["id"]),
            lambda plan: plan["approaches"][1].update(prompt_profile="source-v3",
                                                      provider="kanon-inference/provider"),
            lambda plan: plan["approaches"][1].update(prompt_profile="unknown-v1"),
            lambda plan: plan.update(schema_version=2),
            lambda plan: plan.update(split_manifest=plan["corpus"]),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                plan = copy.deepcopy(self.plan)
                mutate(plan)
                self.write(self.plan_path, plan)
                with self.assertRaises(experiment.Error):
                    experiment.run(self.args)
                self.assertEqual(self.calls, [])
                self.assertFalse(self.directory.exists())

    def test_plan_outside_the_checkout_is_rejected(self):
        outside = Path(self.temporary.name) / "outside-plan.json"
        self.write(outside, self.plan)
        with self.assertRaisesRegex(experiment.Error, "Plan must be inside the checkout"):
            experiment.run(argparse.Namespace(plan=outside, compiler=self.compiler,
                                              output_dir=self.directory))
        self.assertEqual(self.calls, [])
        self.assertFalse(self.directory.exists())

    def test_absolute_compiler_record_is_checked_by_scope_path_and_existence(self):
        outside = Path(self.temporary.name) / "outside-compiler"
        outside.write_text("fixture compiler, never executed\n")
        self.args = argparse.Namespace(plan=self.plan_path, compiler=outside,
                                       output_dir=self.directory)
        path = self.completed()
        (self.directory / "experiment.json").rename(self.directory / "published.json")
        self.assertEqual(json.loads(path.read_text())["frozen"]["compiler"]["scope"], "absolute")
        self.assertTrue(self.replay()["complete"])
        (self.directory / "replay.json").unlink()
        original = path.read_bytes()
        cases = [
            (lambda value: value["frozen"]["compiler"].update(scope="elsewhere"),
             "Invalid compiler scope"),
            (lambda value: value["frozen"]["compiler"].update(path="compiler"),
             "Compiler requires an absolute path"),
            (lambda value: value["frozen"]["compiler"].update(scope="root", path=str(outside)),
             "Paths must be normalized and relative without parent traversal"),
            (lambda value: value["frozen"]["compiler"].update(path=str(outside) + "-missing"),
             "Missing file: " + str(outside) + "-missing"),
        ]
        for index, (mutate, message) in enumerate(cases):
            with self.subTest(case=index):
                path.write_bytes(original)
                self.edit_selection(mutate)
                self.reject_replay(message)

    def test_root_scoped_compiler_record_rejects_a_missing_relative_path(self):
        path = self.completed()
        (self.directory / "experiment.json").rename(self.directory / "published.json")
        self.assertEqual(json.loads(path.read_text())["frozen"]["compiler"],
                         {"path": "compiler", "scope": "root",
                          "sha256": driver.file_sha256(self.compiler)})
        self.compiler.unlink()
        self.reject_replay("Missing file: compiler")

    def test_missing_frozen_source_names_the_file(self):
        self.completed()
        (self.directory / "experiment.json").rename(self.directory / "published.json")
        (self.root / "kanon-inference/prompts.py").unlink()
        self.reject_replay("Missing file: kanon-inference/prompts.py")

    def test_loaded_driver_module_must_match_the_frozen_source(self):
        self.completed()
        (self.directory / "experiment.json").rename(self.directory / "published.json")
        other = Path(self.temporary.name) / "synth-copy.py"
        other.write_bytes((self.root / "kanon-synth/dev/synth.py").read_bytes() + b"\n# override\n")
        with patch.object(driver, "__file__", str(other)):
            self.reject_replay(
                "Loaded implementation does not match frozen source: kanon-synth/dev/synth.py")

    def test_selection_bytes_changed_during_test_evaluation_are_rejected(self):
        self.completed()
        (self.directory / "experiment.json").rename(self.directory / "published.json")
        def touch(args, _report):
            if args.split == "test":
                with (self.directory / "selection.json").open("ab") as stream:
                    stream.write(b"\n")
        self.after_run = touch
        with self.assertRaisesRegex(experiment.Error, "Selection changed during test evaluation"):
            self.replay()
        retained = json.loads((self.directory / "replay.json").read_text())
        self.assertFalse(retained["complete"])

    def test_selection_changed_before_publication_is_rejected(self):
        selection_path = self.directory / "selection.json"
        real_replay = experiment.replay
        def publish(args):
            result = real_replay(args)
            with selection_path.open("ab") as stream:
                stream.write(b"\n")
            return result
        with patch.object(experiment, "replay", side_effect=publish):
            with self.assertRaisesRegex(experiment.Error, "Selection changed before publication"):
                experiment.run(self.args)
        report = json.loads((self.directory / "experiment.json").read_text())
        self.assertFalse(report["complete"])

    def test_saved_report_rewritten_after_evaluation_is_rejected(self):
        def rewrite(args, _report):
            saved = json.loads(args.output.read_text())
            saved["total_seconds"] = saved["total_seconds"] + 1
            self.write(args.output, saved)
        self.after_run = rewrite
        with self.assertRaisesRegex(experiment.Error, "Saved report differs from evaluation"):
            experiment.run(self.args)
        self.assertEqual(len(self.calls), 1)
        self.assertFalse((self.directory / "selection.json").exists())

    def test_saved_test_report_rewritten_after_evaluation_is_rejected(self):
        self.completed()
        (self.directory / "experiment.json").rename(self.directory / "published.json")
        def rewrite(args, _report):
            if args.split == "test":
                saved = json.loads(args.output.read_text())
                saved["total_seconds"] = saved["total_seconds"] + 1
                self.write(args.output, saved)
        self.after_run = rewrite
        with self.assertRaisesRegex(experiment.Error, "Saved test report differs from evaluation"):
            self.replay()
        retained = json.loads((self.directory / "replay.json").read_text())
        self.assertFalse(retained["complete"])

    def test_unreadable_partial_test_report_is_recorded(self):
        self.completed()
        (self.directory / "experiment.json").rename(self.directory / "published.json")
        def corrupt(args, _report):
            if args.split == "test":
                args.output.write_bytes(b"{not json")
                raise experiment.Error("invalid_experiment", "fixture postflight failure")
        self.after_run = corrupt
        with self.assertRaisesRegex(experiment.Error, "fixture postflight failure"):
            self.replay()
        retained = json.loads((self.directory / "replay.json").read_text())
        self.assertFalse(retained["complete"])
        self.assertEqual(retained["failure"]["message"], "fixture postflight failure")
        self.assertEqual(type(retained["partial_read_failure"]["code"]), str)
        self.assertTrue(retained["partial_read_failure"]["message"])

    def test_replay_records_only_the_output_file_name(self):
        self.completed()
        published = json.loads((self.directory / "experiment.json").read_text())
        self.assertEqual(published["test"]["output"], "test.json")
        (self.directory / "experiment.json").rename(self.directory / "published.json")
        self.assertEqual(self.replay()["output"], "replay.json")

    def test_prompt_versions_match_the_frozen_profiles(self):
        self.assertEqual(set(experiment.PROMPT_VERSIONS), set(experiment.PROVIDERS))
        self.assertEqual(set(prompts.PROFILES), set(experiment.PROVIDERS))
        for profile in experiment.PROVIDERS:
            self.assertEqual(experiment.PROMPT_VERSIONS[profile],
                             prompts.PROFILES[profile]["version"])


if __name__ == "__main__":
    unittest.main()
