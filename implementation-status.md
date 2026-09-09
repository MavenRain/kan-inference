Update, 2026-09-08: hint-calibrated ranking and checked numerical evidence

The [ranking experiment](kanon-inference/experiments/ranking.md) adds an opt-in
`hint-calibrated-v1` scoring profile. It subtracts each candidate's mean token
log-likelihood under the same request with an empty hint from its ordinary
conditional mean. Both passes use the unchanged `source-v3` prompt and pinned
135M model. No examples, parameters or weights are fitted. Generation remains
available through the default conditional profile; calibrated scoring requires
a candidate pool and shares the existing deadline and token limits.

Experiment plans now bind prompt and scoring profiles to fixed provider
wrappers. Reports and selections pin the scoring version and source hash.
Replay verifies recorded compiler requests and their hashes, reconstructs both
prompts, checks the component means and their differences, and checks stable
ranked indices against the candidate pool. Edited scores, prompt hashes, scoring
identity or ranking evidence are rejected. Existing prompt plans still default
to conditional scoring when the new optional field is absent.

The [frozen comparison](kanon-inference/results/challenge-ranking-v1-2026-09-08/experiment.json)
selected calibrated scoring: it scored 5/8 on validation against 3/8 for
conditional scoring, despite scoring only 1/8 on train against 3/8. The selected
method then scored 4/8 on test against 2/8 for each unchanged baseline. All
selected terms type-checked and kernel, Node and Wasmtime agreed across all
five comparisons. Every model miss was a semantic mismatch. Earlier test
exposure, including the previous conditional score of 0/8, is disclosed in the
new plan. No rule was adjusted after this comparison began.

[Validation evidence](validation-ranking-2026-09-08.json) records 157 Python
tests, 114 synthesis boundary cases, 47 driver tests and 13 provider protocol
tests, passing without skips, plus frozen-byte checks and selected test replay.
The compiler, corpora, split manifest, prompts and deterministic baseline were
unchanged. The prior unsuccessful prompt evidence is retained byte for byte;
its saved selection requires the matching `8e2d89e` checkout for replay.

This completes the next ranking-method experiment. The new score is opt-in and
the usefulness gate remains unmet: 4/8 is below the proposed success threshold,
and this corpus is neither large nor independently held out. The next slice
should test transfer on independently authored development tasks before fitting
or promoting an approach. Live Kanon integration, Lean parity, Kan-only
foundations, OCaml speed comparisons and browser/all-Wasm inference remain open.

Historical update, 2026-09-08: reproducible prompt comparison and validation selection

The [prompt experiment](kanon-inference/experiments/README.md) now freezes an
explicit plan, implementation hashes, compiler identity and split evidence.
It evaluates two fixed 135M prompt profiles on train and validation, saves the
validation choice before test, and supports replay after verifying the saved
selection. Ties use plan order and failed tasks remain in the denominator.
Incomplete, stale, edited or internally inconsistent evidence cannot select a
profile. A replay that fails verification retains an incomplete public report.

`source-v3` preserves the existing prompt bytes and scoring. `kanon-primer-v1`
adds a Kanon syntax primer and two fixed train demonstrations, `tariff_3_2` and
`capacity_5`. Model weights, resource limits, compiler sources, both corpora,
split assignments and the deterministic baseline remain unchanged. Providers
receive no evaluation oracles; compiler checks still precede behavior tests.

The completed comparison selected the original prompt: it scored 3/8 on train
and 3/8 on validation, while the primer scored 8/8 on train and 1/8 on validation.
The selected original prompt scored 0/8 on test. Candidate order and the unchanged
deterministic baseline each scored 2/8 in every comparison. All selected terms
type-checked and kernel, Node and Wasmtime agreed. Every model miss was a semantic
mismatch. The primer's train score includes its two demonstrations and does not
establish transfer. The model usefulness gate remains unmet.

[Validation evidence](validation-prompts-2026-09-08.json) records 121 Python tests,
114 synthesis boundary cases, 47 driver tests and 10 provider protocol tests,
all passing without skips. The 10 provider protocol tests come from a separate
command, `make test-provider`, which needs the local provider virtual
environment; `make test-all` runs both commands. Independent review verified fixes for replay reports
that could remain marked complete after rejection, and for selection evidence
that was not bound to ranking order. The full experiment and its selection
retain code, model, corpus, manifest and report hashes.

