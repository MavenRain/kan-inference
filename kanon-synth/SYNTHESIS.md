Checked synthesis prototype

This isolated Kanon snapshot adds a development-time `synth` operation. A local model proposes ordinary source expressions. The compiler accepts a proposal only after checking its complete definition against the original type and preceding declarations. Finished source compiles and runs through the existing WasmGC backend.

The first supported form is an explicitly typed, nonrecursive definition whose entire body is a synthesis request:

```text
def select : (earlier : Nat) -> (later : Nat) -> Nat :=
  synth "Return the later argument."
def main : Nat := select 17 42
```

Synthesis inside types, recursive bodies or nested expressions produces an explicit error. A candidate may be a complete lambda expression with ordinary binders. `auto` retains its existing meaning and is rejected in synthesis inputs and proposals.

Build from this directory using the existing OCaml toolchain:

```sh
DUNE_CACHE=disabled dune build --root . bin/kanon.exe test/synthesis.exe
```

The local inference installation is documented in the sibling [kanon-inference directory](../kanon-inference/README.md). Once its `provider` executable and model are installed, synthesis uses that provider by default. These commands create new files and refuse to replace existing outputs:

```sh
./kanon synth examples/synth-choice.kan \
  --candidate-pool examples/synth-choice.candidates.json \
  -o /tmp/kanon-choice-resolved.kan
./kanon check /tmp/kanon-choice-resolved.kan
./kanon run /tmp/kanon-choice-resolved.kan --export main --host both
```

The pool contains two candidate expressions. The model orders them according to the hint, and the compiler checks proposals in that order. Type checking guarantees the declared type; the hint's intended behavior needs a separate test or a stronger formal specification. The example's intended result is `42`, while selecting the first argument produces `17` and still satisfies the type. This demonstration uses a successful smoke-test case and is not a separate accuracy measurement.

Without `--candidate-pool`, the provider attempts direct expression generation. The tested 135M identity attempt produced an invalid declaration with a hole, which the compiler rejected. Direct generation is experimental and has not passed this demonstration. `--provider /absolute/path/to/executable` selects another explicitly trusted local proposer implementing the JSON protocol.

Every successful request writes an ordinary `.kan` file and a neighboring `.kan.synth.json` receipt. The receipt records source, compiler, request and accepted-candidate hashes, model provenance, rejected proposals, and timing. Replay invokes no model and rechecks every accepted term:

```sh
./kanon synth examples/synth-choice.kan \
  --replay /tmp/kanon-choice-resolved.kan.synth.json \
  -o /tmp/kanon-choice-replayed.kan
```

Replay requires the same original source and compiler binary. A rebuilt compiler requires fresh synthesis or checking the saved ordinary source directly. Replaying a receipt is not an authorization to trust its contents: the original goal is reconstructed, request hashes must match, and the candidate is checked again. Receipts provide reproducibility and audit information, not cryptographic authentication of their author.

The initial assumption policy permits the built-in `Nat` postulate with its original type and rejects all source axioms, including unused axioms. Checking the complete prefix environment makes this policy stricter than a per-term dependency allowlist. Existing ordinary compiler commands retain their prior axiom behavior. The synthesis extension adds no kernel constructor, axiom or conversion rule.

The policy also refuses a source that redefines a name. The environment installs by overwrite, so a repeated name would be checked against the earlier entry and then replace it. Synthesis therefore rejects any declaration whose name is already bound in the preceding declarations or in the built-in environment. The rule applies to the synthesis hole itself, to every other declaration, and to every name a family or recursive group binds.

`--timeout` bounds each model process, including loading, and `--check-timeout` bounds each compiler subprocess. The driver kills the process group on a deadline or output overflow. Request, candidate, output and receipt sizes are capped, with at most eight holes and eight candidates per hole. These are explicit failures, never unchecked successful terms. The model provider is trusted executable tooling chosen by the user; model-generated expressions are data and are never shell commands.

The machine interfaces used by the driver are:

```text
kanon synth-request FILE
kanon synth-apply FILE --candidate CANDIDATE_FILE -o OUTPUT_FILE
```

The first emits the earliest typed request or `null` once the whole source checks. The second checks one expression and replaces that hole in reprinted source, preserving family declarations and later holes. These internal commands rely on the calling driver for process and byte limits. The driver performs a final full check before publishing either user artifact.

Run the targeted regression suites after building:

```sh
./_build/default/test/synthesis.exe
KANON_TEST_COMPILER="$PWD/_build/default/bin/kanon.exe" python3 dev/test_synth.py
```

The source snapshot includes the original project's existing staged work. `../kanon-snapshot.json` records its source hashes, and `../kanon-synth-baseline` retains the copied baseline for comparison. The source-only vendor submodule was excluded; the compiler build treats vendor files as data. The live repository changed concurrently after this snapshot, so the source patch must be integrated against that newer tree before adoption there. After you apply the patch, run `chmod +x kanon`. The patch carries no file mode headers, so the wrapper arrives without the execute bit and `./kanon ...` fails with permission denied.

This prototype does not establish a globally smallest useful model, full Lean 4 parity, a derivation of every trusted primitive from Kan extensions, or OCaml-speed compilation. Its validation record must distinguish real model execution, semantic task success, compiler checks, and remaining language-foundation work.

The recorded ranking demonstration produced `42` in kernel evaluation, Node and Wasmtime. Model-assisted materialization took 20.802 seconds including cold model startup; replay took 0.960 seconds with zero provider time and identical output source. System load was approximately 98, so these are observed demonstration timings, not controlled performance benchmarks. Saved source, Wasm and receipts are in [dev/synthesis-results](dev/synthesis-results). These receipts were recorded under the earlier compiler binary, before the redefinition rule and the provider failure reporting above. Replay of a saved receipt therefore reports a stale compiler until the record is regenerated. The saved ordinary source still checks directly.

The frozen six-case pilot scored 4/6 for both the 135M and 360M models, against 3/6 for taking the first candidate. This weak baseline and small sample do not satisfy the usefulness contract. The default stays 135M because the larger tested model showed no accuracy gain here. The next model milestone requires a larger independent corpus, a stronger deterministic baseline, and reliable task performance before selecting a production model.
