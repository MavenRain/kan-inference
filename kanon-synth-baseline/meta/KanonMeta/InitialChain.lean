/-
Copyright (c) 2026 Onyeka Obi. All rights reserved.
Released under MIT OR Apache 2.0 license.
-/

import KanonMeta.Initiality

/-!
The initial-chain construction in the base category of indexed families.
Given a colimit of the initial sequence and preservation of that particular
colimit by the polynomial functor, its carrier admits an initial algebra.
Dependent elimination and propositional beta then follow from Initiality.

Both hypotheses are colimit universal properties of families, not initiality
or folds in the category of algebras. Colimits can be viewed as left Kan
extensions along the unique functor to a terminal category, but this module
does not introduce a categorical Kan record. It does not prove that Kanon's
closed shape grammar admits the countable sequence, construct its colimit,
or assert that every polynomial preserves countable colimits.

Indices, shapes, positions, carriers, and displayed fibres share `Type u`.
All equalities, including constructor preservation and dependent beta, are
propositional equalities in Lean's existing type theory.
-/

namespace KanonMeta.InitialChain

open Initiality

universe u

abbrev Family (Index : Type u) := Index → Type u

abbrev Map {Index : Type u} (X Y : Family Index) := ∀ i, X i → Y i

variable {Index : Type u} (P : Polynomial.{u, u, u} Index)

/-- The dependent polynomial on indexed families. -/
def polyObj (X : Family Index) : Family Index :=
  fun i => (shape : P.Shape i) × ((pos : P.Position shape) → X (P.child shape pos))

def polyMap {X Y : Family Index} (f : Map X Y) : Map (polyObj P X) (polyObj P Y) :=
  fun _i x => ⟨x.1, fun pos => f (P.child x.1 pos) (x.2 pos)⟩

theorem polyMap_id (X : Family Index) (i : Index) (x : polyObj P X i) :
    polyMap P (fun _i x => x) i x = x := rfl

theorem polyMap_comp {X Y Z : Family Index} (g : Map Y Z) (f : Map X Y)
    (i : Index) (x : polyObj P X i) :
    polyMap P (fun i z => g i (f i z)) i x =
      polyMap P g i (polyMap P f i x) := rfl

structure Sequence (Index : Type u) where
  obj : Nat → Family Index
  next : (n : Nat) → Map (obj n) (obj (n + 1))

/-- A compatible family of maps from the stages to a carrier. -/
structure Cocone (S : Sequence Index) (L : Family Index) where
  leg : (n : Nat) → Map (S.obj n) L
  comm : ∀ n i x, leg (n + 1) i (S.next n i x) = leg n i x

/-- The exact universal property in the category of `Type u` families.
Uniqueness is expressed by joint injectivity of restriction to the legs. -/
structure Colimit {S : Sequence Index} {L : Family Index} (c : Cocone S L) where
  descend : {Y : Family Index} → Cocone S Y → Map L Y
  factor : ∀ {Y : Family Index} (d : Cocone S Y) n i x,
    descend d i (c.leg n i x) = d.leg n i x
  unique : ∀ {Y : Family Index} (f g : Map L Y),
    (∀ n i x, f i (c.leg n i x) = g i (c.leg n i x)) →
      ∀ i x, f i x = g i x

def mappedSequence (S : Sequence Index) : Sequence Index where
  obj := fun n => polyObj P (S.obj n)
  next := fun n => polyMap P (S.next n)

def mappedCocone {S : Sequence Index} {L : Family Index}
    (c : Cocone S L) : Cocone (mappedSequence P S) (polyObj P L) where
  leg := fun n => polyMap P (c.leg n)
  comm := fun n _i x => congrArg (Sigma.mk x.1)
    (funext (fun pos => c.comm n (P.child x.1 pos) (x.2 pos)))

/-- The initial sequence starts at the empty family. -/
def stage : Nat → Family Index :=
  Nat.rec (fun _i => PEmpty) (fun _n X => polyObj P X)

def connecting : (n : Nat) → Map (stage P n) (stage P (n + 1)) :=
  Nat.rec (fun _i x => nomatch x) (fun _n f => polyMap P f)

def initialSequence : Sequence Index where
  obj := stage P
  next := connecting P

variable {P} {L : Family Index} (c : Cocone (initialSequence P) L)

/-- Dropping stage zero gives a cocone on the mapped sequence. -/
def tailCocone : Cocone (mappedSequence P (initialSequence P)) L where
  leg := fun n => c.leg (n + 1)
  comm := fun n i x => c.comm (n + 1) i x

variable (preserved : Colimit (mappedCocone P c))

