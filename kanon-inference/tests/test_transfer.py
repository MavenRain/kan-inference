"""Frozen transfer evidence checks with the real report writer and no model."""

import argparse
import copy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SOURCE))
import transfer

experiment = transfer.experiment
benchmark = transfer.benchmark
driver = transfer.driver


class TransferTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="kan-transfer-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "checkout"
        self.root.mkdir()
        for relative in transfer.IMPLEMENTATION:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE.parent / relative, path)
        self.patch(experiment, "ROOT", self.root)
        self.compiler = self.root / "compiler"
        self.compiler.write_text("fixture compiler, never executed\n")
        self.corpus = {"schema_version": 1, "name": "fixture", "purpose": "diagnostic", "tasks": [
            {"id": f"task-{index}", "family": family, "module_id": f"module-{index}",
             "source": f'def target : Nat := synth "Return one."\n-- {index}\n',
             "candidates": ["0", "1"], "tests": [{"arguments": [], "expected": 1}]}
            for index, family in enumerate(("constant", "context"))]}
        self.write(self.root / "corpus.json", self.corpus)
        self.manifest = {"schema_version": 1, "name": "fixture development",
            "corpus_sha256": driver.file_sha256(self.root / "corpus.json"),
            "split_unit": experiment.splits.SPLIT_UNIT,
            "modules": [{"module_id": f"module-{index}", "split": "train", "template_group": f"family-{index}"}
                        for index in range(2)]}
        self.write(self.root / "splits.json", self.manifest)
        self.authorship = {"schema_version": 1, "corpus_sha256": self.manifest["corpus_sha256"],
            "author_role": "fixture author", "process": "Authored before comparison.",
            "exposure_disclosure": "Entire development fixture exposed."}
        self.write(self.root / "authorship.json", self.authorship)
        self.plan = {"schema_version": 1, "name": "fixture transfer", "corpus": "corpus.json",
            "split_manifest": "splits.json", "authorship": "authorship.json",
            "approaches": copy.deepcopy(transfer.APPROACHES), "hosts": ["kernel"],
            "provider_timeout": 1, "check_timeout": 1, "comparison_rule": transfer.RULE,
            "exposure_disclosure": "Entire development fixture exposed; no selection."}
        self.plan_path = self.root / "original-plan.json"
        self.write(self.plan_path, self.plan)
        self.directory = self.root / "output"
        self.report_path = self.directory / "transfer.json"
        self.args = argparse.Namespace(plan=self.plan_path, compiler=self.compiler, output_dir=self.directory)
        self.calls = []
        self.after_run = None
        self.no_protocol = False
        self.change_identity = False
        self.real_run = benchmark.run
        self.patch(benchmark, "evaluate", self.evaluate)
        self.patch(benchmark, "run", self.run_benchmark)

    def patch(self, target, name, value):
        active = patch.object(target, name, value)
        active.start()
        self.addCleanup(active.stop)

    @staticmethod
    def write(path, value):
        path.write_bytes(driver.canonical_json(value) + b"\n")

    @staticmethod
    def request():
        return {"protocol_version": 1, "declaration": "target", "hint": "Return one.",
                "expected_type": "Nat", "context": "", "allowed_axioms": ["Nat"]}

    def provenance(self, args):
        calibrated = args.provider.name == "provider-calibrated"
        approach = transfer.APPROACHES[int(calibrated)]
        identity = {key: "fixture" for key in experiment.IDENTITY_KEYS}
        identity.update(sha256="1" * 64, tokenizer_sha256="2" * 64,
                        model_size_bytes=100, tokenizer_size_bytes=100, cpu_threads=4)
        if self.change_identity and calibrated:
            identity["model_id"] = "changed model"
        result = {**identity, "prompt_profile": "source-v3",
            "prompt_version": experiment.PROMPT_VERSIONS["source-v3"],
            "provider_code_sha256": driver.file_sha256(self.root / "kanon-inference/runtime.py"),
            "prompts_code_sha256": driver.file_sha256(self.root / "kanon-inference/prompts.py"),
            "scoring_profile": approach["scoring_profile"],
            "scoring_version": experiment.scoring.PROFILES[approach["scoring_profile"]]["version"],
            "scoring_code_sha256": driver.file_sha256(self.root / "kanon-inference/scoring.py"),
            "decoding": "hint-calibrated-loglikelihood" if calibrated else "conditional-loglikelihood",
            "prompt_sha256": driver.sha256(experiment.prompts.build_prompt(self.request(), "source-v3").encode())}
        if calibrated:
            reference = experiment.prompts.build_prompt(experiment.scoring.reference_request(self.request()), "source-v3")
            result["reference_prompt_sha256"] = driver.sha256(reference.encode())
        return result

    def evaluate(self, task, strategy, args, compiler, work):
        result = benchmark.empty_result()
        result["total_seconds"] = 0.0
        if strategy == "provider" and (self.no_protocol or
                (task["id"] == "task-1" and args.provider.name == "provider")):
            result["failure"] = {"code": "process_timeout", "message": "fixture timeout"}
            return result
        correct = strategy != "candidate_order"
        candidate = "1" if correct else "0"
        candidate_hash = driver.sha256(candidate.encode())
        result.update(first_attempt_type_accepted=True, type_accepted=True,
            request=self.request(), request_sha256=driver.sha256(driver.canonical_json(self.request())),
            first_attempt_semantic_correct=correct, semantic_correct=correct,
            attempts=[{"index": 0, "candidate_sha256": candidate_hash, "type_valid": True, "error": None}],
            selected={"index": 0, "candidate": candidate, "candidate_sha256": candidate_hash},
            ranking=["1", "0"] if correct else ["0", "1"],
            tests=[{"arguments": [], "expected": 1, "hosts": {"kernel": {"value": int(candidate), "error": None}},
                    "passed": correct, "host_disagreement": False}],
            failure=None if correct else {"code": "wrong_value", "message": "fixture wrong value"})
        if strategy == "provider":
            result.update(provider_exit_status=0, provenance=self.provenance(args))
            result["provider_metrics"] = {"mode": result["provenance"]["decoding"],
                "mean_token_logprobs": [-3.0, -1.0], "ranking_scores": [-3.0, -1.0], "ranked_indices": [1, 0]}
            if args.provider.name == "provider-calibrated":
                result["provider_metrics"].update(reference_mean_token_logprobs=[-2.0, -2.0], ranking_scores=[-1.0, 1.0])
        return result

    def run_benchmark(self, args):
        self.calls.append((args.split, args.provider.name))
        self.assertIsNone(args.limit)
        self.assertEqual(args.split, "train")
        self.assertEqual((self.directory / "plan.json").read_bytes(), self.plan_path.read_bytes())
        self.assertFalse(json.loads(self.report_path.read_text())["complete"])
        result = self.real_run(args)
        if self.after_run:
            self.after_run(args, result)
        return result

    def completed(self):
        result = transfer.run(self.args)
        self.assertTrue(result["complete"])
        return result

    def edit_report(self, mutate):
        report = json.loads(self.report_path.read_text())
        mutate(report)
        self.write(self.report_path, report)

    def edit_evidence(self, mutate, index=0):
        report = json.loads(self.report_path.read_text())
        record = report["evidence"][index]
        path = self.directory / record["path"]
        evidence = json.loads(path.read_text())
        mutate(evidence)
        self.write(path, evidence)
        record["sha256"] = driver.file_sha256(path)
        self.write(self.report_path, report)

    def test_complete_comparison_keeps_all_tasks_failures_and_no_selection(self):
        result = self.completed()
        self.assertEqual(self.calls, [("train", "provider"), ("train", "provider-calibrated")])
        self.assertEqual(set(result), transfer.REPORT_KEYS)
        self.assertNotIn("winner", result)
        self.assertFalse((self.directory / "selection.json").exists())
        self.assertEqual(result["summary"]["tasks"], 2)
        self.assertEqual(len(result["summary"]["paired_comparisons"]), 5)
        compared = result["summary"]["paired_comparisons"][-1]["metrics"]["semantic_correct"]
        self.assertEqual(compared["overall"], {"denominator": 2, "both_correct": 1,
            "left_only_correct": 0, "right_only_correct": 1, "neither_correct": 0, "left_minus_right": -1})
        self.assertEqual(compared["by_family"]["context"]["right_only_correct"], 1)
        self.assertEqual(result["summary"]["approaches"][0]["strategies"]["provider"]["overall"]["failures"], 1)
        self.assertEqual(transfer.validate_transfer(self.report_path), result)
        self.assertEqual(len(self.calls), 2, "Integrity verification must not execute the model")

    def test_sources_plan_copy_compiler_and_authorship_are_frozen(self):
        result = self.completed()
        self.assertEqual(len(result["frozen"]["sources"]), len(transfer.IMPLEMENTATION) + 4)
        paths = [self.plan_path, self.root / "corpus.json", self.root / "splits.json",
                 self.root / "authorship.json", self.compiler, self.directory / "plan.json"]
        paths.extend(self.root / relative for relative in transfer.IMPLEMENTATION)
        for path in paths:
            with self.subTest(path=path):
                original = path.read_bytes()
                path.write_bytes(original + b"\n")
                with self.assertRaises(experiment.Error):
                    transfer.validate_transfer(self.report_path)
                path.write_bytes(original)

    def test_loaded_transfer_and_experiment_source_bindings_are_checked(self):
        self.completed()
        alternate = self.root / "alternate.py"
        alternate.write_text("different loaded implementation\n")
        for module in (transfer, experiment, benchmark, experiment.prompts, experiment.scoring,
                       experiment.splits, driver):
            with self.subTest(module=module.__name__), patch.object(module, "__file__", str(alternate)):
                with self.assertRaisesRegex(experiment.Error, "Loaded implementation does not match"):
                    transfer.validate_transfer(self.report_path)

    def test_top_level_identity_summary_and_source_binding_tampering_is_rejected(self):
        self.completed()
        original = self.report_path.read_bytes()
        cases = [lambda value: value.update(complete=False),
                 lambda value: value.update(winner="hint-calibrated-v1"),
                 lambda value: value["summary"].update(tasks=1),
                 lambda value: value["summary"]["paired_comparisons"][-1]["metrics"]["semantic_correct"]["overall"].update(right_only_correct=0),
                 lambda value: value["model_identity"].update(model_id="edited"),
                 lambda value: value["scoring_identities"]["source-v3"].update(scoring_version="edited"),
                 lambda value: value["frozen"]["sources"].pop("kanon-inference/transfer.py"),
                 lambda value: value["frozen"]["sources"].update({"../escape.py": "0" * 64}),
                 lambda value: value["plan"].update(comparison_rule=experiment.RULE),
                 lambda value: value["evidence"].pop(),
                 lambda value: value["evidence"][0].update(path="../original-plan.json"),
                 lambda value: value["evidence"][1].update(path=value["evidence"][0]["path"],
                                                           sha256=value["evidence"][0]["sha256"])]
        for index, mutate in enumerate(cases):
            with self.subTest(index=index):
                self.report_path.write_bytes(original)
                self.edit_report(mutate)
                with self.assertRaises(experiment.Error):
                    transfer.validate_transfer(self.report_path)
        self.report_path.write_bytes(original)
        self.edit_report(lambda value: value["frozen"].update(plan_sha256="zz"))
        with self.assertRaisesRegex(experiment.Error, "Invalid frozen transfer plan identity"):
            transfer.validate_transfer(self.report_path)

    def test_rehashed_incomplete_duplicate_limited_numeric_and_provider_evidence_is_rejected(self):
        self.completed()
        original = self.report_path.read_bytes()
        path = self.directory / "development-source-v3.json"
        evidence = path.read_bytes()
        cases = [lambda value: value.update(complete=False),
                 lambda value: value["results"].pop(),
                 lambda value: value["results"].__setitem__(1, copy.deepcopy(value["results"][0])),
                 lambda value: value["split"].update(limited=True),
                 lambda value: value["results"][0]["strategies"].pop("deterministic"),
                 lambda value: value["summary"]["provider"]["overall"].update(tasks=1),
                 lambda value: value["implementation"].update(benchmark_sha256="0" * 64),
                 lambda value: value["results"][0]["strategies"]["provider"]["provider_metrics"].update(ranking_scores=[-1.0, -3.0]),
                 lambda value: value["results"][0]["strategies"]["provider"]["provenance"].update(model_id="edited")]
        for index, mutate in enumerate(cases):
            with self.subTest(index=index):
                self.report_path.write_bytes(original)
                path.write_bytes(evidence)
                self.edit_evidence(mutate)
                with self.assertRaises(experiment.Error):
                    transfer.validate_transfer(self.report_path)

    def test_evidence_bytes_require_the_saved_hash(self):
        self.completed()
        path = self.directory / "development-source-v3.json"
        path.write_bytes(path.read_bytes() + b"\n")
        with self.assertRaisesRegex(experiment.Error, "Evaluation evidence bytes changed"):
            transfer.validate_transfer(self.report_path)

    def test_plan_rejects_selection_unsupported_methods_and_duplicate_paths_before_run(self):
        cases = [(lambda value: value.update(selection_rule=experiment.RULE), "Malformed transfer plan fields"),
                 (lambda value: value["approaches"].reverse(), "two fixed scoring approaches in order"),
                 (lambda value: value["approaches"][0].update(scoring_profile="hint-calibrated-v1"),
                  "two fixed scoring approaches in order"),
                 (lambda value: value.update(corpus="../corpus.json"), "without parent traversal"),
                 (lambda value: value.update(authorship=""), "relative POSIX path"),
                 (lambda value: value.update(provider_timeout=True), "Invalid provider_timeout"),
                 (lambda value: value.update(comparison_rule=experiment.RULE), "Unsupported transfer comparison rule"),
                 (lambda value: value.update(schema_version=2), "Unsupported transfer plan version")]
        for index, (mutate, message) in enumerate(cases):
            with self.subTest(index=index):
                plan = copy.deepcopy(self.plan)
                mutate(plan)
                self.write(self.plan_path, plan)
                with self.assertRaisesRegex(experiment.Error, message):
                    transfer.run(self.args)
                self.assertEqual(self.calls, [])
                self.assertFalse(self.directory.exists())

    def test_manifest_and_authorship_must_bind_full_exposed_development_corpus(self):
        self.manifest["modules"][1]["split"] = "test"
        self.write(self.root / "splits.json", self.manifest)
        with self.assertRaisesRegex(experiment.Error, "every module"):
            transfer.run(self.args)
        self.manifest["modules"][1]["split"] = "train"
        self.write(self.root / "splits.json", self.manifest)
        cases = [(lambda value: value.update(corpus_sha256="0" * 64), "authorship corpus binding"),
                 (lambda value: value.update(reviewer="extra"), "transfer authorship"),
                 (lambda value: value.update(author_role=" "), "Authorship author_role must be bounded nonempty text"),
                 (lambda value: value.update(process="p" * 8193), "Authorship process must be bounded nonempty text")]
        for index, (mutate, message) in enumerate(cases):
            with self.subTest(index=index):
                authorship = copy.deepcopy(self.authorship)
                mutate(authorship)
                self.write(self.root / "authorship.json", authorship)
                with self.assertRaisesRegex(experiment.Error, message):
                    transfer.run(self.args)
                self.assertEqual(self.calls, [])
                self.assertFalse(self.directory.exists())

    def test_plan_outside_checkout_is_rejected_before_run(self):
        with tempfile.TemporaryDirectory(prefix="kan-transfer-outside-") as outside:
            self.args.plan = Path(outside) / "plan.json"
            shutil.copy2(self.plan_path, self.args.plan)
            with self.assertRaisesRegex(experiment.Error, "Plan must be inside the checkout"):
                transfer.run(self.args)
        self.assertEqual(self.calls, [])
        self.assertFalse(self.directory.exists())

    def test_runtime_drift_keeps_incomplete_failure_and_both_reports(self):
        self.change_identity = True
        with patch.object(transfer, "validate_evidence", wraps=transfer.validate_evidence) as validate_evidence:
            with self.assertRaisesRegex(experiment.Error, "runtime identity changed"):
                transfer.run(self.args)
        self.assertEqual(validate_evidence.call_count, 0)
        retained = json.loads(self.report_path.read_text())
        self.assertFalse(retained["complete"])
        self.assertIsNotNone(retained["failure"])
        self.assertTrue((self.directory / "development-hint-calibrated-v1.json").is_file())
        with self.assertRaisesRegex(experiment.Error, "Incomplete"):
            transfer.validate_transfer(self.report_path)

    def test_every_method_needs_its_own_successful_protocol(self):
        def disable_next(args, result):
            self.no_protocol = True
        self.after_run = disable_next
        with self.assertRaisesRegex(experiment.Error, "No successful provider protocol"):
            transfer.run(self.args)
        self.assertEqual(len(self.calls), 2)
        self.assertFalse(json.loads(self.report_path.read_text())["complete"])

    def test_verify_rejects_all_failed_provider_evidence_with_null_identity(self):
        self.completed()
        source = json.loads((self.directory / "development-source-v3.json").read_text())
        timeout = source["results"][1]["strategies"]["provider"]
        self.assertEqual(timeout["failure"]["code"], "process_timeout")
        self.assertEqual(timeout["provenance"], {})
        def fail_every_provider(value):
            for item in value["results"]:
                item["strategies"]["provider"] = copy.deepcopy(timeout)
            value["summary"] = benchmark.summarize(value, self.corpus["tasks"])
        self.edit_evidence(fail_every_provider, index=0)
        self.edit_evidence(fail_every_provider, index=1)
        report = json.loads(self.report_path.read_text())
        reports = [json.loads((self.directory / record["path"]).read_text()) for record in report["evidence"]]
        def forge(value):
            value["model_identity"] = None
            value["summary"] = transfer.summarize(reports, value["plan"], self.corpus)
        self.edit_report(forge)
        with self.assertRaisesRegex(experiment.Error, "No successful provider protocol"):
            transfer.validate_transfer(self.report_path)

    def test_changed_source_during_evaluation_prevents_second_method(self):
        def touch(args, result):
            path = self.root / "kanon-inference/runtime.py"
            path.write_bytes(path.read_bytes() + b"\n")
        self.after_run = touch
        with self.assertRaisesRegex(experiment.Error, "Frozen source changed"):
            transfer.run(self.args)
        self.assertEqual(len(self.calls), 1)
        self.assertFalse(json.loads(self.report_path.read_text())["complete"])
        self.assertTrue((self.directory / "development-source-v3.json").is_file())

    def test_saved_report_changed_during_evaluation_is_retained_and_rejected(self):
        def rewrite(args, result):
            saved = json.loads(args.output.read_text())
            saved["total_seconds"] += 1
            self.write(args.output, saved)
        self.after_run = rewrite
        with self.assertRaisesRegex(experiment.Error, "Saved report differs"):
            transfer.run(self.args)
        self.assertEqual(len(self.calls), 1)
        self.assertFalse(json.loads(self.report_path.read_text())["complete"])

    def test_interrupt_preserves_partial_evaluation_and_incomplete_public_report(self):
        with patch.object(benchmark, "evaluate", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                transfer.run(self.args)
        self.assertEqual(json.loads(self.report_path.read_text())["failure"]["code"], "interrupted")
        partial = json.loads((self.directory / "development-source-v3.json").read_text())
        self.assertFalse(partial["complete"])
        self.assertEqual(partial["failure"]["code"], "interrupted")
        self.assertEqual(self.calls, [("train", "provider")])

    def test_existing_output_directory_is_preserved(self):
        self.directory.mkdir()
        marker = self.directory / "existing"
        marker.write_text("keep this\n")
        with self.assertRaisesRegex(experiment.Error, "already exists"):
            transfer.run(self.args)
        self.assertEqual(marker.read_text(), "keep this\n")
        self.assertEqual(self.calls, [])

    def test_public_report_stays_incomplete_until_final_validation_passes(self):
        validate = transfer.validate_transfer
        observed = []
        def inspect(path):
            observed.append(json.loads(self.report_path.read_text())["complete"])
            return validate(path)
        with patch.object(transfer, "validate_transfer", side_effect=inspect):
            self.completed()
        self.assertEqual(observed, [False])
        self.assertFalse(any(path.name.startswith(".kan-transfer-validation-") for path in self.directory.iterdir()))

    def test_final_validation_failure_retains_incomplete_public_report(self):
        def reject(path):
            self.assertFalse(json.loads(self.report_path.read_text())["complete"])
            raise experiment.Error("invalid_experiment", "fixture final validation failure")
        with patch.object(transfer, "validate_transfer", side_effect=reject):
            with self.assertRaisesRegex(experiment.Error, "final validation failure"):
                transfer.run(self.args)
        retained = json.loads(self.report_path.read_text())
        self.assertFalse(retained["complete"])
        self.assertEqual(len(retained["evidence"]), 2)
        self.assertEqual(retained["failure"]["message"], "fixture final validation failure")

    def test_private_candidate_rewritten_before_validation_is_rejected(self):
        validate = transfer.validate_transfer
        def rewrite_before_read(path):
            candidate = json.loads(path.read_text())
            candidate["frozen"]["compiler"]["scope"] = "absolute"
            candidate["frozen"]["compiler"]["path"] = str(self.compiler)
            self.write(path, candidate)
            return validate(path)
        with patch.object(transfer, "validate_transfer", side_effect=rewrite_before_read):
            with self.assertRaisesRegex(experiment.Error, "Validated transfer differs from evaluation"):
                transfer.run(self.args)
        retained = json.loads(self.report_path.read_text())
        self.assertFalse(retained["complete"])
        self.assertEqual(retained["failure"]["message"], "Validated transfer differs from evaluation")

    def test_paired_counts_include_every_boolean_outcome(self):
        left = [{"semantic_correct": value} for value in (True, True, False, False)]
        right = [{"semantic_correct": value} for value in (True, False, True, False)]
        self.assertEqual(transfer.paired(left, right, "semantic_correct"), {
            "denominator": 4, "both_correct": 1, "left_only_correct": 1,
            "right_only_correct": 1, "neither_correct": 1, "left_minus_right": 0})
        with self.assertRaisesRegex(experiment.Error, "matching task denominators"):
            transfer.paired(left, right[:3], "semantic_correct")

    def test_internally_consistent_requests_must_match_between_approaches(self):
        self.completed()
        def replace_requests(value):
            for item in value["results"]:
                for strategy, result in item["strategies"].items():
                    result["request"]["context"] = "def extra : Nat := 1\n"
                    result["request_sha256"] = driver.sha256(driver.canonical_json(result["request"]))
                    if strategy == "provider":
                        result["provenance"]["prompt_sha256"] = driver.sha256(
                            experiment.prompts.build_prompt(result["request"], "source-v3").encode())
                        result["provenance"]["reference_prompt_sha256"] = driver.sha256(
                            experiment.prompts.build_prompt(experiment.scoring.reference_request(result["request"]),
                                                            "source-v3").encode())
        self.edit_evidence(replace_requests, index=1)
        with self.assertRaisesRegex(experiment.Error, "Compiler request differs between approaches"):
            transfer.validate_transfer(self.report_path)

    def test_report_rewritten_during_verification_is_rejected(self):
        self.completed()
        original = experiment.evidence_data
        seen = []
        def rewrite_once(*arguments):
            if not seen:
                seen.append(True)
                self.report_path.write_bytes(self.report_path.read_bytes() + b"\n")
            return original(*arguments)
        with patch.object(experiment, "evidence_data", side_effect=rewrite_once):
            with self.assertRaisesRegex(experiment.Error, "Transfer report changed during verification"):
                transfer.validate_transfer(self.report_path)

    def test_verify_cli_executes_no_evaluation_and_does_not_modify_outputs(self):
        self.completed()
        original = {path.name: path.read_bytes() for path in self.directory.iterdir()}
        with patch.object(benchmark, "run", side_effect=AssertionError("unexpected evaluation")), \
                patch("builtins.print"):
            self.assertEqual(transfer.main(["verify", "--report", str(self.report_path)]), 0)
        self.assertEqual({path.name: path.read_bytes() for path in self.directory.iterdir()}, original)


if __name__ == "__main__":
    unittest.main()
