# Diagnostic corpus

The newer [transfer development corpus](../experiments/transfer.md) records a
disclosed separate task-authoring session and compares the two existing ranking methods
without fitting parameters or selecting a winner. Its authorship disclosure,
corpus and development-only module assignments are frozen before measurement.
It remains same-project diagnostic coverage, not a sealed external evaluation.

`diagnostic-v1.json` is an authored development corpus of 32 small Nat tasks.
It expands the original six smoke cases with compiler validation and executable
behavioral examples. It is not an independent held-out evaluation, a 500-task
corpus, or evidence that the proposed model-selection gate has passed.

The deterministic baseline and this corpus were developed together. Their hints
share an intentionally supported phrase grammar. A high baseline score therefore
demonstrates useful diagnostic coverage, not general natural-language synthesis
ability. Existing model prompting was not changed for this corpus.

| Family | Tasks | Shared module groups |
| --- | ---: | --- |
| Constants | 8 | `constants_direct`, `constants_expressions` |
| Argument selection | 8 | `projections_ordinal`, `projections_named` |
| Unary arithmetic | 8 | `unary_offset`, `unary_scale` |
| Binary arithmetic | 8 | `binary_basic`, `binary_composite` |

Each group contains four closely related tasks. Examples, templates and operator
patterns recur across groups, so even these eight groups are correlated. Treating
32 outcomes as independent trials would overstate the statistical evidence.
Keep related source modules and templates together when designing future splits.

Every task contains one source declaration with a `synth` body, four candidate
expressions and one to three input/output examples. Constants have one example;
functions have three. Nat subtraction saturates at zero, and the examples cover
both subtraction directions and zero boundaries. The first semantically passing
candidate appears at each pool position eight times. Eight tasks have multiple
passing expressions, including commuted addition, multiplication identities and
arithmetic expressions for constants. Exact-string scoring would reject some of
these valid alternatives.

The runner restricts source to one nonrecursive synthesis definition, with no
prefix or suffix declarations. This prevents a later declaration from replacing
the term under test. Strings and line comments are skipped when checking the
source shape; the compiler remains responsible for parsing and type checking.

The behavior examples remain finite tests, not proofs of the English hint or of
equivalence for every input. Every intended oracle candidate was checked with the
existing Kanon synthesis compiler and executed against its examples in the kernel
before this corpus was frozen. A later run must record its own compiler identity,
host results and corpus hash.

## Deterministic development baseline

`baseline.py` exposes `rank_candidates(request: dict) -> list[str]`. It reads only
the hint, expected type and candidate strings. It does not inspect task IDs,
examples, expected outputs or declaration bodies from the compiler context.

Supported hints explicitly name a literal, argument position/name, unary
addition/subtraction/scaling, or a simple sum/product of two arguments. The
recognizer also handles squares and a small set of compositional arithmetic
phrases. Numeric literals are not limited to the constants in this corpus.
Candidate binder names may differ from the names in the compiler's expected type.

The restricted candidate parser recognizes Nat literals, bound arguments,
parentheses and `natAdd`, `natMul` and `natSub`. Symbolic normalization covers
constant folding, neutral elements, commutativity and distributivity of addition
and multiplication. Truncated subtraction remains ordered except for simple
sound identities and constant folding. Candidate text is never passed to an
evaluator, imported or executed by the baseline. Parsing and symbolic expansion
have fixed bounds.

Matching expressions move to the front, preserving their original relative
order. All other expressions retain their relative order. Unsupported hints,
unsupported types and recognized hints with no structural match preserve the
whole input ordering. The compiler still checks each proposal's syntax, scope
and type. This is a reproducible development baseline, not a claim to be the
strongest deterministic method available.

## Interpreting a comparison

Report the original candidate-order baseline alongside the deterministic baseline
and model. Use the same source, candidate pool and examples for each strategy.
The selected compiler-valid candidate must pass every example on every requested
execution host. A failed behavioral example cannot be used to try another
candidate because that would give the proposer access to the answer oracle.

Any model comparison on this set describes these diagnostic tasks only. A
credible usefulness decision still needs an independently designed corpus,
stronger baselines where appropriate, a frozen split/prompt policy and the
separate acceptance criteria in the broader evaluation contract.

## Frozen challenge splits

`challenge-v1.json` adds 24 developer-authored Nat tasks with practical hints
outside the unchanged baseline's phrase grammar. Candidate terms also use local
`let` bindings beyond its restricted candidate parser. At least two candidates in
every pool carry a `let` binding, and no pool makes the intended term its single
longest candidate, so neither surface cue names the answer. Every task has a
distinct candidate pool and a distinct intended term. The corpus keeps the same
diagnostic task schema and single-definition compiler boundary as diagnostic-v1.
It is a small challenge set, not an independent 500-task evaluation.

