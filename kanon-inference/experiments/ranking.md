# Hint-calibrated ranking experiment

The [frozen plan](challenge-ranking-v1.json) compares two scoring methods with
the installed 135M model and the unchanged `source-v3` prompt. `conditional-v1`
uses the existing mean candidate token log-likelihood. `hint-calibrated-v1`
subtracts the candidate's mean token log-likelihood under a reference request
whose hint is empty. The reference keeps the same type, context, declaration
and allowed axioms. It reads no corpus, demonstrations or behavior examples.

For candidate `c` and request `r`, the calibrated score is:

```text
mean_log_probability(c | prompt(r))
  - mean_log_probability(c | prompt(r with hint = ""))
```

Higher scores rank first. Equal scores retain original pool order. There is no
fitted coefficient, learned weight or additional model. The subtraction tests
whether a hint improves a candidate's likelihood over its own reference score.
It does not guarantee that the candidate satisfies the hint. The compiler
checks candidates in ranked order and behavior tests evaluate the first accepted
term, as in the previous experiment.

A request whose hint is already empty makes the reference prompt equal the
conditional prompt. Every calibrated score is then 0.0 and the ranking keeps
pool order. The record marks that case, because `reference_prompt_sha256` then
equals `prompt_sha256`. The frozen corpus contains no such task.

Both prompt evaluations retain the existing prompt and candidate token limits.
Calibrated ranking makes two scoring passes within the same provider deadline.
It rejects requests without a candidate pool. The original provider continues
to support generation and conditional ranking by default.

The response records the conditional and reference means, their differences,
ranked indices, scoring version and code hash, and reference prompt hash.
The experiment binds these to the frozen approach and validates the arithmetic,
order and selected candidate before accepting comparison evidence.

After the existing compiler and provider setup, run from the repository root:

```sh
make experiment-ranking RANKING_OUTPUT=/tmp/challenge-ranking-v1
make experiment-test SELECTION=/tmp/challenge-ranking-v1/selection.json FROZEN_OUTPUT=/tmp/challenge-ranking-test-replay.json
```

Choose fresh output paths. The runner freezes code, model identity, compiler,
corpus and plan, compares both approaches on train and validation, and saves the
validation winner before evaluating it on test. Ties choose `source-v3`, the
first approach in the plan. Failed tasks remain in the denominator. The unchanged
candidate-order and deterministic baselines accompany every report.

The earlier [prompt experiment](README.md) is preserved as historical evidence
from commit `8e2d89e`. Replaying that original selection requires that matching
checkout and its recorded compiler/runtime identity, because the new runtime
and experiment code deliberately have different frozen hashes. Running its
unchanged plan with the current code produces a new evidence bundle.

Every split had prior developer exposure, including the earlier `source-v3`
test score of 0/8. This rule was chosen after that result was known. The new
plan fixes the rule before this comparison and does not tune it after seeing
validation or test scores. These small, correlated tasks cannot establish
independent generalization or satisfy the proposed usefulness contract. Timings
include cold startup and model loading.

The [recorded experiment](../results/challenge-ranking-v1-2026-09-08/experiment.json)
completed on 2026-09-08:

| Approach | Train | Validation | Test |
| --- | ---: | ---: | ---: |
| Candidate order | 2/8 | 2/8 | 2/8 |
| Unchanged deterministic baseline | 2/8 | 2/8 | 2/8 |
| `source-v3` with `conditional-v1` | 3/8 | 3/8 | Not evaluated in this run |
| `source-v3` with `hint-calibrated-v1` | 1/8 | 5/8 | 4/8 |

The [saved selection](../results/challenge-ranking-v1-2026-09-08/selection.json)
chose calibrated scoring from validation alone, despite its lower train score.
Its test score exceeded both unchanged baselines on these eight tasks. All
selected terms type-checked and kernel, Node and Wasmtime agreed in all five
comparisons. Every model miss was a semantic mismatch. The 4/8 test score is
below the proposed 80% success threshold, and prior exposure and the small
corpus still prevent a usefulness claim. The default provider remains
`source-v3` with `conditional-v1`; calibrated scoring is opt-in.

[Validation evidence](../../validation-ranking-2026-09-08.json) records the
combined suites, frozen source and report hashes, and test replay. This run
executed from the repository root and used the compiler binary built in this
checkout. Its compiler record therefore uses scope `root` and names a path
relative to the repository root. All 14 frozen source hashes match the retained
source files. Replay requires that exact compiler binary and model runtime;
the reports are local execution evidence, not a portable compiler build receipt.
