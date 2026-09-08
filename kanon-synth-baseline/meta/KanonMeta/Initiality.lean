/-
Copyright (c) 2026 Onyeka Obi. All rights reserved.
Released under MIT OR Apache 2.0 license.
-/

import Init

/-!
An explicit initiality hypothesis gives dependent elimination for indexed
polynomial algebras. This is a conditional semantic bridge: it does not
construct initial algebras from Kan extensions, justify the compiler's
inductive rules, or assert semantic naturality of the syntax substitution
lemmas in BeckChevalley.

Indices, shapes, and positions may have independent universes `u`, `s`, and
`p`. Carriers and displayed fibres both lie in `Type a`; initiality ranges
over algebras at that same carrier universe. Larger displayed universes,
`Sort`-valued motives, and universe cumulativity are outside this statement.
The section and computation laws are propositional equalities, not new
judgmental reduction rules. All proofs use Lean's existing equality,
dependent pairs, and function extensionality.
-/

namespace KanonMeta.Initiality

universe u s p a

set_option linter.checkUnivs false in
/-- A strictly positive indexed signature with explicit recursive indices.
The declaration-local linter exception preserves independent shape and
position levels: both occur together in the structure's result sort. -/
structure Polynomial (Index : Type u) where
  Shape : Index → Type s
  Position : {i : Index} → Shape i → Type p
  child : {i : Index} → (shape : Shape i) → Position shape → Index

variable {Index : Type u} (P : Polynomial.{u, s, p} Index)

/-- An algebra for the indexed polynomial specified by `P`. -/
structure Algebra where
  Carrier : Index → Type a
  roll : {i : Index} → (shape : P.Shape i) →
    ((pos : P.Position shape) → Carrier (P.child shape pos)) → Carrier i

variable {P}

/-- Algebra maps preserve constructors propositionally. -/
structure Hom (A B : Algebra.{u, s, p, a} P) where
  map : {i : Index} → A.Carrier i → B.Carrier i
  comm : ∀ {i : Index} (shape : P.Shape i) (xs),
    map (A.roll shape xs) = B.roll shape (fun pos => map (xs pos))

def Hom.id (A : Algebra.{u, s, p, a} P) : Hom A A where
  map := fun x => x
  comm := fun _ _ => rfl

def Hom.comp {A B C : Algebra.{u, s, p, a} P}
    (g : Hom B C) (f : Hom A B) : Hom A C where
  map := fun x => g.map (f.map x)
  comm := fun shape xs =>
    (congrArg g.map (f.comm shape xs)).trans (g.comm shape _)

/-- Chosen folds and uniqueness among all algebra morphisms, at `Type a`. -/
structure Initial (A : Algebra.{u, s, p, a} P) where
  fold : (B : Algebra.{u, s, p, a} P) → Hom A B
  unique : ∀ (B : Algebra.{u, s, p, a} P) (f g : Hom A B)
    {i : Index} (x : A.Carrier i), f.map x = g.map x

/-- A dependent constructor interpretation over `A`. -/
structure Displayed (A : Algebra.{u, s, p, a} P) where
  Fibre : {i : Index} → A.Carrier i → Type a
  step : ∀ {i : Index} (shape : P.Shape i) (xs),
    ((pos : P.Position shape) → Fibre (xs pos)) → Fibre (A.roll shape xs)

variable {A : Algebra.{u, s, p, a} P}

/-- The total algebra retains both a base element and its dependent witness. -/
def Displayed.total (D : Displayed A) : Algebra.{u, s, p, a} P where
  Carrier := fun i => (x : A.Carrier i) × D.Fibre x
  roll := fun shape xs =>
    ⟨A.roll shape (fun pos => (xs pos).1),
      D.step shape (fun pos => (xs pos).1) (fun pos => (xs pos).2)⟩

def Displayed.projection (D : Displayed A) : Hom D.total A where
  map := Sigma.fst
  comm := fun _ _ => rfl

/-- Uniqueness makes the projection after folding the identity on the base. -/
theorem projection_fold (h : Initial A) (D : Displayed A)
    {i : Index} (x : A.Carrier i) : ((h.fold D.total).map x).1 = x :=
  h.unique A (D.projection.comp (h.fold D.total)) (Hom.id A) x

/-- Transport the witness along the proven section law. -/
def elim (h : Initial A) (D : Displayed A) {i : Index}
    (x : A.Carrier i) : D.Fibre x :=
  (projection_fold h D x) ▸ ((h.fold D.total).map x).2

private theorem pair_transport {X : Type a} {F : X → Type a}
    {x y : X} (w : F x) (e : x = y) :
    (⟨x, w⟩ : Sigma F) = ⟨y, e ▸ w⟩ :=
  Eq.rec (motive := fun y e => (⟨x, w⟩ : Sigma F) = ⟨y, e ▸ w⟩) rfl e

/-- The chosen fold is the graph of the dependent eliminator. -/
theorem fold_eq_section (h : Initial A) (D : Displayed A)
    {i : Index} (x : A.Carrier i) :
    (h.fold D.total).map x = ⟨x, elim h D x⟩ :=
  pair_transport ((h.fold D.total).map x).2 (projection_fold h D x)

/-- Dependent beta follows from preservation of constructors and the section
law. It is propositional; proof transport need not reduce by computation. -/
theorem elim_beta (h : Initial A) (D : Displayed A)
    {i : Index} (shape : P.Shape i)
    (xs : (pos : P.Position shape) → A.Carrier (P.child shape pos)) :
    elim h D (A.roll shape xs) =
      D.step shape xs (fun pos => elim h D (xs pos)) :=
  eq_of_heq (Sigma.mk.inj
    ((fold_eq_section h D (A.roll shape xs)).symm.trans
      (((h.fold D.total).comm shape xs).trans
        (congrArg (D.total.roll shape)
          (funext (fun pos => fold_eq_section h D (xs pos))))))).2

end KanonMeta.Initiality