The corpus was corrected on 2026-09-08, after its first freeze and before its
first commit. In the first bytes the intended term was the only candidate with a
`let` binding and the longest candidate in all eight validation tasks and all
eight test tasks, so a one-line rule scored 8/8 on both held-out splits. The
correction replaces one decoy in each affected pool and re-authors the absolute
distance pools, which also collapsed onto one shared pool. Every hash, recorded
run and count in this file covers the corrected bytes.

`challenge-v1.splits.json` pins the SHA-256 of the complete corpus bytes, including
the source, candidate order and every behavior example. Each module belongs to
exactly one split, and modules sharing a semantic template stay in the same
split. Assignments were authored before running the model or adapting its prompt.

| Split | Tasks | Modules | Template groups |
| --- | ---: | ---: | --- |
| train | 8 | 4 | Affine tariffs, capped capacity |
| validation | 8 | 4 | Absolute distance, staged consumption/refill |
| test | 8 | 4 | Rectangle interior, interval clamping |

The intended answer occupies each of four candidate positions equally within
each split, two tasks per position. Finite examples include zero and relevant
saturation or boundary cases. Corpus tests pin that per-split balance, the task
family against its module template group, the distinct pools and the absence of
the two surface cues. Corpus integrity tests check all 96 candidates with the
real compiler and
kernel: the 24 intended candidates pass, and all 72 decoys fail behavior. This use of the oracle
validates the corpus; the benchmark still selects its first compiler-valid
candidate before running any behavior example.

Run one split from the repository root:

```sh
make benchmark-challenge-baseline SPLIT=train CHALLENGE_OUTPUT=/tmp/challenge-train.json
make benchmark-challenge-baseline SPLIT=test HOSTS=kernel,node,wasmtime CHALLENGE_OUTPUT=/tmp/challenge-test.json
make benchmark-challenge-135m SPLIT=validation CHALLENGE_OUTPUT=/tmp/challenge-model-validation.json
```

The model target requires the provider installation. `SPLIT` has no default, and
both challenge targets stop with an error when it is unset. `HOSTS` defaults to
`kernel`. Reports are created exclusively, so choose a fresh
output path for each run. The CLI equivalents are `--split-manifest PATH` and
`--split train|validation|test`, which must be supplied together. `--limit N`
applies after split selection and is recorded as a partial split when it reduces
the available task count. Interrupted reports retain the selected denominator.

The validator rejects changed corpus bytes, incomplete or duplicate module
assignments, unknown modules, shared template groups across splits, exact task
payloads relabeled into different modules, and empty selections. Reports include
the manifest hash, split unit, selected modules, template groups and task counts.
Providers receive only compiler context, hints, candidate pools and budgets;
split metadata and behavioral oracles stay in the evaluator.

These checks establish consistency of declared assignments. They cannot prove
independent authorship, detect every paraphrase or semantic clone, or prevent an
operator from inspecting test data. Related Nat operations still recur across
splits. Keep test tasks out of model adaptation and disclose exposure before any
usefulness claim. After the first commit of these files, any source, candidate
or oracle correction requires a new corpus version and corresponding manifest,
preserving these frozen files.

Per-family counts in a report cover four tasks each. Read their intervals as
descriptive summaries of this small set, not as evidence about a family.

The recorded 2026-09-08 comparisons cover [train](../results/challenge-train-baseline-2026-09-08.json),
[validation](../results/challenge-validation-baseline-2026-09-08.json) and
[test](../results/challenge-test-baseline-2026-09-08.json). Candidate order and
the unchanged deterministic baseline each score 2/8 in each split, with all
selected terms type-accepted and zero disagreements across kernel, Node and
Wasmtime. The baseline preserves candidate order for these unsupported hints.
These baseline-only runs did not use a model. Implementers inspected the entire corpus and evaluated the
test split to validate the infrastructure; it is not a sealed independent test.

The subsequent [prompt experiment](../experiments/README.md) uses the same frozen
bytes and unchanged baselines. It compares the original prompt and a train-derived
primer on train and validation, saves the validation choice, then evaluates that
choice on test. All prompt candidates and the tie rule are fixed by its plan.

Each report records `corpus.path`, `split.manifest_path` and `compiler.path` from
the operator's own checkout. Those paths are provenance, not a reproduction
target. The binding evidence is the `sha256` field beside each path. A rerun on
the same bytes must reproduce `corpus.sha256`, `split.manifest_sha256`,
`split.selected_tasks`, the `implementation` hashes, `compiler.sha256` and the
`type_accepted`, `semantic_correct` and `host_disagreement` counts. Elapsed
seconds differ on every run, so the report hash itself does not reproduce.
