This directory implements the local, untrusted model proposer for the Kanon synthesis prototype. The compiler driver freezes the expected type and context, checks proposed terms, and materializes accepted ordinary code. This provider only proposes expressions. It never checks proofs, executes generated code, or edits the context.

The default executable is `provider`, using SmolLM2-135M-Instruct. `provider360` selects SmolLM2-360M-Instruct. These are explicit experimental profiles. Neither is certified as the smallest useful model. The 135M development observations in [development-history.json](development-history.json) include failures to select the requested number and argument. Independent results go in `results/`.

The frozen six-case smoke evaluation completed for both profiles. Each scored 4/6 exact-intent matches; choosing the first pool expression scored 3/6. Both models selected seven and three correctly under different hints with the same `["3", "7"]` pool. Both selected the later argument but missed the earlier argument and increment task. The larger model showed no accuracy improvement in this small comparison, so the default remains 135M. Neither profile meets the proposed 80% success gate on this pilot.

| Pilot result | 135M | 360M |
| --- | --- | --- |
| Intent matches | 4/6 | 4/6 |
| Provider failures | 0 | 0 |
| Median cold end-to-end time | 14.24 seconds | 12.75 seconds |
| Cold elapsed range | 11.27 to 15.11 seconds | 8.28 to 24.44 seconds |
| Highest process peak RSS observed | 624,197,632 bytes | 1,018,609,664 bytes |

These timings reflect a shared development machine, not a controlled benchmark. The artifacts preserve each request, model scores, provenance and separate load/inference timing: [135M observations](results/smoke-135m.json) and [360M observations](results/smoke-360m.json).

The model runs on the local CPU through ONNX Runtime, without a required server or inference API. This is the native inference portion of a Wasm-powered CLI experiment. It does not establish browser inference or a compiler fully running inside Wasm.

| Profile | Pinned publisher revision | ONNX weight artifact |
| --- | --- | --- |
| 135M | `12fd25f77366fa6b3b4b768ec3050bf629380bac` | 137,147,867 bytes, int8 |
| 360M | `a10cc1512eabd3dde888204e902eca88bddb4951` | 364,564,558 bytes, int8 |

Both profiles use a 2,104,556-byte tokenizer. The initial measured 135M model directory occupied 139,258,301 bytes including configuration and manifest; the pinned Python environment occupied 127,781,308 bytes. Package download cache is additional development storage. These figures are installed prototype artifacts, not an optimized distribution size or an all-4-bit theoretical payload.

Set up inside this directory:

```sh
python3.12 -I -m venv .venv
uv pip install --python .venv/bin/python --cache-dir .cache/uv --only-binary :all: -r requirements.lock
python3.12 -I download_model.py
python3.12 -I download_model.py --profile 360m
```

Downloads use the pinned publisher URLs and verify their exact sizes and publisher file digests. Only ONNX, tokenizer JSON and configuration data are fetched. Model and tokenizer SHA-256 hashes are checked again before every model load. Installation stays in this directory. The runtime uses local paths, disables telemetry, and does not load custom operators, executable model repository code, Python pickles or remote templates. The weight directories and virtual environment are ignored by Git.

Send one newline-terminated JSON object to either executable:

```json
{"protocol_version":1,"hint":"Return the second argument.","expected_type":"(left : Nat) -> (right : Nat) -> Nat","context":"","declaration":"choose","max_new_tokens":96,"max_candidates":8,"allowed_axioms":[],"candidates":["fun (left : Nat) (right : Nat) => left","fun (left : Nat) (right : Nat) => right"]}
```

`candidates` is optional. When supplied, the model ranks exactly those expressions by mean conditional token log likelihood under the frozen source-completion prompt. The returned ordering comes from model scores; ties preserve input order. The provider does not contain an intent heuristic or silently fall back to a fixture. Candidate likelihoods have length and tokenization biases, so their ordering is an experiment, not a semantic guarantee. Model acceptance through the kernel only establishes the declared formal type and dependency policy, which may not fully encode the hint.

Without a pool, the model generates a proposed expression greedily until its end token. Reaching the token cap is an explicit failure. The provider preserves the output as text for the compiler's restricted decoder. Explanations, declarations and malformed syntax must be rejected at that boundary. Direct generation is implemented but unsuccessful in the recorded probes. The final identity probe produced `def identity : (A : Type 0) -> A := ?`, a declaration with an unresolved hole, rather than an expression for the requested dependent identity type. That output must be rejected by the compiler. Its full response and provenance are in [direct-identity-135m.json](results/direct-identity-135m.json); generation used 14 tokens and the cold request took 27.87 seconds.

