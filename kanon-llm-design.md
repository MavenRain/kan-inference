Draft architecture for Kanon with embedded synthesis

Prepared 2026-09-07. This is a proposed extension and feasibility contract, not an implemented language or a claim that the requested guarantees have been achieved. The working assumption is development-time LLM assistance. Runtime assistance remains an alternative pending the user's preference.

The design has two language-level facilities: Kan extensions and one `synth` operation. `synth` proposes a program or proof in an explicitly given context. A deterministic kernel must check the proposal before it becomes a program. The model supplies search, never evidence by itself.

The existing implementation in `/Users/oobi/Documents/kanon` is the relevant starting point. Its current state and concrete extension seams are recorded in [kanon-current-state.md](kanon-current-state.md). That repository has ongoing staged work. This draft and the [evaluation contract](evaluation-contract.json) are separate artifacts in the current workspace.

| Requirement | Proposed operational meaning | Evidence required |
|---|---|---|
| Only Kan extensions plus the LLM primitive | Lan/Ran kernel type formers and a development-time `synth` form, with all ambient rules disclosed | Full primitive and rule inventory, plus derivations for every claimed derived construct |
| At least Lean 4 type safety and expressiveness | A stated correspondence to a pinned Lean 4 logical fragment and then its full supported core, under explicit matching assumptions | Formal preservation arguments, independent checking, positive and negative conformance suites |
| At least OCaml compilation speed | A ratio at most 1.0 on fixed paired ordinary-program workloads, with both tools' complete compile commands disclosed | Clean and incremental measurements on named hardware; separate proof-checking and synthesis measurements |
| Smallest useful embedded LLM | Smallest deployed model artifact among evaluated candidates meeting a declared task, latency and memory gate | Held-out task evaluation after quantization, including comparison to deterministic search |
| Wasm and Wasm-powered CLI | Checked programs lower to Wasm; the CLI hosts those modules | Host compatibility tests, semantic agreement, explicit inference deployment profile |

“Two facilities” is a proposed interpretation of the primitive requirement. It does not establish that every logical rule is a Kan extension. If “only primitives” literally excludes ambient universes, substitution, equality rules, or an effect interface, this design has an unresolved foundational obligation. Renaming an induction rule as a Kan shape would not discharge it.

