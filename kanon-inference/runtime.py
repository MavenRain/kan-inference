#!/usr/bin/env python3
"""A bounded, offline, untrusted Kanon term proposer using pinned ONNX data."""

import hashlib
import json
import math
import os
from pathlib import Path
import platform
import resource
import signal
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent
MODEL_DIR = ROOT / "models" / "SmolLM2-135M-Instruct-int8"
MODEL_ID = "HuggingFaceTB/SmolLM2-135M-Instruct"
REVISION = "12fd25f77366fa6b3b4b768ec3050bf629380bac"
MODEL_SHA256 = "a7c33f9ef85d06734cc9d1f943f7e2ba57c77e769df727f4d3e217d9f672b0cc"
TOKENIZER_SHA256 = "9ca9acddb6525a194ec8ac7a87f24fbba7232a9a15ffa1af0c1224fcd888e47c"
MAX_REQUEST_BYTES = 65536
MAX_RESPONSE_BYTES = 65536
MAX_PROMPT_TOKENS = 1024
MAX_NEW_TOKENS = 96
MAX_CANDIDATES = 8
MAX_CANDIDATE_BYTES = 2048
WALL_SECONDS = 60
PROMPT_VERSION = "kanon-source-completion-v3"


class Failure(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def failure(code, message):
    return {"protocol_version": 1, "error": {"code": code, "message": message}}


def emit(value):
    print(json.dumps(value, ensure_ascii=True, allow_nan=False, separators=(",", ":")), flush=True)


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Failure("invalid_request", f"duplicate JSON key: {key}")
        result[key] = value
    return result


def validate_request(value):
    if not isinstance(value, dict):
        raise Failure("invalid_request", "request must be a JSON object")
    allowed = {
        "protocol_version", "hint", "expected_type", "context", "declaration",
        "max_new_tokens", "max_candidates", "candidates", "allowed_axioms",
    }
    if set(value) - allowed:
        raise Failure("invalid_request", "unknown request fields")
    if type(value.get("protocol_version")) is not int or value["protocol_version"] != 1:
        raise Failure("invalid_request", "protocol_version must be 1")
    for name, limit in (("hint", 4096), ("expected_type", 4096), ("context", 32768), ("declaration", 256)):
        item = value.get(name)
        if not isinstance(item, str) or len(item.encode("utf-8")) > limit or "\0" in item:
            raise Failure("invalid_request", f"{name} must be bounded text without NUL")
    if not value["expected_type"].strip():
        raise Failure("invalid_request", "expected_type must be nonempty")
    axioms = value.get("allowed_axioms", [])
    if not isinstance(axioms, list) or len(axioms) > 64 or any(
        not isinstance(item, str) or len(item.encode("utf-8")) > 256 for item in axioms
    ):
        raise Failure("invalid_request", "allowed_axioms must be a bounded array of names")
    for name, default in (("max_new_tokens", MAX_NEW_TOKENS), ("max_candidates", MAX_CANDIDATES)):
        item = value.get(name, default)
        if type(item) is not int or not 1 <= item <= default:
            raise Failure("invalid_request", f"{name} must be an integer between 1 and {default}")
        value[name] = item
    if "candidates" in value:
        candidates = value["candidates"]
        if not isinstance(candidates, list) or not 1 <= len(candidates) <= MAX_CANDIDATES:
            raise Failure("invalid_request", "candidates must contain 1 to 8 expressions")
        for item in candidates:
            if (
                not isinstance(item, str) or not item.strip() or "\0" in item
                or len(item.encode("utf-8")) > MAX_CANDIDATE_BYTES
            ):
                raise Failure("invalid_request", "each candidate must be a bounded nonempty expression")
        if len(set(candidates)) != len(candidates):
            raise Failure("invalid_request", "candidate expressions must be distinct")
    return value


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_prompt(request):
    context = request["context"]
    user = (
        "Complete this functional program. Return only the expression replacing ?.\n"
        f"{context}\n-- {request['hint']}\n"
        f"def {request['declaration']} : {request['expected_type']} := ?"
    )
    system = "You are a helpful programming assistant. Follow the requirement in the comment."
    # This is the fixed publisher ChatML layout, not executable remote template code.
    return (
        f"<|im_start|>system\n{system}<|im_end|>\n"
        f"<|im_start|>user\n{user}<|im_end|>\n<|im_start|>assistant\n"
    )


class Engine:
    def __init__(self, profile="135m"):
        self.started = time.monotonic()
        if profile == "135m":
            model_id, revision, expected_sha, model_dir = MODEL_ID, REVISION, MODEL_SHA256, MODEL_DIR
        elif profile == "360m":
            model_id = "HuggingFaceTB/SmolLM2-360M-Instruct"
            revision = "a10cc1512eabd3dde888204e902eca88bddb4951"
            expected_sha = "cb7375a212a6583cbd96eaa739142f3a1a0d17cbd51043c60f081ea5ce6d21e3"
            model_dir = ROOT / "models" / "SmolLM2-360M-Instruct-int8"
        else:
            raise Failure("invalid_profile", "model profile must be 135m or 360m")
        model_path = model_dir / "onnx" / "model_int8.onnx"
        tokenizer_path = model_dir / "tokenizer.json"
        if not model_path.is_file() or not tokenizer_path.is_file():
            raise Failure("model_missing", "Run download_model.py to install the pinned model data.")
        if sha256(model_path) != expected_sha or sha256(tokenizer_path) != TOKENIZER_SHA256:
            raise Failure("model_integrity", "Pinned model or tokenizer SHA-256 does not match.")
        os.environ["ORT_DISABLE_TELEMETRY"] = "1"
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
        os.environ["TOKENIZERS_PARALLELISM"] = "false"
        import numpy as np
        import onnxruntime as ort
        import tokenizers

        ort.disable_telemetry_events()
        self.np = np
        self.tokenizer = tokenizers.Tokenizer.from_file(str(tokenizer_path))
        options = ort.SessionOptions()
        options.intra_op_num_threads = 4
        options.inter_op_num_threads = 1
        options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        options.log_severity_level = 3
        self.session = ort.InferenceSession(str(model_path), options, providers=["CPUExecutionProvider"])
        self.session.disable_fallback()
        self.cache_names = [item.name for item in self.session.get_inputs() if item.name.startswith("past_key_values.")]
        self.cache_shapes = [(1, item.shape[1], 0, item.shape[3]) for item in self.session.get_inputs() if item.name.startswith("past_key_values.")]
        self.output_names = ["logits"] + [name.replace("past_key_values.", "present.") for name in self.cache_names]
        self.provenance = {
            "model_id": model_id, "revision": revision, "sha256": expected_sha,
            "tokenizer_sha256": TOKENIZER_SHA256, "backend": "onnxruntime-cpu",
            "backend_version": ort.__version__, "tokenizers_version": tokenizers.__version__,
            "numpy_version": np.__version__, "quantization": "publisher-onnx-int8",
            "model_size_bytes": model_path.stat().st_size,
            "tokenizer_size_bytes": tokenizer_path.stat().st_size,
            "prompt_version": PROMPT_VERSION, "cpu_threads": 4,
            "python": platform.python_version(), "platform": platform.platform(),
            "provider_code_sha256": sha256(Path(__file__).resolve()),
        }
        self.load_seconds = time.monotonic() - self.started

    def forward(self, ids, cache=None, past_length=0, all_logits=False):
        np = self.np
        feeds = {
            "input_ids": np.asarray([ids], dtype=np.int64),
            "attention_mask": np.ones((1, past_length + len(ids)), dtype=np.int64),
            "position_ids": np.arange(past_length, past_length + len(ids), dtype=np.int64)[None, :],
        }
        if cache is None:
            cache = [np.empty(shape, dtype=np.float32) for shape in self.cache_shapes]
        feeds.update(zip(self.cache_names, cache))
        outputs = self.session.run(self.output_names, feeds)
        return outputs[0][0] if all_logits else outputs[0][0, -1], outputs[1:]

    def propose(self, request):
        started = time.monotonic()
        prompt = build_prompt(request)
        prompt_ids = self.tokenizer.encode(prompt, add_special_tokens=False).ids
        if len(prompt_ids) > MAX_PROMPT_TOKENS:
            raise Failure("prompt_budget", f"prompt has {len(prompt_ids)} tokens; maximum is {MAX_PROMPT_TOKENS}")
        np = self.np
        if "candidates" in request:
            candidate_ids = [self.tokenizer.encode(candidate, add_special_tokens=False).ids for candidate in request["candidates"]]
            for ids in candidate_ids:
                if not ids or len(ids) > request["max_new_tokens"]:
                    raise Failure("candidate_budget", "candidate exceeds the requested token budget")
            logits, cache = self.forward(prompt_ids)
            scores = []
            for ids in candidate_ids:
                continuation = [logits]
                if len(ids) > 1:
                    tail_logits, _ = self.forward(ids[:-1], cache, len(prompt_ids), all_logits=True)
                    continuation.extend(tail_logits)
                token_scores = []
                for distribution, token in zip(continuation, ids):
                    maximum = float(np.max(distribution))
                    normalizer = maximum + math.log(float(np.sum(np.exp(distribution - maximum), dtype=np.float64)))
                    token_scores.append(float(distribution[token]) - normalizer)
                scores.append(sum(token_scores) / len(token_scores))
            if not all(math.isfinite(score) for score in scores):
                raise Failure("nonfinite_logits", "model produced nonfinite choice scores")
            order = sorted(range(len(scores)), key=lambda index: (-scores[index], index))
            candidates = [request["candidates"][index] for index in order[:request["max_candidates"]]]
            detail = {
                "mode": "conditional-loglikelihood", "mean_token_logprobs": scores,
                "ranked_indices": order, "generated_tokens": 0,
                "scored_tokens": sum(len(ids) for ids in candidate_ids),
            }
        else:
            generated = []
            logits, cache = self.forward(prompt_ids)
            stopped = False
            for _ in range(request["max_new_tokens"]):
                token = int(np.argmax(logits))
                if token == 2:
                    stopped = True
                    break
                generated.append(token)
                if len(generated) < request["max_new_tokens"]:
                    logits, cache = self.forward([token], cache, len(prompt_ids) + len(generated) - 1)
            expression = self.tokenizer.decode(generated, skip_special_tokens=True).strip()
            if not stopped:
                raise Failure("generation_budget", "model reached the token limit before ending its expression")
            if not expression or len(expression.encode("utf-8")) > MAX_CANDIDATE_BYTES:
                raise Failure("empty_or_oversize_candidate", "model output was empty or exceeded the expression byte limit")
            candidates = [expression]
            detail = {"mode": "greedy-generation", "generated_tokens": len(generated), "stopped_on_eos": stopped}
        max_rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        peak_bytes = max_rss if sys.platform == "darwin" else max_rss * 1024
        return {
            "protocol_version": 1, "candidates": candidates,
            "provenance": {**self.provenance, "decoding": detail["mode"], "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest()},
            "metrics": {
                "load_seconds": self.load_seconds, "inference_seconds": time.monotonic() - started,
                "prompt_tokens": len(prompt_ids), "peak_rss_bytes": peak_bytes, **detail,
            },
        }


def read_request():
    line = sys.stdin.buffer.readline(MAX_REQUEST_BYTES + 1)
    if len(line) > MAX_REQUEST_BYTES:
        raise Failure("request_budget", "request exceeds 65536 bytes")
    if not line.endswith(b"\n"):
        raise Failure("invalid_request", "request must be one newline-terminated JSON object")
    try:
        value = json.loads(line.decode("utf-8"), object_pairs_hook=no_duplicate_keys)
    except (UnicodeError, ValueError, RecursionError) as error:
        raise Failure("invalid_request", "request is not bounded valid UTF-8 JSON") from error
    return validate_request(value), line


def deadline(_signal, _frame):
    raise Failure("timeout", "local provider exceeded its 60-second deadline")


def main():
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(WALL_SECONDS)
    try:
        request, raw = read_request()
        arguments = sys.argv[1:]
        worker = bool(arguments and arguments[0] == "--worker")
        if worker:
            arguments = arguments[1:]
        if not arguments:
            profile = "135m"
        elif len(arguments) == 2 and arguments[0] == "--profile" and arguments[1] in ("135m", "360m"):
            profile = arguments[1]
        else:
            raise Failure("invalid_request", "valid arguments are --profile 135m or --profile 360m")
        if worker:
            resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
            resource.setrlimit(resource.RLIMIT_CPU, (WALL_SECONDS, WALL_SECONDS))
            emit(Engine(profile).propose(request))
        else:
            # A separate process makes the deadline cover native inference calls.
            process = subprocess.Popen(
                [sys.executable, "-I", str(Path(__file__).resolve()), "--worker", "--profile", profile],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                cwd=ROOT,
            )
            try:
                stdout, stderr = process.communicate(raw, timeout=WALL_SECONDS - 1)
            except (subprocess.TimeoutExpired, Failure):
                process.kill()
                process.communicate()
                raise Failure("timeout", "local provider exceeded its 60-second deadline")
            if stderr:
                sys.stderr.buffer.write(stderr[:8192])
            if process.returncode != 0:
                raise Failure("worker_failed", f"inference worker exited with status {process.returncode}")
            if len(stdout) > MAX_RESPONSE_BYTES:
                raise Failure("response_budget", "worker response exceeded 65536 bytes")
            try:
                response = json.loads(stdout)
            except (ValueError, UnicodeError) as error:
                raise Failure("worker_failed", "inference worker returned malformed JSON") from error
            emit(response)
    except Failure as error:
        emit(failure(error.code, str(error)))
    except Exception as error:
        print(f"{type(error).__name__}: {error}", file=sys.stderr)
        emit(failure("inference_failed", f"{type(error).__name__}: local inference failed"))
    finally:
        signal.alarm(0)


if __name__ == "__main__":
    main()
