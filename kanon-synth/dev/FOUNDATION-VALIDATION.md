Validation for the foundation increment, 2026-09-06. Commands ran in the isolated source snapshot at `/Users/oobi/Documents/gpt15/kanon-work`, based on `ac94fe36c7fc7d4013a00d3fa102666e2cafdd0a` with Stage K staged changes and the seven concurrent edits recorded in `/Users/oobi/Documents/gpt15/evidence/concurrent-refresh.json`. The snapshot was refreshed before the final OCaml build and suite runs. This increment changes no compiler implementation file.

| Check | Result |
| --- | --- |
| `zsh dev/dunecho.sh build` | Zero errors and warnings. |
| `leancho --json`, from `meta` | Entire default package, including both test roots: zero errors, incomplete proofs, and warnings. |
| `lake +leanprover/lean4:v4.33.0-rc1 env lean Axioms.lean`, from `meta` | All existing substitution theorems and the new projection, eliminator, and section declarations report no axioms. `Initiality.elim_beta` reports exactly `Quot.sound`. The initiality argument remains an explicit parameter, not something this dependency report proves. |
| External source importing `KanonMeta` | Resolves the public `Initiality.elim` and `Initiality.elim_beta` declarations. |
| `_build/default/test/main.exe test` | PARSE 122/122, CHECK 74/74, ERASE 74/74, NEG 48/48, KNEG 2/2, REC 1/1, MIGRATED 4/4, SUITE-KERNEL OK. |
| `_build/default/test/wasm.exe test OUTDIR` | WASM 30/30, SUITE-WASM OK, including the new vector fixture. |
| Vector fixture with `kanon run ... --host kernel` and `--host both` | Each prints exactly `42` followed by a newline and exits zero. The latter compares Node and Wasmtime. |
| `kanon axioms test/fixtures/mu-dependent-copy.kan` | Empty axiom disclosure, exit zero. |
| Wrong-index fixture | Rejected with the exact constructor-index mismatch in its negative sidecar. |
| Payload mutation | A well-typed version that replaces copied payloads with zero returns zero on kernel and both Wasm hosts, differing from the fixed expectation of 42. |
| `zsh dev/encoder-subset.sh` | ENCODER-SUBSET OK. |
| `zsh dev/house.sh` | HOUSE OK. |
| `zsh dev/trusted-lines.sh` | Kernel 3997/4000, encoder 246/600. |

The Lean regression supplies a concrete Nat initial algebra using Lean's existing Nat recursor and proves a dependent counter in `Fin (n + 1)` returns three at input three. Its countermodel supplies folds into every algebra but has distinct identity and collapse morphisms; a valid displayed algebra over it has no dependent section. These are tests of the initiality bridge's meaning. The Nat instance is not a derivation of natural numbers from Kan extensions.

One declaration-local universe linter exception on `Polynomial` preserves independent shape and position universe levels that co-occur in its result sort. The comment states the reason. No global warning, kernel-checking, or test setting is weakened.

The standalone cost probe observed three stdout bytes and zero stderr bytes for the original vector run. Token counts are null because no model tokenizer was selected. Its single elapsed-time sample is not a compilation benchmark. No claim of OCaml-speed compilation, full Lean parity, judgmental beta, or strict Kan-only initial-algebra existence follows from this validation.

Full transcripts and source hashes are retained under `/Users/oobi/Documents/gpt15/evidence`. The dedicated Stage K exhaustive agreement and One-path helper batteries and the full timing-gate battery were not rerun for this metatheory and fixture increment; the ordinary kernel and Wasm suites were rerun after the concurrent source refresh.
