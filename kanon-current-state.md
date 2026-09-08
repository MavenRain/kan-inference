# Kanon source inspection, 2026-09-07

Read-only inspection of `/Users/oobi/Documents/kanon`. No project code, builds, or test suites were run. Historical memory was used only to locate the project; current source and Git state support the findings below. No applicable `AGENTS.md` was present in the repository or the checked ancestor paths.

## Current state

Git reports branch `main`, HEAD `c418062` (`M1 Stage K: arbitrary precision Nat and linear One`), and 76 staged files with 22,647 insertions and 144 deletions. The unstaged diff is empty. These are existing user changes and were preserved.

The README status is stale: [README.md:10](/Users/oobi/Documents/kanon/README.md:10) says M0 Stage E. The later [Stage L log:1768](/Users/oobi/Documents/kanon/dev/M1-BUILD-LOG.md:1768) says `IMPLEMENTED, VALIDATION PENDING`. Its recorded full battery has sixteen passing legs and three open legs: M0-TIME, M0-RATIO, and AGREEMENT. The latter reached its 300-second watchdog after 2,978 of 7,445 cases; no completed Stage L or M1 claim follows from those results ([log:1952](/Users/oobi/Documents/kanon/dev/M1-BUILD-LOG.md:1952)). These are recorded results, not fresh measurements.

## Primitive inventory and mathematical limits

The current implementation counts two *type formers*, `Lan` and `Ran`, and four introduction/elimination constructors. Its term grammar also contains variables, universes, globals, literals, lets, annotations, and `Auto` ([term.ml:46](/Users/oobi/Documents/kanon/lib/term.ml:46)). The SPEC additionally counts three named rules: proof irrelevance, subsingleton large elimination, and a literal fast path ([SPEC.md:175](/Users/oobi/Documents/kanon/SPEC.md:175)). Thus the existing source claim is narrower than a literal claim of only Kan extensions plus one LLM primitive across the entire trusted calculus.

The global initial environment postulates `Nat` and installs five arithmetic/comparison primitives. File-level `kanon axioms` output does not disclose that initial `Nat` postulate ([global.ml:118](/Users/oobi/Documents/kanon/lib/global.ml:118), [prim.ml:17](/Users/oobi/Documents/kanon/lib/prim.ml:17)). Finite agreement tests support the literal accelerator, but are explicitly not a general agreement theorem ([SPEC.md:272](/Users/oobi/Documents/kanon/SPEC.md:272)). Impredicative `Prop` additionally uses the stated framework level rule ([SPEC.md:293](/Users/oobi/Documents/kanon/SPEC.md:293)).

Three closed shapes are admitted: `SPi`, `SColl`, and `SMu`. `SPar` and `SNu` are refused ([rules.ml:1425](/Users/oobi/Documents/kanon/lib/rules.ml:1425)). `SMu` carries a family name and indices, with a dedicated rule pack for formation, introduction, dependent elimination, beta reduction, and subsingleton handling ([shape.ml:10](/Users/oobi/Documents/kanon/lib/shape.ml:10), [rules.ml:1388](/Users/oobi/Documents/kanon/lib/rules.ml:1388)). Counting it as a shape does not itself derive inductives from Kan universal properties. The project explicitly acknowledges that this derivation and the compiler correspondence remain open ([FOUNDATION-AUDIT.md:7](/Users/oobi/Documents/kanon/dev/FOUNDATION-AUDIT.md:7)).

The latest indexed metatheory constructs a semantic model for nullary/unary recursive signatures and vectors. It neither interprets checked `SMu` syntax nor proves the OCaml checker, eraser, or emitter preserve that model. It uses Lean's equality, iteration, and quotient machinery, with `Quot.sound` dependencies disclosed. Multiple recursive children and infinite branching remain outside that increment ([INDEXED-CONSTRUCTION.md:11](/Users/oobi/Documents/kanon/dev/INDEXED-CONSTRUCTION.md:11)).

## Gaps against the requested guarantees

