"""Check frozen prompt selection and worker propagation without loading models."""

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("kanon_prompt_runtime_test", ROOT / "runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
prompts = runtime.prompts
REQUEST = {
    "protocol_version": 1,
    "hint": "Return zéro.",
    "expected_type": "Nat",
    "context": "def unit : Nat := 1\n",
    "declaration": "zero",
    "allowed_axioms": ["Nat"],
    "max_new_tokens": 96,
    "max_candidates": 8,
}


class PromptTests(unittest.TestCase):
    def test_default_prompt_preserves_source_v3_bytes(self):
        expected = (
            "<|im_start|>system\n"
            "You are a helpful programming assistant. Follow the requirement in the comment."
            "<|im_end|>\n<|im_start|>user\n"
            "Complete this functional program. Return only the expression replacing ?.\n"
            "def unit : Nat := 1\n\n-- Return zéro.\n"
            "def zero : Nat := ?<|im_end|>\n<|im_start|>assistant\n"
        ).encode("utf-8")
        self.assertEqual(runtime.build_prompt(REQUEST).encode("utf-8"), expected)
        self.assertEqual(runtime.build_prompt(REQUEST, "source-v3").encode("utf-8"), expected)
        self.assertEqual(runtime.PROMPT_VERSION, "kanon-source-completion-v3")

    def test_primer_uses_only_fixed_train_examples_and_request_fields(self):
        # Deny file access after import, including potential per-request oracle reads.
        with patch("builtins.open", side_effect=AssertionError("unexpected file read")), \
                patch.object(Path, "open", side_effect=AssertionError("unexpected file read")):
            plain = prompts.build_prompt(REQUEST, "kanon-primer-v1")
            enriched = prompts.build_prompt({**REQUEST, "candidates": ["PRIVATE_POOL"],
                                            "tests": "PRIVATE_ORACLE"}, "kanon-primer-v1")
        self.assertEqual(plain, enriched)
        self.assertNotIn("PRIVATE_", enriched)
        self.assertEqual(plain.count("<|im_start|>user\n"), 3)
        self.assertEqual(plain.count("<|im_start|>assistant\n"), 3)
        self.assertIn("subtracts with a floor of zero", plain)
        self.assertIn("let x : Nat := value in body", plain)
        for example in prompts.TRAIN_EXAMPLES:
            self.assertIn(prompts.request_text(example["request"]), plain)
            self.assertIn(example["expression"], plain)
        self.assertIn(prompts.request_text(REQUEST), plain)

    def test_train_derivation_matches_selected_frozen_tasks(self):
        corpus_path = ROOT / "benchmarks" / "challenge-v1.json"
        manifest_path = ROOT / "benchmarks" / "challenge-v1.splits.json"
        corpus_bytes, manifest_bytes = corpus_path.read_bytes(), manifest_path.read_bytes()
        metadata = prompts.TRAIN_DERIVATION
        self.assertEqual(hashlib.sha256(corpus_bytes).hexdigest(), metadata["corpus_sha256"])
        self.assertEqual(hashlib.sha256(manifest_bytes).hexdigest(), metadata["split_manifest_sha256"])
        selected = {task["id"]: task for task in json.loads(corpus_bytes)["tasks"]
                    if task["id"] in ("tariff_3_2", "capacity_5")}
        modules = {item["module_id"]: item["split"]
                   for item in json.loads(manifest_bytes)["modules"]}
        self.assertEqual(metadata["task_ids"], ["tariff_3_2", "capacity_5"])
        self.assertEqual([item["task_id"] for item in prompts.TRAIN_EXAMPLES], metadata["task_ids"])
        for example in prompts.TRAIN_EXAMPLES:
            task = selected[example["task_id"]]
            request = example["request"]
            self.assertEqual(modules[task["module_id"]], "train")
            self.assertEqual(task["source"],
                             f"def {request['declaration']} : {request['expected_type']} := synth "
                             + json.dumps(request["hint"]) + "\n")
            self.assertEqual(request["protocol_version"], 1)
            self.assertEqual(request["context"], "")
            self.assertEqual(request["allowed_axioms"], ["Nat"])
            self.assertEqual(example["expression"], task["candidates"][0])

    def test_primer_wrapper_pins_the_frozen_prompt_profile(self):
        text = (ROOT / "provider-primer").read_text()
        tokens = text.split()
        self.assertIn("--prompt-profile", tokens)
        self.assertEqual(tokens[tokens.index("--prompt-profile") + 1], "kanon-primer-v1")
        for name in prompts.PROFILES:
            if name != "kanon-primer-v1":
                self.assertNotIn(name, text)

    def test_profile_provenance_pins_the_actual_prompt_source(self):
        digest = hashlib.sha256((ROOT / "prompts.py").read_bytes()).hexdigest()
        for profile in prompts.PROFILES:
            metadata = prompts.provenance(profile)
            self.assertEqual(metadata["prompt_profile"], profile)
            self.assertEqual(metadata["prompt_version"], prompts.PROFILES[profile]["version"])
            self.assertEqual(metadata["prompts_code_sha256"], digest)
            self.assertEqual("prompt_training" in metadata, profile == "kanon-primer-v1")
        self.assertEqual(prompts.provenance("kanon-primer-v1")["prompt_training"]["split"], "train")

    def test_isolated_python_loads_trusted_sibling(self):
        code = (
            "import importlib.util,sys; "
            "from pathlib import Path; "
            "p=Path(sys.argv[1]); "
            "assert str(p.parent) not in sys.path; "
            "s=importlib.util.spec_from_file_location('isolated_runtime',p); "
            "m=importlib.util.module_from_spec(s); s.loader.exec_module(m); "
            "assert m.prompts.DEFAULT_PROFILE == 'source-v3'; "
            "assert Path(m.prompts.__file__).resolve() == p.parent/'prompts.py'"
        )
        process = subprocess.run([sys.executable, "-I", "-c", code, str(ROOT / "runtime.py")],
                                 cwd=ROOT.parent, capture_output=True, timeout=10)
        self.assertEqual(process.returncode, 0, process.stderr)


class ArgumentTests(unittest.TestCase):
    def test_defaults_and_independent_profile_selection(self):
        self.assertEqual(runtime.parse_arguments([]), (False, "135m", "source-v3"))
        for worker in ([], ["--worker"]):
            for model in ("135m", "360m"):
                for profile in prompts.PROFILES:
                    for options in (["--profile", model, "--prompt-profile", profile],
                                    ["--prompt-profile", profile, "--profile", model]):
                        self.assertEqual(runtime.parse_arguments(worker + options),
                                         (bool(worker), model, profile))
        self.assertEqual(runtime.parse_arguments(["--profile", "360m"]),
                         (False, "360m", "source-v3"))

    def test_invalid_and_duplicate_options_are_rejected(self):
        cases = [
            ["--prompt-profile"], ["--prompt-profile", "unknown"],
            ["--profile", "unknown"], ["--unexpected", "source-v3"],
            ["--prompt-profile=source-v3"],
            ["--profile", "135m", "--profile", "135m"],
            ["--prompt-profile", "source-v3", "--prompt-profile", "source-v3"],
            ["--prompt-profile", "source-v3", "--prompt-profile", "kanon-primer-v1"],
            ["--worker", "--worker"], ["--profile", "360m", "--worker"],
        ]
        for arguments in cases:
            with self.subTest(arguments=arguments), self.assertRaises(runtime.Failure) as error:
                runtime.parse_arguments(arguments)
            self.assertEqual(error.exception.code, "invalid_request")

    def test_selected_profiles_reach_subprocess_worker(self):
        raw = (json.dumps(REQUEST) + "\n").encode()
        response = {"protocol_version": 1, "candidates": ["0"]}
        for profile in prompts.PROFILES:
            process = Mock(returncode=0)
            process.communicate.return_value = (json.dumps(response).encode(), b"")
            with patch.object(runtime.sys, "argv", ["runtime.py", "--profile", "360m",
                                                     "--prompt-profile", profile]), \
                    patch.object(runtime, "read_request", return_value=(REQUEST, raw)), \
                    patch.object(runtime.subprocess, "Popen", return_value=process) as popen, \
                    patch.object(runtime.signal, "signal"), patch.object(runtime.signal, "alarm"), \
                    patch.object(runtime, "emit") as emit:
                runtime.main()
            self.assertEqual(popen.call_args.args[0],
                             [sys.executable, "-I", str(ROOT / "runtime.py"), "--worker",
                              "--profile", "360m", "--prompt-profile", profile])
            process.communicate.assert_called_once_with(raw, timeout=runtime.WALL_SECONDS - 1)
            emit.assert_called_once_with(response)

    def test_worker_constructs_engine_with_both_profiles(self):
        engine = Mock()
        engine.propose.return_value = {"protocol_version": 1, "candidates": ["0"]}
        with patch.object(runtime.sys, "argv", ["runtime.py", "--worker", "--profile", "360m",
                                                 "--prompt-profile", "kanon-primer-v1"]), \
                patch.object(runtime, "read_request", return_value=(REQUEST, b"request\n")), \
                patch.object(runtime, "Engine", return_value=engine) as factory, \
                patch.object(runtime.resource, "setrlimit"), \
                patch.object(runtime.signal, "signal"), patch.object(runtime.signal, "alarm"), \
                patch.object(runtime, "emit"):
            runtime.main()
        factory.assert_called_once_with("360m", "kanon-primer-v1")
        engine.propose.assert_called_once_with(REQUEST)


class BudgetTests(unittest.TestCase):
    def engine(self, profile, prompt_tokens):
        engine = runtime.Engine.__new__(runtime.Engine)
        engine.prompt_profile = profile
        engine.tokenizer = SimpleNamespace(
            encode=Mock(return_value=SimpleNamespace(ids=[0] * prompt_tokens)),
            decode=Mock(return_value="0"))
        engine.np = SimpleNamespace(argmax=lambda values: values.index(max(values)))
        engine.forward = Mock(side_effect=[([1, 0, 0], []), ([0, 0, 1], [])])
        engine.provenance = {**prompts.provenance(profile),
                             "provider_code_sha256": runtime.sha256(ROOT / "runtime.py")}
        engine.load_seconds = 0.0
        return engine

    def test_prompt_budget_applies_to_both_profiles(self):
        for profile in prompts.PROFILES:
            engine = self.engine(profile, runtime.MAX_PROMPT_TOKENS + 1)
            with self.assertRaises(runtime.Failure) as error:
                engine.propose(REQUEST)
            self.assertEqual(error.exception.code, "prompt_budget")
            engine.forward.assert_not_called()

    def test_exact_prompt_limit_preserves_response_provenance(self):
        for profile in prompts.PROFILES:
            engine = self.engine(profile, runtime.MAX_PROMPT_TOKENS)
            response = engine.propose(REQUEST)
            prompt = prompts.build_prompt(REQUEST, profile)
            self.assertEqual(response["candidates"], ["0"])
            self.assertEqual(response["metrics"]["prompt_tokens"], runtime.MAX_PROMPT_TOKENS)
            self.assertEqual(response["provenance"]["prompt_profile"], profile)
            self.assertEqual(response["provenance"]["prompt_sha256"],
                             hashlib.sha256(prompt.encode()).hexdigest())
            self.assertEqual(response["provenance"]["provider_code_sha256"],
                             runtime.sha256(ROOT / "runtime.py"))

    def test_candidate_budget_still_precedes_inference(self):
        for profile in prompts.PROFILES:
            engine = self.engine(profile, 1)
            engine.tokenizer.encode.side_effect = [SimpleNamespace(ids=[0]),
                                                   SimpleNamespace(ids=[0, 1])]
            with self.assertRaises(runtime.Failure) as error:
                engine.propose({**REQUEST, "max_new_tokens": 1, "candidates": ["natAdd 0 0"]})
            self.assertEqual(error.exception.code, "candidate_budget")
            engine.forward.assert_not_called()


class RequestTests(unittest.TestCase):
    """Chat template markers in request text are rejected for either profile."""

    def test_chat_markers_are_rejected_in_every_request_text_field(self):
        for name in ("hint", "expected_type", "context", "declaration"):
            for marker in runtime.CHAT_MARKERS:
                with self.subTest(field=name, marker=marker):
                    with self.assertRaises(runtime.Failure) as error:
                        runtime.validate_request({**REQUEST, name: REQUEST[name] + marker})
                    self.assertEqual(error.exception.code, "invalid_request")

    def test_chat_markers_are_rejected_in_allowed_axioms(self):
        for marker in runtime.CHAT_MARKERS:
            with self.subTest(marker=marker):
                with self.assertRaises(runtime.Failure) as error:
                    runtime.validate_request({**REQUEST, "allowed_axioms": ["Nat", marker]})
                self.assertEqual(error.exception.code, "invalid_request")

    def test_clean_request_keeps_the_marker_count_of_both_profiles(self):
        self.assertEqual(runtime.validate_request(dict(REQUEST))["declaration"], "zero")
        expected = {"source-v3": (3, 2), "kanon-primer-v1": (7, 6)}
        for profile in prompts.PROFILES:
            prompt = prompts.build_prompt(REQUEST, profile)
            self.assertEqual((prompt.count("<|im_start|>"), prompt.count("<|im_end|>")),
                             expected[profile])


if __name__ == "__main__":
    unittest.main()
