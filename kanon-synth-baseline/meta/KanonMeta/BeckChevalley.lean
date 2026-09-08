/-
Copyright (c) 2026 Onyeka Obi.  All rights reserved.
Released under MIT OR Apache 2.0 license.

Beck-Chevalley for the two formers over the two admitted shapes.

The statement form is the design verdict's, at
kan-lang-design-verdict.md:164-166: substitution slides through an open
shape, `(Lan_s A)[sigma] = Lan_{s[sigma]} (A[sigma^+])`, and the same for
`Ran`, proved one shape at a time.  Each theorem mirrors one eta row of
SPEC.md section 4.

The proofs use kan-tactics only (M1-PLAN.md:182).  `kan_rfl` closes each
goal because `subst` is structurally recursive, so the two sides are
definitionally equal.
-/

import KanonMeta.Subst
import KanTactics

namespace KanonMeta

/-- Lan at the point shape.  Mirrors SPEC.md:163.  `up sigma` is
`sigma^+` because the point diagram opens one binder
(lib/rules.ml:635). -/
theorem bc_lan_spi (sigma : Subst) (A : Term) (q : Quantity) (x : String)
    (dom : Term) :
    subst sigma (Term.lan (Shape.SPi q x dom) A)
      = Term.lan (Shape.SPi q x (subst sigma dom)) (subst (up sigma) A) := by
  kan_rfl

/-- Ran at the point shape.  Mirrors SPEC.md:162. -/
theorem bc_ran_spi (sigma : Subst) (A : Term) (q : Quantity) (x : String)
    (dom : Term) :
    subst sigma (Term.ran (Shape.SPi q x dom) A)
      = Term.ran (Shape.SPi q x (subst sigma dom)) (subst (up sigma) A) := by
  kan_rfl

/-- Lan at the collection shape.  Mirrors SPEC.md:165, the row with no
eta.  The shape action is the identity here because `SColl` holds an
`int` and no term (lib/shape.ml:12), and `sigma^+` is `sigma` because the
collection diagram opens no binder (lib/rules.ml:637). -/
theorem bc_lan_scoll (sigma : Subst) (A : Term) (n : Nat) :
    subst sigma (Term.lan (Shape.SColl n) A)
      = Term.lan (Shape.SColl n) (subst sigma A) := by
  kan_rfl

/-- Ran at the collection shape.  Mirrors SPEC.md:164, the row that gives
Unit its eta at `SColl 0`. -/
theorem bc_ran_scoll (sigma : Subst) (A : Term) (n : Nat) :
    subst sigma (Term.ran (Shape.SColl n) A)
      = Term.ran (Shape.SColl n) (subst sigma A) := by
  kan_rfl

end KanonMeta
