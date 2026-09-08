# kan-inference

Local model synthesis for Kanon, with compiler checking and behavioral
evaluation. An explicitly typed, nonrecursive definition can contain
`synth "hint"`. The model proposes or ranks expressions, the compiler
checks the complete definition against its original goal and context,
and accepted code is saved as ordinary source with a provenance receipt.
Replay rechecks saved terms without loading the model.

This is a prototype. The successful demonstration returns `42` through
kernel evaluation, Node and Wasmtime. SmolLM2-135M and 360M int8 each scored
4/6 on the original ranking pilot, against 3/6 for candidate order.
Direct generation failed the recorded identity probe. The experimental
default remains 135M; no model has passed the proposed usefulness contract.

The newer [32-task behavioral comparison](kanon-inference/results/diagnostic-135m-2026-09-07.json)
scored 9/32 for the 135M model, 32/32 for the deterministic baseline and 8/32 for
candidate order. All selected terms type-checked, and kernel evaluation, Node
and Wasmtime agreed. The corpus and baseline were developed together; these
results describe diagnostic coverage, not independent generalization.

| Location | Purpose |
| --- | --- |
| [kanon-synth](kanon-synth/SYNTHESIS.md) | Compiler snapshot, checked synthesis CLI, tests and saved demonstration |
| [kanon-inference](kanon-inference/README.md) | ONNX CPU provider, pinned model setup and original pilot evidence |
| [Diagnostic benchmark](kanon-inference/benchmarks/README.md) | Behavioral corpus and deterministic baseline |
| [Implementation status](implementation-status.md) | Completed work, measured results and remaining milestones |
| [Evaluation contract](evaluation-contract.json) | Proposed model, correctness and performance requirements |
| [Design](kanon-llm-design.md) | Trust boundary and broader language goals |
| [Source baseline](kanon-synth-baseline/) | Saved compiler source before synthesis changes |
| [Snapshot](kanon-snapshot.json) and [patch](kanon-synthesis.patch) | Original source hashes and compiler changes pending integration |

The compiler uses OCaml 5.2.1, Dune 3.24.2 and Zarith 1.14. The evaluation
tools use Python 3.12 and the standard library. These commands run from
the repository root with that toolchain installed:

```sh
make build
make test
```

For Python-only unit checks, use `make test-unit`. The model provider has
separate local dependencies and pinned weight downloads; follow its
[setup instructions](kanon-inference/README.md), then run
`make test-provider`. Models and environments are local installations,
excluded from Git. The prototype uses POSIX subprocess groups and targets
macOS or Linux.

Evaluate program behavior without a model, or with the installed 135M
profile:

```sh
make benchmark-baseline HOSTS=kernel OUTPUT=/tmp/kan-baseline.json
make benchmark-135m HOSTS=kernel,node,wasmtime OUTPUT=/tmp/kan-135m.json
```

The default is `HOSTS=kernel`, which needs no external host binary. On a
machine with Node and Wasmtime installed, run
`make benchmark-baseline HOSTS=kernel,node,wasmtime` to compare the three
hosts. A requested host without its binary on `PATH` stops the run with
the error code `host_unavailable`.

Choose a new output path for each run. Provider failures remain in the
report, and interrupted runs are marked incomplete. The diagnostic corpus
is developer-authored, with shared task families. It is not the independent
500-task evaluation required by the proposed selection contract. Execution
examples test behavior on those inputs, not universal correctness. Model
timings include process startup and loading; they are cold observations.

Node and Wasmtime checks require those hosts, zsh and ripgrep. The saved
ordinary demonstration can be checked after a fresh build:

```sh
cd kanon-synth
./kanon check dev/synthesis-results/synth-choice-resolved.kan
./kanon run dev/synthesis-results/synth-choice-resolved.kan --export main --host both
```

Saved receipts require the exact recorded compiler binary hash. A rebuilt
compiler can check the saved ordinary source, but may require fresh
synthesis receipts. The receipts in `kanon-synth/dev/synthesis-results` were
recorded under the earlier compiler binary, before the redefinition rule of
this review. Check the saved ordinary source directly, or record fresh
receipts. The `kanon check` command above passed on the saved source under
the rebuilt compiler. Historical Kanon carry/PIN gates and Lean metatheory
have local dependencies outside this repository; the build and test commands
above cover the synthesis experiment.

The local workspace is `~/Documents/kanon-inference`. Its inner
`kanon-inference/` provider directory retains the original sibling layout.
The former `~/Documents/gpt16` directory contains compatibility links for
existing environment scripts and historical references. Live Kanon at
`~/Documents/kanon` is a separate project; integrating this compiler patch
there remains unfinished.

Source licensing follows the included [MIT](LICENSE-MIT) and
[Apache 2.0](LICENSE-APACHE) licenses. Downloaded models and runtime
dependencies retain their own license notices, as described in the
provider documentation.
