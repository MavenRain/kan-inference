"""Frozen source-completion prompts with train-only Kanon demonstrations.

Prompt construction uses these literals and the request alone. Benchmark files,
candidate rankings and behavioral expectations are never read at inference time.
"""

import hashlib
import json
from pathlib import Path


DEFAULT_PROFILE = "source-v3"
PROFILES = {
    "source-v3": {"version": "kanon-source-completion-v3"},
    "kanon-primer-v1": {"version": "kanon-primer-v1"},
}
PROMPTS_CODE_SHA256 = hashlib.sha256(Path(__file__).resolve().read_bytes()).hexdigest()
TRAIN_DERIVATION = {
    "corpus": "challenge-v1",
    "corpus_sha256": "9210f281dc8109c1bbbcc4e1b5fa5b4f9e19b418f6722cb7a736fbd3c9d5d7d8",
    "split_manifest_sha256": "930779ceb4fd081238fdfbdc1e3c36670a9e62d9c6abad1f498d882b62528d6a",
    "split": "train",
    "task_ids": ["tariff_3_2", "capacity_5"],
}
TRAIN_EXAMPLES = (
    {
        "task_id": "tariff_3_2",
        "request": {
            "protocol_version": 1,
            "hint": "An order costs 2 credits before any items are counted, then 3 credits for every item. Compute its bill.",
            "expected_type": "(n : Nat) -> Nat",
            "context": "",
            "declaration": "answer",
            "allowed_axioms": ["Nat"],
        },
        "expression": "fun (n : Nat) => let s : Nat := natMul 3 n in natAdd s 2",
    },
    {
        "task_id": "capacity_5",
        "request": {
            "protocol_version": 1,
            "hint": "There is room for 5 units. Admit as much of the requested amount as fits and discard any overflow.",
            "expected_type": "(n : Nat) -> Nat",
            "context": "",
            "declaration": "answer",
            "allowed_axioms": ["Nat"],
        },
        "expression": "fun (n : Nat) => let excess : Nat := natSub n 5 in natSub n excess",
    },
)
PRIMER = (
    "Complete a Kanon expression from a JSON request. Follow hint and expected_type, "
    "using declarations in context. Return only the expression, without a declaration or explanation.\n"
    "Nat is the type of natural numbers including zero. natAdd a b adds, natMul a b "
    "multiplies, and natSub a b subtracts with a floor of zero. Apply functions with spaces. "
    "Parenthesize nested applications. Write a function as fun (n : Nat) => body. "
    "Write a local binding as let x : Nat := value in body. "
    "The bound name is available in body. Here are two completed requests."
)


def message(role, text):
    return f"<|im_start|>{role}\n{text}<|im_end|>\n"


def request_text(request):
    fields = {key: request[key] for key in (
        "protocol_version", "hint", "expected_type", "context", "declaration"
    )}
    fields["allowed_axioms"] = request.get("allowed_axioms", [])
    return json.dumps(fields, ensure_ascii=True, separators=(",", ":"))


def build_prompt(request, profile=DEFAULT_PROFILE):
    if profile not in PROFILES:
        raise ValueError("unknown prompt profile")
    if profile == "source-v3":
        context = request["context"]
        user = (
            "Complete this functional program. Return only the expression replacing ?.\n"
            f"{context}\n-- {request['hint']}\n"
            f"def {request['declaration']} : {request['expected_type']} := ?"
        )
        system = "You are a helpful programming assistant. Follow the requirement in the comment."
        # Preserve the fixed publisher ChatML layout byte for byte.
        return message("system", system) + message("user", user) + "<|im_start|>assistant\n"
    prompt = message("system", PRIMER)
    for example in TRAIN_EXAMPLES:
        prompt += message("user", request_text(example["request"]))
        prompt += message("assistant", example["expression"])
    return prompt + message("user", request_text(request)) + "<|im_start|>assistant\n"


def provenance(profile=DEFAULT_PROFILE):
    result = {
        "prompt_profile": profile,
        "prompt_version": PROFILES[profile]["version"],
        "prompts_code_sha256": PROMPTS_CODE_SHA256,
    }
    if profile == "kanon-primer-v1":
        result["prompt_training"] = {**TRAIN_DERIVATION,
                                     "task_ids": list(TRAIN_DERIVATION["task_ids"])}
    return result
