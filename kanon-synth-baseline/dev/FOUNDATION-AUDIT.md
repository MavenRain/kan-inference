This audit distinguishes implemented behavior from the mathematical obligations behind the strict Kan-only requirement. It covers the sources at `ac94fe36c7fc7d4013a00d3fa102666e2cafdd0a` plus the staged Stage K changes, as read on 2026-09-06. The new metatheory and regression files accompany this audit. No existing kernel rule is changed by this increment.

The [validation record](FOUNDATION-VALIDATION.md) lists the commands, outcomes, proof dependencies, and limits of the evidence, including the concurrent source refresh.

The later [initial-chain increment](INITIAL-CHAIN.md) constructs sequence colimits and a concrete recursive initial algebra. It advances the semantic existence argument while retaining the separate obligation to connect that construction to the compiler's admitted shapes. The [indexed construction](INDEXED-CONSTRUCTION.md) adds preservation for nullary/unary indexed signatures and a constructed vector model with payload-preserving copy.

The current implementation supplies useful inductive behavior, but a derivation of that behavior from Kan universal properties is not yet established. This is an evidence gap, not a counterexample to the implementation's soundness or to the possibility of a Kan-based construction.

| Obligation | Source evidence | Status |
| --- | --- | --- |
| Initial algebra | `lib/shape.ml` represents `SMu` by family name and indices. `lib/positivity.ml` stores the constructor table and positivity verdict. `lib/rules.ml` checks formation against those records. | No construction or proof of initiality is supplied by these representations. |
| Dependent case analysis | The mu rule pack checks motive family and arity, substitutes constructor result indices, and checks coverage and branch types. | Implemented directly. |
| Recursive induction | Branch contexts bind constructor fields. Recursive calls are checked separately by `Totality.guard_group` and `Order.certify`. | No derivation of this combination from initiality is established. |
| Constructor beta | `mu_beta` looks up the matching branch and evaluates it in the constructor-field environment. | Operational rule; correspondence with a universal-property derivation is open. |
| Mu uniqueness | The mu pack disables both definitional eta flags and provides no expansion. | Absence of definitional eta does not rule out propositional uniqueness. No such theorem for the compiler's mu interpretation is supplied here. |
| Substitution | `meta/KanonMeta/BeckChevalley.lean` proves four raw-syntax substitution equations for SPi and SColl by reflexivity. | These do not establish typed substitution preservation, semantic Beck-Chevalley, or mu substitution stability. |

The initiality bridge added in `meta/KanonMeta/Initiality.lean` makes one implication precise. An indexed polynomial signature specifies constructor shapes, recursive positions, and the index of each recursive child. An algebra supplies a carrier family and constructor operation. The `Initial` structure supplies a chosen algebra morphism to every algebra in the stated universe and pointwise uniqueness of all such morphisms.

Given that explicit initiality hypothesis and a displayed algebra:

1. Construct the total algebra whose elements pair a base element with its dependent witness.
2. Fold the initial algebra into that total algebra.
3. Use uniqueness to show that projection after folding is the identity on the base.
4. Transport the fold's witness along that equality to obtain `elim`.
5. Derive `elim_beta` from constructor preservation and the section law.

The resulting section and beta laws are propositional equalities. This module does not introduce judgmental reduction rules. Its carriers and displayed fibres both inhabit `Type a`; larger displayed universes and general `Sort` motives are not covered. The proof uses Lean's existing equality, dependent pairs, and function extensionality. It does not construct an initial algebra from Kan extensions or prove the compiler correct. `meta/Axioms.lean` provides exact dependency disclosure, including the bridge's public laws.

This argument follows the standard total-algebra route for dependent induction. The important next obligation is to provide initiality from the admitted Kan construction, rather than inserting the desired eliminator into the hypothesis. W-types as initial algebras and their stability are treated in [Gambino and Hyland](https://www.dpmms.cam.ac.uk/~jmeh1/Research/Publications/2004/gh04.pdf). Coherence under substitution is a separate obligation, as illustrated by [Lumsdaine and Warren](https://arxiv.org/abs/1411.1736).

The executable witness is `test/fixtures/mu-dependent-copy.kan`. It copies a vector while preserving its erased length index and retained natural-number payloads, then totals the copied payloads. The expected result is independently fixed as `17 + 25 = 42`. Its motive depends on the constructor's result index. The empty and successor cases execute, and the recursive call consumes the vector field.

The corresponding negative fixture, `test/neg/mu-dependent-copy-index.kan`, returns a successor-length vector in the zero-length branch. It must be rejected with the exact constructor-index mismatch recorded in its sidecar. Checked, erased, and Wasm goldens place the positive fixture in the existing mandatory suites. The erased program retains one vector argument for `copy`; length indices are absent from that runtime signature.

A separate validation mutation replaces each copied payload with zero. This variant remains well typed but computes zero on the kernel and both Wasm hosts. Comparing against the original expected result therefore detects a data-flow error as well as checking type rejection. This is a control for the witness's observable behavior, not a mutation of the kernel or a proof of general compilation correctness.

Lean parity remains a separate matrix:

| Feature | Current evidence and remaining work |
| --- | --- |
| Dependent functions, pairs, finite variants | Admitted SPi/SColl rule packs and tests; a complete typed semantic interpretation remains open. |
| Strictly positive indexed and mutual families | Implemented mu checking and structural recursion; this increment adds a dependent runtime witness and a conditional semantic bridge. |
| Nested inductives | Still deferred by the positivity policy. |
| Universe polymorphism | Closed levels exist; level variables remain deferred. |
| Impredicative proof-irrelevant Prop | Implemented rules exist, including a restricted large-elimination criterion; full parity and semantic justification remain open. |
| Equality and computational quotients | SPar is refused. This audit does not establish a complete identity/elimination library from other encodings. |
| General well-founded recursion | Structural recursion exists; the planned Acc-based route remains deferred. |
| Compiler preservation | Fixture agreement is evidence for those programs; no general erasure or code-generation preservation theorem is supplied. |

The reference feature set is the [Lean kernel documentation](https://lean-lang.org/doc/reference/latest/Elaboration-and-Compilation/#kernel); the metatheory toolchain is pinned separately by `meta/lean-toolchain`. A full parity claim needs a pinned source-language reference and a typing-preserving translation, not only a growing set of examples.

The next foundation increment should give a typed interpretation of one actual SMu signature, connect its constructor and recursive-call rules to the polynomial algebra, and prove initiality from the proposed Kan construction. It must state the category, admitted diagrams, existence assumptions, and substitution behavior. If extra existence or computation rules are needed, disclose them before claiming the strict primitive requirement has been met.
