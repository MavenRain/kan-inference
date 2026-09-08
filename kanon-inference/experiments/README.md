# Prompt selection experiment

`challenge-prompts-v1.json` fixes two 135M prompt profiles, their order, the
corpus and split manifest, execution hosts, deadlines, and selection rule before
any comparison. It uses the installed pinned model and the existing behavioral
evaluator. No model download or weight training is part of the experiment.

`source-v3` keeps the original prompt bytes and mean conditional token
log-likelihood ranking. `kanon-primer-v1` adds a short explanation of Kanon
syntax and two demonstrations from the train split, `tariff_3_2` and
`capacity_5`. Demonstrations are fixed source data in `prompts.py`. The provider
does not open the corpus, read evaluation examples, or choose demonstrations
based on a validation or test request. Each profile ranks the same candidate
pool with the same model and limits.

From the repository root, after the existing compiler and provider setup:

```sh
make experiment-challenge EXPERIMENT_OUTPUT=/tmp/challenge-prompts-v1
```

Choose a new directory for each run. The runner freezes the plan, compiler and
implementation hashes, evaluates both profiles on train, then evaluates both
on validation. Candidate order and the unchanged deterministic baseline are
included in every comparison. It selects the profile with the highest count of
validation tasks passing all behavior examples on every requested host. Ties
go to the earlier profile in the plan. Train scores do not break ties. Failed
tasks stay in the denominator; an incomplete comparison cannot select a winner.

The runner saves `selection.json` before launching the selected profile on test.
The selection binds the frozen plan, code, model provenance and train/validation
reports. Replaying the saved selection rechecks these dependencies and computes
the same validation choice before starting test:

```sh
make experiment-test SELECTION=/tmp/challenge-prompts-v1/selection.json FROZEN_OUTPUT=/tmp/challenge-test-replay.json
```

The experiment plan chooses its hosts explicitly. The supplied plan uses kernel,
Node and Wasmtime. The regular benchmark's `HOSTS` setting does not override the
plan. To run a different configuration, create a separate plan inside the
checkout and pass `EXPERIMENT_PLAN=PATH`; retain it with its reports. Corpus,
split and provider paths in a plan are relative to the repository root.

An interrupted run leaves incomplete evidence. Existing report paths are
preserved. Start a new experiment in a fresh output directory after fixing a
failure. A change to a frozen source file or evidence report invalidates replay
of that selection; retain the matching checkout to reproduce historical runs.

These hashes check local consistency. They do not authenticate who produced a
report or prevent an operator from rewriting a whole evidence bundle. They also
cannot establish that test data remained unseen. Earlier implementers inspected
every split and ran deterministic test comparisons during corpus validation.
This experiment discloses that exposure and does not claim a sealed independent
test. The small correlated corpus, finite examples and cold process timings do
not satisfy the model usefulness or warm performance contract, whatever score
is observed.

The [recorded experiment](../results/challenge-prompts-v1-2026-09-08/experiment.json)
completed on 2026-09-08 with these behavior counts:

| Approach | Train | Validation | Test |
| --- | ---: | ---: | ---: |
| Candidate order | 2/8 | 2/8 | 2/8 |
| Unchanged deterministic baseline | 2/8 | 2/8 | 2/8 |
| Original `source-v3` prompt | 3/8 | 3/8 | 0/8 |
| Train-derived `kanon-primer-v1` | 8/8 | 1/8 | Not evaluated |

The [saved selection](../results/challenge-prompts-v1-2026-09-08/selection.json)
chose `source-v3` because it scored higher on validation. Only that model profile
was evaluated on test. Every selected term type-checked, and kernel, Node and
Wasmtime agreed across all five comparisons. All model failures were semantic
mismatches, with no provider protocol failure or host disagreement. The primer's
train score includes its two demonstration tasks and did not transfer to
validation. Both demonstrations and the primer syntax line show a one-argument
function, every train task takes one argument, and every validation task takes
two, so the primer's validation drop mixes prompt content with an argument-shape
change. The test split holds four two-argument interior tasks and four
one-argument clamp tasks. Neither approach justifies selecting a useful model.
The default remains the original 135M profile, with its experimental status
unchanged.

See [validation evidence](../../validation-prompts-2026-09-08.json) for source
hashes, tests and report hashes. The one-task primer preflight used a train
demonstration, retained no report and produced no artifact in this bundle, and it
did not change either prompt or the plan. The recorded run executed
`experiment.py run` from this repository root through `make experiment-challenge`,
and the eight reports were copied into
`../results/challenge-prompts-v1-2026-09-08`. The binding evidence is content, not
path: every `frozen.sources` hash equals the bytes committed here, and
`frozen.compiler.sha256` equals the built compiler binary. The compiler is inside
that run's root, so the selection records scope `root` with a path relative to the
repository root; a run from a separate working checkout records scope `absolute`
with a full local path instead. The recorded selection reuses the existing
compiler. Replay requires that exact compiler binary and matching recorded runtime
identity; these results are not a portable compiler build receipt. The corpus,
split manifest, compiler and provider paths inside each report, and the run
directories named beside the recorded checks, are provenance of the machine that
ran them and are not part of the checked evidence.
