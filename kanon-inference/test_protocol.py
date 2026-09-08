#!/usr/bin/env python3
"""Exercise malformed-input failures without loading a model."""

import json
from pathlib import Path
import subprocess
import unittest


PROVIDER = Path(__file__).resolve().parent / "provider"
VALID = {"protocol_version": 1, "hint": "Return zero.", "expected_type": "Nat", "context": "", "declaration": "zero"}


class ProtocolTests(unittest.TestCase):
    def assert_failure(self, raw, code, arguments=(), provider=PROVIDER):
        process = subprocess.run([str(provider), *arguments], input=raw, capture_output=True, timeout=10)
        self.assertEqual(process.returncode, 0, process.stderr)
        response = json.loads(process.stdout)
        self.assertEqual(response["error"]["code"], code, response)
        self.assertNotIn("candidates", response)

    def test_duplicate_goal_is_rejected(self):
        raw = json.dumps(VALID)[:-1] + ',"expected_type":"False"}\n'
        self.assert_failure(raw.encode(), "invalid_request")

    def test_bool_is_not_a_protocol_version(self):
        self.assert_failure((json.dumps({**VALID, "protocol_version": True}) + "\n").encode(), "invalid_request")

    def test_remote_model_override_is_rejected(self):
        self.assert_failure((json.dumps({**VALID, "model_id": "some/other-model"}) + "\n").encode(), "invalid_request")

    def test_token_budget_cannot_be_increased(self):
        self.assert_failure((json.dumps({**VALID, "max_new_tokens": 97}) + "\n").encode(), "invalid_request")

    def test_request_byte_limit(self):
        self.assert_failure(b" " * 65537 + b"\n", "request_budget")

    def test_duplicate_candidates_are_rejected(self):
        self.assert_failure((json.dumps({**VALID, "candidates": ["0", "0"]}) + "\n").encode(), "invalid_request")

    def test_missing_newline_is_rejected(self):
        self.assert_failure(json.dumps(VALID).encode(), "invalid_request")

    def test_invalid_prompt_profile_is_rejected_before_model_load(self):
        self.assert_failure((json.dumps(VALID) + "\n").encode(), "invalid_request",
                            ["--prompt-profile", "unknown"])

    def test_duplicate_prompt_profile_is_rejected_before_model_load(self):
        self.assert_failure((json.dumps(VALID) + "\n").encode(), "invalid_request",
                            ["--prompt-profile", "source-v3", "--prompt-profile", "source-v3"])

    def test_primer_wrapper_rejects_a_second_prompt_profile_option(self):
        """The wrapper adds its own profile, so a forwarded profile is a duplicate.

        This does not pin the wrapper's profile string. experiment.provider_identity
        enforces the recorded profile at run time, and tests/test_prompts.py checks
        the wrapper bytes.
        """
        self.assert_failure((json.dumps(VALID) + "\n").encode(), "invalid_request",
                            ["--prompt-profile", "source-v3"],
                            provider=PROVIDER.with_name("provider-primer"))


if __name__ == "__main__":
    unittest.main()
