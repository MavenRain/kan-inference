# Diagnostic corpus

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