Responses contain `protocol_version`, `candidates`, `provenance` and `metrics`. Provenance includes the model revision, model/tokenizer hashes, runtime versions, quantization, prompt hash and provider source hash. Metrics include model-load time, inference time, scores, prompt tokens and process peak RSS. A failure contains `error.code` and `error.message` and has no candidates. Stdout is reserved for one JSON response; runtime diagnostics use stderr.

The default prompt profile is `source-v3`, preserving the original prompt bytes.
`provider-primer` selects `kanon-primer-v1`, with a Kanon syntax explanation and
the fixed train demonstrations `tariff_3_2` and `capacity_5`. The equivalent
option is `provider --prompt-profile kanon-primer-v1`; it can be combined with
`--profile 360m` for a separate experiment. Unknown or duplicate options are
errors. Prompt selection does not change likelihood scoring or resource limits.
Provenance also records the prompt profile, the hash of `prompts.py`, and the
primer's training task IDs and frozen corpus hashes. See the
[experiment procedure](experiments/README.md) for validation selection and test
replay with the default 135M model.

The provider enforces these limits:

- 65,536 request bytes and a 1,024-token model prompt, without silent truncation.
- At most 8 pool expressions, each at most 2,048 UTF-8 bytes and the requested token cap.
- At most 96 new tokens and 8 returned candidates. Direct generation returns one candidate.
- Four inference threads, one inter-op thread and CPU execution only.
- A separate inference worker with a 60-second outer deadline and a CPU-time limit. The compiler driver may impose a shorter timeout. The token and fixed graph limits bound the workload; there is no portable hard RSS limit in this prototype.

Run the protocol tests and small frozen smoke comparison:

```sh
.venv/bin/python -I test_protocol.py
.venv/bin/python -I evaluate.py --corpus smoke-corpus.json --provider provider --output results/smoke-135m.json
.venv/bin/python -I evaluate.py --corpus smoke-corpus.json --provider provider360 --output results/smoke-360m.json
```

The six smoke tasks were written after prompt tuning and are independent of the development examples. They are too small to satisfy the 500-task evaluation contract. Their exact-expression intent oracle and first-candidate-order baseline are deliberately disclosed. Kernel validation, Wasm execution agreement, stronger deterministic baselines, warm latency, confidence intervals and task-specific usefulness gates require separate evidence. Each harness request starts a fresh model process, so its end-to-end measurement includes model loading and host contention.

The implementation follows the [official ONNX Runtime inference API](https://onnxruntime.ai/docs/api/python/api_summary.html) and [Tokenizer API](https://huggingface.co/docs/tokenizers/api/tokenizer). Model data and licensing metadata come from the publisher's [135M model](https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct) and [360M model](https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct), both identified by the publisher as Apache 2.0. Retain the applicable model and runtime license notices when preparing a redistributed bundle.

For behavioral evaluation, use the newer [diagnostic benchmark](benchmarks/README.md)
and `benchmark.py` from the repository root. Its [32-task comparison](results/diagnostic-135m-2026-09-07.json)
records 9/32 for the unchanged 135M model, 32/32 for the deterministic baseline
and 8/32 for candidate order, with compiler acceptance and all three execution
hosts checked separately. The older `evaluate.py` above remains the original
six-case exact-expression smoke harness. Neither dataset satisfies the proposed
independent 500-task selection contract.

The next corpus, [challenge-v1](benchmarks/README.md#frozen-challenge-splits),
freezes sources, candidate pools, finite behavior oracles and module/template
splits before any model adaptation. From the repository root, run
`make benchmark-challenge-baseline SPLIT=train` for the deterministic comparison,
or `make benchmark-challenge-135m SPLIT=validation` with the installed provider.
Use `CHALLENGE_OUTPUT=PATH` to choose a fresh report path. The test split is
reserved for evaluating a frozen approach; inspecting or tuning against it must
be disclosed in any later report. The subsequent
[prompt comparison](experiments/README.md) records both train and validation
profiles and the selected test run with the required exposure disclosure.