For a context projection `p : Gamma.A -> Gamma`, the intended semantic starting point is the adjunction chain `Lan_p ⊣ p* ⊣ Ran_p`. In a suitable model of dependent families, left and right adjoints to reindexing interpret dependent sums and products. General categorical Kan extensions need not exist in every setting, and their universal properties alone do not specify executable reduction rules. The connection is supported by the polynomial treatment in [Hamana and Fiore, A Foundation for GADTs and Inductive Families](https://www.cl.cam.ac.uk/~mpf23/papers/Types/gadtif.pdf); it is not a proof of this proposed kernel.

Before a Kan-only claim, write formation, introduction, elimination, computation and substitution rules for a closed, decidable shape grammar. Prove substitution stability, the appropriate Beck-Chevalley properties, and preservation for the chosen reductions. Account explicitly for the following:

1. Contexts, variables, substitution, universes and universe constraints.
2. Dependent functions and pairs, including the exact judgmental equality rules.
3. Identity and equality elimination, beyond equality of runtime values.
4. Strictly positive inductive families, dependent induction, mutual and nested cases, and termination checking.
5. Impredicative propositions, proof irrelevance and restrictions on elimination into computational types.
6. Quotients and the logical assumptions needed for their equality principles.
7. Literal accelerators, effects and foreign interfaces, with a distinction between derived syntax, representation optimizations and trusted operations.

Initial algebras and their induction principles need an explicit construction or an openly counted additional assumption. Coequalizers do not automatically establish Lean's precise quotient interface and computation behavior. Surface encodings are insufficient if they lose dependent elimination, universe behavior or required computation rules. The first foundation checkpoint is a derivation of `Nat` with dependent induction and its computation laws, then an indexed family such as `Vec`, tied to actual checked syntax and the compiler's implementation.

Lean's documented core includes universes, dependent functions, inductive types and quotients, together with conversion behavior such as proof irrelevance and function/structure eta. This supplies a concrete comparison target, rather than a single informal “type-strength” score. Elaborator conveniences such as type classes and tactics need a separate usability comparison. [Lean type system reference](https://lean-lang.org/doc/reference/latest/The-Type-System/)

Start parity work with a pinned Lean release, a precisely stated fragment, and a translation preserving typing and the specified computation behavior. A reverse interpretation into Lean can provide relative soundness evidence. Record assumptions on both sides. General claims need arguments beyond a finite passing test corpus. Library coverage and automation quality are separate from logical expressiveness. Noncomputable classical proofs also do not imply executable Wasm implementations of arbitrary functions.

The proposed `synth` contract is an elaboration judgment:

```text
request = (frozen context Gamma, expected type T, hint, dependency policy, budget)
candidate = model(request)
parse candidate as restricted term syntax
elaborate candidate without changing Gamma or T
independently check Gamma |- candidate : T
check transitive assumptions against dependency policy
return CheckedTerm(candidate) or a structured synthesis failure
```

`CheckedTerm` is an implementation-side wrapper produced by the checker. This is not an unrestricted object-language constant of type `forall T, String -> T`: such a total constant could claim a proof of `False`. At a source hole, failure stops elaboration with a diagnostic. Model refusal, wrong types, timeouts and exhausted search budgets are ordinary failures. Accepted terms must have no unresolved metavariables or nested synthesis requests, and must respect the context's universe and resource-usage constraints.

Proposed surface syntax, not current Kanon syntax:

```text
def id (A : Type) : A -> A := synth "return the argument"

def append {A : Type} {m n : Nat}
  (xs : Vec A m) (ys : Vec A n) : Vec A (m + n) :=
  synth "append xs and ys in order"
```

The first example is the initial small-model task. The vector example is a later target after the requisite dependent types and arithmetic are available. Its type proves a length property only. To guarantee element order and contents, the requested specification must include those properties and synthesis must provide their proofs. Type checking does not establish that a natural-language hint expresses the programmer's actual intent.

The model receives the local context, expected type and a bounded set of relevant declarations. Begin with constructor completion or ranking a deterministically generated set of applicable terms. This reduces the vocabulary burden of a new language. Generation may use grammar constraints and bounded checker feedback. Neither mechanism proves model usefulness; compare each against the same deterministic baseline.

Keep model input and output as data. Accept a single restricted expression or term tree. Exclude top-level declarations, new axioms, macros, plugins, host calls, imports and changes to the goal or its dependencies. Apply byte, token, elaboration and checking limits. Budget exhaustion must produce a failure, never an unchecked success. Pin the target and its dependency closure before generation. Check assumptions transitively so that a seemingly harmless library reference cannot introduce an unapproved axiom. This extends the separation between terms, assumptions and intended statements described in [Lean proof validation](https://lean-lang.org/doc/reference/latest/ValidatingProofs/).

Inference remains outside the logical trusted base. The checker, term decoder, dependency loader and axiom-policy enforcement remain trusted unless separately verified. Runtime behavior additionally depends on erasure, lowering, the encoder and the selected Wasm host. Kernel acceptance alone is not a correctness proof for the backend.

Successful synthesis materializes an ordinary term in a source expansion or versioned sidecar. Store the request, normalized context, expected type, transitive dependency fingerprints, checker/elaborator versions and accepted-term digest. Also store provenance: model and tokenizer digests, quantization, decoding settings, prompt/template version and inference runtime. Recheck persisted terms against the current environment. A model hash or fixed random seed is not a guarantee of identical results across hardware; the persisted accepted term provides replay stability.

Proposed command behavior:

```text
kanon synth file.kan       # Produce checked materialized expansions.
kanon check file.kan       # Recheck terms, fail on unresolved synthesis.
kanon build file.kan       # Deterministically check and emit Wasm.
kanon run file.kan         # Execute the resulting module in a selected host.
```

These commands are a proposed interface, not instructions to run against the current compiler. Existing `auto` is reserved for instance synthesis, so the LLM operation should receive a distinct surface form and elaboration path.

Model selection is a search over measured deployments. An extremely small model may help with ranking or bounded repair; none of the cited cards demonstrates competence in Kanon. The first experiment should test the following ladder, with adaptation if needed:

| Candidate | Parameters reported by publisher | Ideal all-4-bit weight payload | Experimental role |
|---|---:|---:|---|
| [SmolLM2-135M-Instruct](https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct) | 135M nominal | 67.5 MB | Rank candidate terms or lemmas |
| [SmolLM2-360M-Instruct](https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct) | 360M nominal | 180 MB | Bounded hole completion |
| [Qwen2.5-Coder-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-Coder-0.5B-Instruct) | 0.49B | 245 MB | First code-specialized comparison |
| [Qwen2.5-Coder-1.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct) | 1.54B | 770 MB | Escalation if smaller candidates fail |

The payload column is arithmetic, `parameters * 4 / 8`, in decimal megabytes. Actual artifacts and memory are larger because of quantization metadata, higher-precision tensors, tokenizer, KV cache, activations, runtime and loading buffers. The cards identify these candidates as Apache 2.0. This shortlist is a starting experiment, not an exhaustive contemporary ranking or an absolute lower bound. A custom trained smaller model could win.

Freeze independent train, validation and test modules before generating synthetic variants. Evaluate at least 500 held-out tasks in each task family for which usefulness is claimed. Report first-attempt success and success within eight candidates, using identical context and token budgets across candidates and baselines. Include wrong-goal and malformed-output controls. Quantization must precede final evaluation.

Proposed initial product gates are at least 80% verified task success, at least ten percentage points above the strongest deterministic baseline at a comparable budget, and warm p95 end-to-end synthesis latency at most five seconds on named minimum hardware. Report uncertainty intervals, cold model-load time, peak memory and task-specific results. These thresholds are proposed defaults, not measured results or user-approved specifications. If a baseline already solves a task, choose a more useful task rather than claim model value from its presence alone.

For multiple claimed tasks, one installed model must satisfy each declared task gate. Selecting a different model per task changes the deployed-size calculation to the complete shipped package. Training and teacher-model costs are reported separately from embedded inference size. A distillation process is an option if prompting alone fails, not an assumed requirement or a completed step.

Wasm program execution and inference placement are separate deployment choices:

| Profile | Program execution | Model execution | Evidence needed |
|---|---|---|---|
| Browser, CPU only | Wasm module | Compatible model runtime compiled to Wasm | Actual model/operator compatibility and acceptable CPU latency |
| Browser, GPU enabled | Wasm module | WebGPU with browser orchestration | WebGPU availability, adapter support and memory measurements |
| Wasm-powered CLI | Wasm module hosted by the CLI | Embedded native CPU/GPU backend | Bundled local inference with no required network service |
| Entire CLI inside Wasm | Wasm compiler/runtime | Wasm inference or an explicitly declared host import | Component/ABI and memory compatibility, measured separately |

[ONNX Runtime Web](https://onnxruntime.ai/docs/tutorials/web/) provides a CPU Wasm execution option, but each exported model still needs compatibility and performance validation. [WebLLM](https://webllm.mlc.ai/docs/user/get_started.html) requires WebGPU. Browser-local inference therefore does not by itself establish all-Wasm inference. For development-time synthesis, the finished application need not carry model weights unless it also supplies development tooling or runtime assistance.

Keep the current WasmGC route as the first code-generation target, subject to verified host support. Define an explicit host ABI for I/O and traps. A Wasm module with host imports is not a self-sufficient operating-system executable. Test compiler evaluation against target execution, including data layout, recursion, big integers and observable errors.

Compilation speed must be measured without hiding work. The user-facing wait is `context preparation + model loading/inference + candidate elaboration/checking + compilation + required linking/host preparation`. Report each component and the full sum. Previously materialized synthesis can legitimately be absent from later compilation; cold generation time cannot be presented as OCaml-speed compilation.

For the ordinary programming fragment, use paired programs with matching behavior and scale. Pin OCaml and Kanon versions, optimization levels, clean/warm cache states, core counts and complete commands. Include source parsing, elaboration, kernel checking, lowering, emission and all required postprocessing for the declared output. Record `ocamlc` and `ocamlopt` separately. Also distinguish time to code artifact from time to a runnable deployment, because native OCaml and Wasm outputs have different host requirements.

For each workload, the proposed performance target is `median(Kanon compile) / median(OCaml compile) <= 1.0`; report p95 and absolute times too. A per-line ratio against another proof checker's test runner does not establish this target. Proof-heavy workloads need their own Lean comparison because OCaml has no equivalent dependent-proof obligation. General dependent conversion and proof generation can be expensive, so no universal “faster for every program” guarantee is justified. Budgeted interactive checking may return an explicit resource-limit failure; it must never weaken the logic to meet a timer.

The first implementation milestone is a checked synthesis vertical slice:

1. Stabilize and pin a reviewable Kanon baseline; preserve the current staged work and record outstanding compiler checks independently.
2. Implement a distinct surface synthesis request and a restricted term protocol. Freeze context and goal before passing the request to any proposer.
3. Connect proposal elaboration to independent kernel checking, transitive assumption enforcement and structured failures. Validate this boundary with a fixture proposer before introducing inference. Enforce a hard worker deadline until all evaluator paths support cooperative checking budgets; the current checker budget does not cover every reduction.
4. Add accepted-term persistence and fresh deterministic replay. Reject stale context, wrong-goal substitutions, axiom injection and malformed candidate terms.
5. Embed one actual compatible small model, then run the frozen task corpus and deterministic baseline. A fixture proposer validates plumbing only and never counts as LLM usefulness evidence.
6. Demonstrate one model-assisted program whose checked materialized term compiles to Wasm and agrees with kernel evaluation. Publish model size, cold/warm latency, peak memory and unsuccessful attempts.

Success at this milestone means one useful embedded synthesis task works through the full checking and execution path. Lean parity, Kan-only foundations and OCaml-speed compilation remain separately tracked obligations until their own evidence is complete.

If runtime LLM results are required, use the same conceptual operation in an explicit effectful phase and return failure-or-validated-data. Ordinary runtime consumers can validate a schema; stronger dependent guarantees require a runtime proof checker and a frozen specification, or a deterministic verifier tailored to the property. Runtime inference cannot enter definitional equality or supply unchecked proof objects. Its failure, latency and memory costs belong to program execution. The effect and host interfaces must also appear in the primitive inventory.