/-- The structure map comes from the preserved base colimit. -/
def rollMap : Map (polyObj P L) L := preserved.descend (tailCocone c)

theorem roll_on_leg (n : Nat) (i : Index) (x : polyObj P (stage P n) i) :
    rollMap c preserved i (polyMap P (c.leg n) i x) = c.leg (n + 1) i x :=
  preserved.factor (tailCocone c) n i x

def chainAlgebra : Algebra.{u, u, u, u} P where
  Carrier := L
  roll := fun shape xs => rollMap c preserved _ ⟨shape, xs⟩

/-- Every algebra evaluates finite stages recursively from its constructors. -/
def algebraLeg (A : Algebra.{u, u, u, u} P) :
    (n : Nat) → Map (stage P n) A.Carrier :=
  Nat.rec (fun _i x => nomatch x)
    (fun _n leg _i x => A.roll x.1 (fun pos => leg (P.child x.1 pos) (x.2 pos)))

def algebraCocone (A : Algebra.{u, u, u, u} P) :
    Cocone (initialSequence P) A.Carrier where
  leg := algebraLeg A
  comm := Nat.rec (fun _i x => nomatch x)
    (fun _n ih _i x => congrArg (A.roll x.1)
      (funext (fun pos => ih (P.child x.1 pos) (x.2 pos))))

variable (colim : Colimit c)

/-- Base-colimit descent supplies the underlying map of the fold. -/
def foldMap (A : Algebra.{u, u, u, u} P) : Map L A.Carrier :=
  colim.descend (algebraCocone A)

/-- Preservation lets equality be checked on the mapped cocone's legs. -/
theorem fold_comm (A : Algebra.{u, u, u, u} P)
    (i : Index) (x : polyObj P L i) :
    foldMap c colim A i (rollMap c preserved i x) =
      A.roll x.1 (fun pos => foldMap c colim A (P.child x.1 pos) (x.2 pos)) :=
  preserved.unique
    (fun i z => foldMap c colim A i (rollMap c preserved i z))
    (fun _i z => A.roll z.1
      (fun pos => foldMap c colim A (P.child z.1 pos) (z.2 pos)))
    (fun n i z =>
      (congrArg (foldMap c colim A i) (roll_on_leg c preserved n i z)).trans
        ((colim.factor (algebraCocone A) (n + 1) i z).trans
          (congrArg (A.roll z.1)
            (funext (fun pos =>
              (colim.factor (algebraCocone A) n (P.child z.1 pos) (z.2 pos)).symm)))))
    i x

def foldHom (A : Algebra.{u, u, u, u} P) : Hom (chainAlgebra c preserved) A where
  map := fun {i} x => foldMap c colim A i x
  comm := fun {i} shape xs => fold_comm c preserved colim A i ⟨shape, xs⟩

/-- Constructor preservation forces every algebra map to evaluate each stage. -/
theorem hom_on_leg {A : Algebra.{u, u, u, u} P}
    (f : Hom (chainAlgebra c preserved) A) :
    ∀ n i x, f.map (c.leg n i x) = (algebraCocone A).leg n i x :=
  Nat.rec (fun _i x => nomatch x)
    (fun n ih _i x =>
      (congrArg f.map (roll_on_leg c preserved n _ x).symm).trans
        ((f.comm x.1 (fun pos => c.leg n (P.child x.1 pos) (x.2 pos))).trans
          (congrArg (A.roll x.1)
            (funext (fun pos => ih (P.child x.1 pos) (x.2 pos))))))

/-- Initiality is derived from the two base-category colimit hypotheses. -/
def chainInitial : Initial (chainAlgebra c preserved) where
  fold := foldHom c preserved colim
  unique := fun _A f g {i} x =>
    colim.unique (fun _i z => f.map z) (fun _i z => g.map z)
      (fun n i z => (hom_on_leg c preserved f n i z).trans
        (hom_on_leg c preserved g n i z).symm) i x

/-- Dependent elimination with both base-colimit hypotheses exposed. -/
def chainElim (D : Displayed (chainAlgebra c preserved))
    {i : Index} (x : L i) : D.Fibre x :=
  Initiality.elim (chainInitial c preserved colim) D x

theorem chainElim_beta (D : Displayed (chainAlgebra c preserved))
    {i : Index} (shape : P.Shape i)
    (xs : (pos : P.Position shape) → L (P.child shape pos)) :
    chainElim c preserved colim D ((chainAlgebra c preserved).roll shape xs) =
      D.step shape xs (fun pos => chainElim c preserved colim D (xs pos)) :=
  Initiality.elim_beta (chainInitial c preserved colim) D shape xs

end KanonMeta.InitialChain
