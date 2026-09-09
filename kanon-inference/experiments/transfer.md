# Fixed development transfer comparison

`transfer-v1` compares the existing conditional and hint-calibrated 135M ranking
methods on newly authored development tasks. It fixes the model, `source-v3`
prompt, score definitions, candidate pools, behavior examples and approach order
before running either method. It does not fit parameters or select a winner.

The authorship record states that a same-project AI collaborator authored the
tasks in a separate agent session and reports that it did not read the existing
corpora, candidate pools, model results, prompts or ranking implementations
before completing them. This statement is the author's own disclosure; the
frozen record and its hash are the only evidence for it. The
coordinator knew the earlier results and supplied the supported language fragment,
task count, quality requirements and earlier semantic families to avoid. The
[authorship record](../benchmarks/transfer-v1.authorship.json) documents this
process and its limits. This is task-author separation within one project; it
does not establish external independence, a sealed test or generalization.

All modules belong to the `train` split, used here to mean development data.
The split name does not imply that weights or parameters were trained. There is
no validation or test partition and no automatic promotion based on these
results. The corpus contains only small Nat expressions. Finite examples check
the requested behavior on those inputs, not universal correctness.

| Family | Tasks | Examples |
| --- | ---: | ---: |
| Group rejection | 4 | 24 |
| Ordered selection | 4 | 24 |
| Message fanout | 4 | 24 |
| Pairwise analysis | 4 | 24 |

Each task has its own module, two or three Nat arguments, four candidates and
six examples. Related tasks still share arithmetic patterns. Different semantic
settings do not establish disjoint mathematical templates. Corpus checks
confirmed all 64 candidates type-check, with one passing answer and three
semantic decoys per task. Intended positions are balanced within each family;
no intended answer is the unique longest or sole `let` candidate. Tokenizer-only
preflight found a maximum of 42 candidate tokens and 117 prompt tokens, below
the unchanged limits of 96 and 1,024.

The [plan](transfer-v1.json) and [corpus](../benchmarks/transfer-v1.json) are
frozen with the authorship record, split assignments, compiler binary and
implementation hashes. Each method evaluates the complete corpus against both
unchanged baselines. Every strategy chooses its first compiler-valid proposal
before receiving behavioral feedback. A strategy whose proposal the compiler
rejects moves to its next proposal, so `first_attempt_semantic_correct` can be
lower than `semantic_correct`. In this run every first proposal type-checked
(`first_attempt_type_accepted` 16 of 16 and `rejections` 0 for all six strategy
rows), so the two metrics are equal in every cell of the report. The tables
below report `semantic_correct`. Failed tasks remain in the denominator. The
reports include per-family counts and paired outcomes, including tasks on which
only one method succeeds.

Run from the repository root after installing the provider dependencies and
building the compiler:

```sh
make experiment-transfer TRANSFER_OUTPUT=/tmp/kan-transfer-run
make verify-transfer TRANSFER_REPORT=/tmp/kan-transfer-run/transfer.json
```

The plan requires kernel, Node and Wasmtime. Choose a new output directory for
each run. `transfer.json` starts incomplete before evaluation; an interrupted or
rejected comparison cannot publish a completed result. The saved plan and each
method's detailed report remain beside it for inspection.

Verification checks frozen input bytes, compiler identity, report hashes,
complete task coverage, provider identity, numerical ranking evidence and the
derived summaries. It needs the matching source checkout and compiler binary,
but does not load the model or execute the saved programs again. It establishes
local evidence consistency, not cryptographic authorship or an independent
reproduction of model scores. `check_frozen` binds the loaded benchmark,
experiment, prompts, scoring, splits, synth and transfer modules to the frozen
hashes but not the lazily imported baseline module; the run used the Makefile
invocation from the checkout, where the script directory precedes `PYTHONPATH`.
Binding baseline is a follow-up shared with `experiment.check_frozen`.

The existing challenge corpora, prompts, scoring implementation and historical
results retain their original bytes. The previous ranking selection remains
verifiable on this checkout. The provider default remains conditional scoring
with SmolLM2-135M; this development comparison cannot satisfy the broader
[model-selection contract](../../evaluation-contract.json).

## Recorded comparison, 2026-09-08

The [complete report](../results/transfer-v1-2026-09-08/transfer.json) records:

| Method | Group rejection | Ordered selection | Message fanout | Pairwise analysis | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Candidate order | 1/4 | 1/4 | 1/4 | 1/4 | 4/16 |
| Deterministic baseline | 1/4 | 1/4 | 1/4 | 1/4 | 4/16 |
| Conditional 135M | 0/4 | 0/4 | 1/4 | 0/4 | 1/16 |
| Hint-calibrated 135M | 1/4 | 0/4 | 3/4 | 0/4 | 4/16 |

The model methods both succeeded on one task. Calibrated scoring alone succeeded
on three, conditional scoring alone on none, and both failed on twelve. Each
method's selected terms all type-checked, with zero disagreements between kernel,
Node and Wasmtime. All failures were semantic mismatches. No strategy used a
second attempt. Baseline results were the same in both runs. These measurements
provide no evidence that calibrated scoring beats either baseline on this corpus.

The run executed from `~/Documents/kanon-inference`, with reports initially
written into the isolated implementation workspace before being staged here.
Recorded source and provider paths describe that canonical execution checkout.
The compiler record has root scope and the relative path
`kanon-synth/_build/default/bin/kanon.exe`. Moving the result directory retains
verification when the checkout's frozen source and compiler bytes match.

The [validation record](../../validation-transfer-2026-09-08.json) preserves
commands, source and report hashes, test counts, preflight observations and
execution provenance. To check the saved result from this repository root:

```sh
make verify-transfer TRANSFER_REPORT=kanon-inference/results/transfer-v1-2026-09-08/transfer.json
```
