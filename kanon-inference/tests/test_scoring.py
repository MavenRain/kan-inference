"""Verify calibrated ranking numerics, boundaries and isolation without a model."""

import hashlib
import importlib.util
import itertools
import json
import math
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("kanon_scoring_runtime_test", ROOT / "runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
scoring = runtime.scoring
REQUEST = {
    "protocol_version": 1, "hint": "Return the context value.", "expected_type": "Nat",
    "context": "def value : Nat := 2", "declaration": "answer", "allowed_axioms": ["Nat"],
    "max_new_tokens": 96, "max_candidates": 8, "candidates": ["0", "value"],
}


class Vector(list):
    def __sub__(self, other):
        return Vector(value - other for value in self)


NUMPY = SimpleNamespace(max=max, sum=lambda values, dtype=None: sum(values),
                        exp=lambda values: [math.exp(value) for value in values], float64=float)


def fake_engine(profile="hint-calibrated-v1", prompt_profile="source-v3"):
    engine = runtime.Engine.__new__(runtime.Engine)
    engine.prompt_profile = prompt_profile
    engine.scoring_profile = profile
    engine.tokenizer = SimpleNamespace(encode=Mock(return_value=SimpleNamespace(ids=[0])))
    engine.np = NUMPY
    engine.load_seconds = 0.0
    engine.provenance = {**runtime.prompts.provenance(prompt_profile), **scoring.provenance(profile)}
    engine.forward = Mock()
    return engine


class NumericalTests(unittest.TestCase):
    def test_calibration_can_reverse_generic_candidate_preference(self):
        conditional = [-0.5, -1.0]
        reference = [-0.25, -2.0]
        self.assertEqual(scoring.ranked_indices(scoring.rank_scores(conditional)), [0, 1])
        scores = scoring.rank_scores(conditional, reference, "hint-calibrated-v1")
        self.assertEqual(scores, [-0.25, 1.0])
        self.assertEqual(scoring.ranked_indices(scores), [1, 0])

    def test_equal_calibrated_scores_preserve_pool_order(self):
        scores = scoring.rank_scores([-0.5, -1.0, -2.0], [-1.0, -1.5, -2.5],
                                     "hint-calibrated-v1")
        self.assertEqual(scoring.ranked_indices(scores), [0, 1, 2])

    def test_nonfinite_components_and_difference_are_rejected(self):
        for value in (float("inf"), float("-inf"), float("nan")):
            for profile in scoring.PROFILES:
                with self.subTest(value=value, profile=profile), self.assertRaises(ValueError):
                    scoring.rank_scores([value], [-1.0] if profile != scoring.DEFAULT_PROFILE else None,
                                        profile)
            with self.assertRaisesRegex(ValueError, "nonfinite reference scores"):
                scoring.rank_scores([-1.0], [value], "hint-calibrated-v1")
            with self.assertRaises(ValueError):
                scoring.ranked_indices([value])
        with self.assertRaises(ValueError):
            scoring.rank_scores([1e308], [-1e308], "hint-calibrated-v1")

    def test_reference_must_match_the_selected_rule_and_pool(self):
        for conditional, reference, profile in [
            ([], None, "conditional-v1"), ([-1.0], [-1.0], "conditional-v1"),
            ([-1.0], None, "hint-calibrated-v1"), ([-1.0], [], "hint-calibrated-v1"),
            ([-1.0], [-1.0, -2.0], "hint-calibrated-v1"), ([-1.0], None, "unknown"),
            ([-1.0], [-1.0], "unknown"),
        ]:
            with self.subTest(profile=profile, reference=reference), self.assertRaises(ValueError):
                scoring.rank_scores(conditional, reference, profile)

    def test_mean_logprob_uses_each_candidate_prefix_and_token_count(self):
        engine = fake_engine("conditional-v1")
        cache = [object()]
        first = Vector([math.log(0.75), math.log(0.25)])
        second = Vector([math.log(0.1), math.log(0.9)])
        engine.forward.side_effect = [(first, cache), ([second], []), ([second], [])]
        scores = engine.mean_token_logprobs([9, 8], [[0], [1, 1], [0, 1]])
        expected = [math.log(0.75), (math.log(0.25) + math.log(0.9)) / 2,
                    (math.log(0.75) + math.log(0.9)) / 2]
        for actual, wanted in zip(scores, expected):
            self.assertAlmostEqual(actual, wanted, places=14)
        self.assertEqual(engine.forward.call_args_list[0].args, ([9, 8],))
        self.assertEqual(engine.forward.call_args_list[1].args, ([1], cache, 2))
        self.assertEqual(engine.forward.call_args_list[2].args, ([0], cache, 2))
        self.assertEqual(engine.forward.call_args_list[1].kwargs, {"all_logits": True})

    def test_large_logits_are_stable_and_default_preserves_scores(self):
        engine = fake_engine("conditional-v1")
        logits = Vector([1000.0, 999.0, 998.0])
        tail = Vector([0.2, -0.1, 0.8])
        engine.forward.side_effect = [(logits, []), ([tail], [])]
        scores = engine.mean_token_logprobs([9], [[2], [1, 0]])
        first_normalizer = math.log1p(math.exp(-1) + math.exp(-2))
        second_logprob = -math.log(1 + math.exp(-0.3) + math.exp(0.6))
        expected = [-2 - first_normalizer, (-1 - first_normalizer + second_logprob) / 2]
        for actual, wanted in zip(scores, expected):
            self.assertAlmostEqual(actual, wanted, places=12)
        self.assertEqual(scoring.rank_scores(scores), scores)


class ReferenceTests(unittest.TestCase):
    def test_reference_removes_only_current_hint_without_reads_or_mutation(self):
        original = json.loads(json.dumps(REQUEST))
        with patch("builtins.open", side_effect=AssertionError("unexpected file read")), \
                patch.object(Path, "open", side_effect=AssertionError("unexpected file read")):
            reference = scoring.reference_request(REQUEST)
            for profile in runtime.prompts.PROFILES:
                self.assertEqual(runtime.build_prompt(reference, profile),
                                 runtime.build_prompt({**REQUEST, "hint": ""}, profile))
            metadata = scoring.provenance("hint-calibrated-v1")
        self.assertEqual(REQUEST, original)
        self.assertEqual(reference, {**original, "hint": ""})
        self.assertEqual(metadata["scoring_profile"], "hint-calibrated-v1")

    def test_provenance_pins_scoring_source_and_version(self):
        digest = hashlib.sha256((ROOT / "scoring.py").read_bytes()).hexdigest()
        for profile, settings in scoring.PROFILES.items():
            self.assertEqual(scoring.provenance(profile), {
                "scoring_profile": profile, "scoring_version": settings["version"],
                "scoring_code_sha256": digest,
            })
        self.assertEqual(scoring.scoring_code_hash(), digest)

    def test_isolated_python_loads_only_the_trusted_scoring_sibling(self):
        code = (
            "import importlib.util,sys; from pathlib import Path; p=Path(sys.argv[1]); "
            "assert str(p.parent) not in sys.path; "
            "s=importlib.util.spec_from_file_location('runtime',p); "
            "m=importlib.util.module_from_spec(s); s.loader.exec_module(m); "
            "assert Path(m.scoring.__file__).resolve() == p.parent/'scoring.py'; "
            "assert m.scoring.DEFAULT_PROFILE == 'conditional-v1'"
        )
        process = subprocess.run([sys.executable, "-I", "-c", code, str(ROOT / "runtime.py")],
                                 cwd=ROOT.parent, capture_output=True, timeout=10)
        self.assertEqual(process.returncode, 0, process.stderr)


class RuntimeTests(unittest.TestCase):
    def test_conditional_ranking_uses_one_pass_and_keeps_existing_metrics(self):
        engine = fake_engine("conditional-v1")
        engine.mean_token_logprobs = Mock(return_value=[-0.5, -1.0])
        response = engine.propose(REQUEST)
        self.assertEqual(response["candidates"], REQUEST["candidates"])
        self.assertEqual(response["metrics"]["mode"], "conditional-loglikelihood")
        self.assertEqual(response["metrics"]["mean_token_logprobs"], [-0.5, -1.0])
        self.assertEqual(response["metrics"]["ranking_scores"], [-0.5, -1.0])
        self.assertEqual(response["metrics"]["scored_tokens"], 2)
        self.assertEqual(response["metrics"]["ranked_indices"], [0, 1])
        self.assertNotIn("reference_prompt_sha256", response["provenance"])
        self.assertNotIn("reference_mean_token_logprobs", response["metrics"])
        engine.mean_token_logprobs.assert_called_once_with([0], [[0], [0]])

    def test_calibration_records_both_passes_and_limits_returned_candidates(self):
        for prompt_profile in runtime.prompts.PROFILES:
            engine = fake_engine(prompt_profile=prompt_profile)
            engine.mean_token_logprobs = Mock(side_effect=[[-0.5, -1.0], [-0.25, -2.0]])
            request = {**REQUEST, "max_candidates": 1}
            response = engine.propose(request)
            metrics = response["metrics"]
            self.assertEqual(response["candidates"], ["value"])
            self.assertEqual(metrics["mode"], "hint-calibrated-loglikelihood")
            self.assertEqual(metrics["mean_token_logprobs"], [-0.5, -1.0])
            self.assertEqual(metrics["reference_mean_token_logprobs"], [-0.25, -2.0])
            self.assertEqual(metrics["ranking_scores"], [-0.25, 1.0])
            self.assertEqual(metrics["ranked_indices"], [1, 0])
            self.assertEqual(metrics["scored_tokens"], 4)
            self.assertEqual(metrics["reference_prompt_tokens"], 1)
            self.assertEqual(metrics["generated_tokens"], 0)
            reference = runtime.build_prompt(scoring.reference_request(request), prompt_profile)
            self.assertEqual(response["provenance"]["reference_prompt_sha256"],
                             hashlib.sha256(reference.encode()).hexdigest())
            self.assertEqual(response["provenance"]["prompt_sha256"],
                             hashlib.sha256(runtime.build_prompt(request, prompt_profile).encode()).hexdigest())
            self.assertEqual(engine.mean_token_logprobs.call_count, 2)

    def test_empty_hint_produces_ties_with_identical_prompt_passes(self):
        engine = fake_engine()
        engine.mean_token_logprobs = Mock(return_value=[-0.5, -1.0])
        response = engine.propose({**REQUEST, "hint": ""})
        self.assertEqual(response["metrics"]["ranking_scores"], [0.0, 0.0])
        self.assertEqual(response["metrics"]["ranked_indices"], [0, 1])
        self.assertEqual(response["provenance"]["prompt_sha256"],
                         response["provenance"]["reference_prompt_sha256"])

    def test_calibration_preserves_candidate_and_reference_token_budgets(self):
        for candidate_tokens, reference_tokens, code in (
            (0, 1, "candidate_budget"), (97, 1, "candidate_budget"),
            (1, runtime.MAX_PROMPT_TOKENS + 1, "prompt_budget"),
        ):
            engine = fake_engine()
            engine.tokenizer.encode.side_effect = [SimpleNamespace(ids=[0]),
                                                    SimpleNamespace(ids=[0] * candidate_tokens),
                                                    SimpleNamespace(ids=[0] * reference_tokens)]
            with self.subTest(code=code), self.assertRaises(runtime.Failure) as error:
                engine.propose({**REQUEST, "candidates": ["0"]})
            self.assertEqual(error.exception.code, code)
            engine.forward.assert_not_called()

    def test_exact_reference_prompt_token_limit_is_accepted(self):
        engine = fake_engine()
        reference_ids = [0] * runtime.MAX_PROMPT_TOKENS
        engine.tokenizer.encode.side_effect = [SimpleNamespace(ids=[0]), SimpleNamespace(ids=[0]),
                                                SimpleNamespace(ids=reference_ids)]
        engine.mean_token_logprobs = Mock(return_value=[-1.0])
        response = engine.propose({**REQUEST, "candidates": ["0"]})
        self.assertEqual(response["metrics"]["reference_prompt_tokens"], runtime.MAX_PROMPT_TOKENS)
        self.assertEqual(engine.mean_token_logprobs.call_args.args, (reference_ids, [[0]]))

    def test_nonfinite_component_or_difference_is_a_protocol_failure(self):
        for conditional, reference in (([float("nan"), -1.0], [-1.0, -1.0]),
                                       ([-1.0, -1.0], [-1.0, float("inf")]),
                                       ([1e308, -1.0], [-1e308, -1.0])):
            engine = fake_engine()
            engine.mean_token_logprobs = Mock(side_effect=[conditional, reference])
            with self.assertRaises(runtime.Failure) as error:
                engine.propose(REQUEST)
            self.assertEqual(error.exception.code, "nonfinite_logits")

    def test_calibrated_generation_fails_before_tokenization(self):
        engine = fake_engine()
        request = {name: value for name, value in REQUEST.items() if name != "candidates"}
        with self.assertRaises(runtime.Failure) as error:
            engine.propose(request)
        self.assertEqual(error.exception.code, "invalid_request")
        engine.tokenizer.encode.assert_not_called()
        engine.forward.assert_not_called()

    def test_unknown_scoring_profile_is_rejected_before_any_model_path_work(self):
        with self.assertRaises(runtime.Failure) as error:
            runtime.Engine("135m", "source-v3", "unknown-v1")
        self.assertEqual(error.exception.code, "invalid_profile")
        message = str(error.exception)
        self.assertEqual(message, "scoring profile must be conditional-v1 or hint-calibrated-v1")
        for profile in scoring.PROFILES:
            self.assertIn(profile, message)

    def test_existing_deadline_interrupts_reference_inference(self):
        engine = fake_engine()
        engine.mean_token_logprobs = Mock(side_effect=[[-1.0, -2.0], runtime.Failure("timeout", "deadline")])
        with self.assertRaises(runtime.Failure) as error:
            engine.propose(REQUEST)
        self.assertEqual(error.exception.code, "timeout")


class ArgumentTests(unittest.TestCase):
    def test_scoring_option_is_independent_of_model_and_prompt(self):
        for model, prompt, profile in itertools.product(("135m", "360m"), runtime.prompts.PROFILES,
                                                         scoring.PROFILES):
            options = [["--profile", model], ["--prompt-profile", prompt], ["--scoring-profile", profile]]
            for order in itertools.permutations(options):
                arguments = [item for option in order for item in option]
                self.assertEqual(runtime.parse_arguments(arguments), (False, model, prompt, profile))
                self.assertEqual(runtime.parse_arguments(["--worker", *arguments]),
                                 (True, model, prompt, profile))

    def test_invalid_missing_and_duplicate_scoring_option_is_rejected(self):
        for arguments in (["--scoring-profile"], ["--scoring-profile", "unknown"],
                          ["--scoring-profile", "conditional-v1", "--scoring-profile", "hint-calibrated-v1"]):
            with self.assertRaises(runtime.Failure) as error:
                runtime.parse_arguments(arguments)
            self.assertEqual(error.exception.code, "invalid_request")

    def test_calibrated_wrapper_pins_its_profile(self):
        wrapper = ROOT / "provider-calibrated"
        self.assertTrue(wrapper.stat().st_mode & 0o111)
        tokens = wrapper.read_text().split()
        self.assertEqual(tokens[tokens.index("--scoring-profile") + 1], "hint-calibrated-v1")

    def test_calibrated_worker_refuses_a_missing_pool_without_building_an_engine(self):
        request = {name: value for name, value in REQUEST.items() if name != "candidates"}
        raw = (json.dumps(request) + "\n").encode()
        arguments = ["runtime.py", "--worker", "--scoring-profile", "hint-calibrated-v1"]
        with patch.object(runtime.sys, "argv", arguments), \
                patch.object(runtime, "read_request", return_value=(request, raw)), \
                patch.object(runtime, "Engine") as factory, \
                patch.object(runtime.resource, "setrlimit"), \
                patch.object(runtime.signal, "signal"), patch.object(runtime.signal, "alarm"), \
                patch.object(runtime, "emit") as emit:
            runtime.main()
        self.assertEqual(emit.call_args.args[0]["error"],
                         {"code": "invalid_request",
                          "message": "hint-calibrated scoring requires candidates"})
        factory.assert_not_called()

    def test_calibrated_parent_refuses_a_missing_pool_without_spawning_a_worker(self):
        request = {name: value for name, value in REQUEST.items() if name != "candidates"}
        raw = (json.dumps(request) + "\n").encode()
        arguments = ["runtime.py", "--scoring-profile", "hint-calibrated-v1"]
        with patch.object(runtime.sys, "argv", arguments), \
                patch.object(runtime, "read_request", return_value=(request, raw)), \
                patch.object(runtime.subprocess, "Popen") as popen, \
                patch.object(runtime.signal, "signal"), patch.object(runtime.signal, "alarm"), \
                patch.object(runtime, "emit") as emit:
            runtime.main()
        self.assertEqual(emit.call_args.args[0]["error"],
                         {"code": "invalid_request",
                          "message": "hint-calibrated scoring requires candidates"})
        popen.assert_not_called()

    def test_calibrated_option_reaches_worker_and_engine(self):
        raw = (json.dumps(REQUEST) + "\n").encode()
        response = {"protocol_version": 1, "candidates": ["0"]}
        process = Mock(returncode=0)
        process.communicate.return_value = (json.dumps(response).encode(), b"")
        arguments = ["runtime.py", "--scoring-profile", "hint-calibrated-v1"]
        with patch.object(runtime.sys, "argv", arguments), \
                patch.object(runtime, "read_request", return_value=(REQUEST, raw)), \
                patch.object(runtime.subprocess, "Popen", return_value=process) as popen, \
                patch.object(runtime.signal, "signal"), patch.object(runtime.signal, "alarm"), \
                patch.object(runtime, "emit") as emit:
            runtime.main()
        self.assertEqual(popen.call_args.args[0][-2:], ["--scoring-profile", "hint-calibrated-v1"])
        process.communicate.assert_called_once_with(raw, timeout=runtime.WALL_SECONDS - 1)
        emit.assert_called_once_with(response)
        engine = Mock()
        engine.propose.return_value = response
        with patch.object(runtime.sys, "argv", [arguments[0], "--worker", *arguments[1:]]), \
                patch.object(runtime, "read_request", return_value=(REQUEST, raw)), \
                patch.object(runtime, "Engine", return_value=engine) as factory, \
                patch.object(runtime.resource, "setrlimit"), \
                patch.object(runtime.signal, "signal"), patch.object(runtime.signal, "alarm"), \
                patch.object(runtime, "emit"):
            runtime.main()
        factory.assert_called_once_with("135m", "source-v3", "hint-calibrated-v1")
        engine.propose.assert_called_once_with(REQUEST)


if __name__ == "__main__":
    unittest.main()