| Requirement | Source-supported status |
| --- | --- |
| Lean 4 type expressiveness | Dependent functions, pairs, variants, indexed/mutual families, restricted Prop elimination, and structural recursion exist. Nested inductives, universe level variables, computational quotients, and general well-founded recursion remain deferred; a complete identity/elimination library and semantic parity are unestablished ([FOUNDATION-AUDIT.md:38](/Users/oobi/Documents/kanon/dev/FOUNDATION-AUDIT.md:38)). |
| WebAssembly target | The existing OCaml driver checks and emits WasmGC, then runs Node or Wasmtime through host runners ([kanon.ml:132](/Users/oobi/Documents/kanon/bin/kanon.ml:132), [kanon.ml:215](/Users/oobi/Documents/kanon/bin/kanon.ml:215)). This is useful existing infrastructure. It is not evidence that the compiler or LLM inference itself runs inside Wasm. |
| At least OCaml compilation speed | No implemented gate establishes this comparison. See the measurement definitions below. |
| Embedded LLM coding primitive | No LLM integration was found in `lib`, `surface`, or `bin`. `auto` parses to `SAuto`, elaborates to `Term.Auto`, and is rejected with `instances arrive at M2` ([elab.ml:202](/Users/oobi/Documents/kanon/surface/elab.ml:202), [check.ml:191](/Users/oobi/Documents/kanon/lib/check.ml:191), [rules.ml:24](/Users/oobi/Documents/kanon/lib/rules.ml:24)). It is currently reserved for instance synthesis. |

The binding `M0-RATIO` limit is **2.000**, not 1.000 ([gates.sh:48](/Users/oobi/Documents/kanon/dev/gates.sh:48)). Its exact definition is:

```text
(median(kanon check 1000-line corpus) / 1000)
  / (103.662 ms / 8138 lines)
```

The denominator is the frozen warm **tot kernel test suite**, not OCaml compilation. The numerator is Kanon checking, not its full Wasm compilation path ([m1-gates.py:124](/Users/oobi/Documents/kanon/dev/m1-gates.py:124)). The latest recorded ratio is 3.161088 under load 62.494, failing the 2.000 limit; quiet-machine classification remains open ([log:1940](/Users/oobi/Documents/kanon/dev/M1-BUILD-LOG.md:1940)).

`M0-TIME` times checking, emission, and both execution hosts for one spine against 150 ms ([m1-gates.py:112](/Users/oobi/Documents/kanon/dev/m1-gates.py:112)). `M1-CORPUS` times a compound check/emit/host validation against 713 ms for 1,000 lines ([m1-gates.py:161](/Users/oobi/Documents/kanon/dev/m1-gates.py:161)). The stored OCaml measurements are older clean-plus-build timings for a separate 4,969-line OCaml corpus, with substantial sample spread; they do not supply a matched contemporary source-to-artifact comparison ([denominators.json:36](/Users/oobi/Documents/kanon/dev/denominators.json:36)).

## Bounded first implementation milestone

Add one **elaboration-time synthesis operation** that asks an embedded model for a term filling a fully typed hole. Keep candidate generation outside the trusted checker. Initially limit requests to nonrecursive definition bodies and expression-sized holes with explicit expected types. Keep `auto`'s existing instance meaning separate unless the language specification deliberately changes it.

The implementation seam is already present: `Elab.elab` receives both a `Check.ctx` and `expected : Value.t option`; the context contains local names, quantities, types, and checked globals ([elab.ml:186](/Users/oobi/Documents/kanon/surface/elab.ml:186), [check.ml:27](/Users/oobi/Documents/kanon/lib/check.ml:27)). Add an injected synthesis provider there or a preceding goal pass. Parse exactly one expression, require end-of-input, reject further synthesis requests in a candidate, elaborate against the fixed goal, and let normal declaration checking accept or reject it. `elab_program_in` already checks every elaborated definition before installing it ([elab.ml:1124](/Users/oobi/Documents/kanon/surface/elab.ml:1124)). Do not allow candidate output to introduce declarations, axioms, imports, or a replacement goal type.

Materialize accepted ordinary Kanon source in a replayable artifact. A normal build then rechecks the resolved term without loading the model. Give the inference attempt explicit output, retry, and wall-time bounds, and use process isolation to enforce a hard timeout because the current checker budget polls inference nodes rather than every evaluator reduction ([budget.ml:23](/Users/oobi/Documents/kanon/lib/budget.ml:23), [check.ml:140](/Users/oobi/Documents/kanon/lib/check.ml:140)).

Validate the boundary first with injected candidates: valid term accepted, wrong type rejected, unavailable variable rejected, axiom/declaration injection rejected, erased/linear misuse rejected, unresolved nested request rejected, exhaustion reported, and resolved artifact checks and executes identically through existing Wasm hosts. Then embed one actual locally executing model backend and benchmark a small held-out task corpus. A mock provider alone completes only the trust-boundary milestone, not the user's embedded-LLM requirement. No smallest sufficient model can be selected from this repository evidence without such task measurements.

This milestone adds useful assistance while preserving the current trust boundary. The Kan-only derivation, Lean parity, broad Wasm ABI, and matched OCaml compilation benchmark remain separate required work.