This completes a small train/validation/test prompt experiment, with prior test
exposure disclosed. The next model-development slice should investigate a
different ranking or adaptation method using development data, freeze a new
plan, and retain these unsuccessful results. Broader independently authored
tasks and stronger comparisons are still needed for a usefulness claim. Live
Kanon integration, Lean parity, Kan-only foundations, OCaml speed comparisons
and browser/all-Wasm inference remain separate unfinished work.

Historical update, 2026-09-08: frozen module splits and challenge coverage

The evaluator now accepts a frozen split manifest alongside a diagnostic corpus.
It validates the complete corpus hash, module coverage and template assignments
before selecting train, validation or test tasks. Reports preserve split hashes,
module IDs and counts; limits apply after selection. Changed oracles, missing
assignments and shared template groups across splits are explicit failures.

The [challenge corpus](kanon-inference/benchmarks/README.md#frozen-challenge-splits)
adds 24 tasks, 12 modules and six semantic template groups, with eight tasks per
split. Practical hints and local let expressions extend diagnostic coverage
beyond the unchanged baseline grammar. Compiler/kernel checks verify all 96
candidates: 24 intended answers pass and 72 decoys fail behavior. Every pool
holds at least two `let` candidates, no pool makes the intended term its single
longest candidate, and every task has a distinct pool and intended term. The
corpus was corrected on 2026-09-08, after its first freeze and before its first
commit, because those two surface cues named the intended term in all eight
validation tasks and all eight test tasks. The
original diagnostic corpus remains unchanged. Candidate order and the unchanged
deterministic baseline each score 2/8 on every challenge split, with all selected
terms type-accepted and zero disagreements across kernel, Node and Wasmtime.
Implementers inspected every split for corpus validation, so these results are
not a sealed independent evaluation.

This completes the split infrastructure and a small developer-authored challenge
set. It does not establish independent generalization or satisfy the proposed
500-task-per-family model-selection contract. No model or prompt was adapted,
and no model result on the new corpus has been recorded. Next, develop an approach
using the train split, choose it using validation, then evaluate a frozen approach
on test while disclosing any test exposure. Independently authored tasks and a
stronger comparison remain necessary before claiming model usefulness.

Current validation and deterministic comparison evidence are recorded in
[validation-2026-09-08.json](validation-2026-09-08.json). Live Kanon integration,
Lean parity, Kan-only foundations, OCaml speed comparisons and browser/all-Wasm
inference remain separate unfinished work.

Historical update, 2026-09-07: repository initialization and behavioral evaluation

The workspace is now a Git repository on `main`, with private GitHub remote
`MavenRain/kan-inference`. Repository source and results are staged separately
from installed model weights, virtual environments, caches and generated host
outputs. The original compiler snapshot and source patch remain preserved.

A new [behavioral evaluation harness](kanon-inference/benchmark.py) compares
candidate order, a deterministic symbolic baseline and an optional model. It
uses compiler-frozen requests, chooses the first compiler-valid proposal before
consulting any test oracle, and executes finite behavior examples through the
requested hosts. Type acceptance and behavior are counted separately. Timeouts,
malformed responses and failed tasks stay in the denominator. Reports preserve
hashes, model provenance, cold timing, per-family counts and incomplete-run state.
The diagnostic source shape forbids extra declarations, preventing later
shadowing from making the evaluator test a different definition.

The frozen [32-task corpus](kanon-inference/benchmarks/README.md) covers constants,
argument selection, unary arithmetic and binary arithmetic. It has eight
correlated groups and was developed together with the deterministic baseline.
It is not an independent held-out benchmark and does not meet the proposed
500-task contract.

[Full recorded comparison](kanon-inference/results/diagnostic-135m-2026-09-07.json):
SmolLM2-135M matched behavior on 9/32 tasks, the deterministic baseline on 32/32,
and candidate order on 8/32. All 32 selected terms for each strategy type-checked;
all three execution hosts agreed. The model's 23 misses were semantic mismatches,
with no provider protocol failures. This narrow diagnostic set gives no reason
to select the model over its deterministic comparator. The 360M model was not
rerun on this corpus, and model prompting and weights were not changed.

Fresh validation passed: 35 new baseline/evaluation tests, 106 compiler synthesis
boundary cases, 36 driver tests and seven provider protocol tests. Independent
review reproduced and verified the fix for definition-shadowing false positives.
The comparison ran every selected strategy through kernel evaluation, Node and
Wasmtime. See [validation evidence](validation-2026-09-07.json).

Next, design independent tasks outside the jointly developed baseline grammar,
freeze module splits and behavior oracles, and measure model adaptation or another
compatible code model. The model-selection gate stays unmet. Integration into
live Kanon, Lean parity, Kan-only foundations, OCaml speed comparisons and
browser/all-Wasm inference remain separate unfinished work.

Original implementation handoff follows.

The first checked-synthesis prototype is implemented in [kanon-synth](kanon-synth/SYNTHESIS.md), using an isolated snapshot of 658 files from the existing Kanon source. This task made no writes to the original repository. A final hash comparison found concurrent changes to ten original files after the snapshot was taken. The [source patch](kanon-synthesis.patch) targets the saved baseline and needs integration against the newer live tree.

The working path is an explicitly typed nonrecursive definition body containing `synth "hint"`. A locally embedded model ranks candidate expressions; the compiler parses one expression, checks its whole definition against the original goal and context, and persists ordinary source. Model output cannot introduce declarations, axioms or nested synthesis. Timeouts, malformed responses and invalid terms produce failures.

Validation evidence:

- 106 synthesis boundary tests passed, including otherwise ignored annotations, wrong types, direct and indirect axiom attempts, quantity misuse, multiple holes and family preservation.
- The full 35-test driver suite passed, then the new newline-protocol regression and the adjusted candidate-pool test passed. There are 36 driver tests in the final suite. These cover fresh replay, tampering, existing-output preservation, publication races, output floods, blocked stdin, descendant processes and real compiler rejection cases.
- Seven malformed model-provider protocol tests passed without loading a model.
- Existing kernel regressions passed after the source changes: parse 127, check 76, erasure 76, negative cases 51, kernel negatives 2, recursion 1 and migrated cases 4. Existing surface regressions passed 20/20. The 32-case Wasm suite passed on the copied baseline, and the new model-assisted program separately passed all three execution paths.
- Independent reviews found no confirmed issue in the scoped compiler/driver boundary or the model-provider boundary. Existing kernel and backend research gaps remain outside those reviews.
- The unchanged HOUSE checks passed. No kernel constructor, kernel axiom or conversion rule was added.

The real 135M model selected the later argument for the saved demonstration. The resulting [ordinary program](kanon-synth/dev/synthesis-results/synth-choice-resolved.kan) returned `42` through kernel evaluation, Node and Wasmtime. The [standalone Wasm artifact](kanon-synth/dev/synthesis-results/synth-choice.wasm) also returned `42` in Node. [Replay](kanon-synth/dev/synthesis-results/synth-choice-replayed.kan.synth.json) used no model and produced byte-identical source.

The [original synthesis receipt](kanon-synth/dev/synthesis-results/synth-choice-resolved.kan.synth.json) records 20.802 seconds including model startup. Replay took 0.960 seconds. Host load was approximately 98; neither measurement establishes a performance bound or an OCaml comparison.

The [135M](kanon-inference/results/smoke-135m.json) and [360M](kanon-inference/results/smoke-360m.json) int8 models each scored 4/6 on the same frozen pilot, versus 3/6 for the weak candidate-order baseline. The default remains 135M, with 137,147,867 bytes of model weights. No model has passed the 500-task usefulness contract. The pilot's observed peak process memory was approximately 624 MB for 135M and 1,019 MB for 360M, including inference working memory.

The direct-generation identity probe produced `def identity : (A : Type 0) -> A := ?`. The restricted expression parser rejected it, and no program was published. This failed probe is retained in the [model record](kanon-inference/results/direct-identity-135m.json) and [compiler rejection record](kanon-synth/dev/synthesis-results/direct-identity-rejection.json).

The next milestone is model usefulness: freeze a larger independent task corpus and a stronger deterministic baseline, then evaluate adaptation or another compatible small code model. Kan-only derivations, full Lean 4 parity, a matched OCaml compilation benchmark, and browser/Wasm inference remain separately open.
