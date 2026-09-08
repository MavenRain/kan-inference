/-
Copyright (c) 2026 Onyeka Obi. All rights reserved.
Released under MIT OR Apache 2.0 license.
-/

import KanonMeta.ChainColimit

/-!
The recursive polynomial `1 + X` preserves every sequential colimit.
The preservation proof uses only the colimit universal property and the
single recursive position. No initial algebra is an input to this proof.
-/

namespace KanonMeta.NatConstruction

open Initiality InitialChain

inductive NatShape where
  | zero
  | succ

def natPolynomial : Polynomial Unit where
  Shape := fun (_i) => NatShape
  Position := fun shape => match shape with
    | .zero => Empty
    | .succ => Unit
  child := fun (_shape) (_pos) => ()

def zeroNode (X : Family Unit) (i : Unit) : polyObj natPolynomial X i :=
  ⟨.zero, fun pos => nomatch pos⟩

def succNode {X : Family Unit} (x : X ()) : polyObj natPolynomial X () :=
  ⟨.succ, fun (_pos) => x⟩

theorem map_zero {X Y : Family Unit} (f : Map X Y) (i : Unit) :
    polyMap natPolynomial f i (zeroNode X i) = zeroNode Y i :=
  congrArg (fun ys : Empty → Y () => (⟨.zero, ys⟩ : polyObj natPolynomial Y i))
    (funext (fun pos => nomatch pos))

theorem zero_node {X : Family Unit} (i : Unit)
    (xs : (pos : natPolynomial.Position (i := i) .zero) →
      X (natPolynomial.child .zero pos)) :
    zeroNode X i = (⟨.zero, xs⟩ : polyObj natPolynomial X i) :=
  congrArg (fun ys : Empty → X () => (⟨.zero, ys⟩ : polyObj natPolynomial X i))
    (funext (fun pos => nomatch pos))

theorem succ_node {X : Family Unit}
    (xs : (pos : natPolynomial.Position (i := ()) .succ) →
      X (natPolynomial.child .succ pos)) :
    succNode (xs ()) = (⟨.succ, xs⟩ : polyObj natPolynomial X ()) :=
  congrArg (fun ys : Unit → X () => (⟨.succ, ys⟩ : polyObj natPolynomial X ()))
    (funext (fun pos => match pos with | () => rfl))

variable {S : Sequence Unit} {L Y : Family Unit}

/-- The nullary branch is constant along the connected sequence. -/
theorem zero_legs (d : Cocone (mappedSequence natPolynomial S) Y) :
    ∀ n i, d.leg n i (zeroNode (S.obj n) i) =
      d.leg 0 i (zeroNode (S.obj 0) i) :=
  Nat.rec (fun (_i) => rfl)
    (fun n ih i =>
      (congrArg (d.leg (n + 1) i) (map_zero (S.next n) i).symm).trans
        ((d.comm n i (zeroNode (S.obj n) i)).trans (ih i)))

/-- Restriction to the one recursive position gives an ordinary cocone. -/
def successorCocone (d : Cocone (mappedSequence natPolynomial S) Y) : Cocone S Y where
  leg := fun n i => match i with
    | () => fun x => d.leg n () (succNode x)
  comm := fun n i => match i with
    | () => fun x => d.comm n () (succNode x)

def natDescend {c : Cocone S L} (colim : Colimit c)
    (d : Cocone (mappedSequence natPolynomial S) Y) :
    Map (polyObj natPolynomial L) Y :=
  fun i => match i with
    | () => fun x => match x with
      | ⟨.zero, (_children)⟩ => d.leg 0 () (zeroNode (S.obj 0) ())
      | ⟨.succ, xs⟩ => colim.descend (successorCocone d) () (xs ())

/-- This proves preservation rather than assuming it for the recursive model. -/
def natPreserves {c : Cocone S L} (colim : Colimit c) :
    Colimit (mappedCocone natPolynomial c) where
  descend := natDescend colim
  factor := fun d n i => match i with
    | () => fun x => match x with
      | ⟨.zero, xs⟩ =>
        (zero_legs d n ()).symm.trans
          (congrArg (d.leg n ()) (zero_node () xs))
      | ⟨.succ, xs⟩ =>
        (colim.factor (successorCocone d) n () (xs ())).trans
          (congrArg (d.leg n ()) (succ_node xs))
  unique := fun f g h i => match i with
    | () => fun x => match x with
      | ⟨.zero, xs⟩ =>
        (congrArg (f ())
          ((map_zero (c.leg 0) ()).trans (zero_node () xs)).symm).trans
          ((h 0 () (zeroNode (S.obj 0) ())).trans
            (congrArg (g ())
              ((map_zero (c.leg 0) ()).trans (zero_node () xs))))
      | ⟨.succ, xs⟩ =>
        (congrArg (f ()) (succ_node xs).symm).trans
          ((colim.unique
            (fun i => match i with | () => fun z => f () (succNode z))
            (fun i => match i with | () => fun z => g () (succNode z))
            (fun n i => match i with | () => fun z => h n () (succNode z))
            () (xs ())).trans
            (congrArg (g ()) (succ_node xs)))

/-- The carrier is the constructed quotient of finite polynomial stages. -/
abbrev recursiveSequence := initialSequence natPolynomial

def recursivePreserved : Colimit
    (mappedCocone natPolynomial (ChainColimit.cocone recursiveSequence)) :=
  natPreserves (ChainColimit.isColimit recursiveSequence)

def recursive : Algebra natPolynomial :=
  chainAlgebra (ChainColimit.cocone recursiveSequence) recursivePreserved

/-- Both colimit premises have checked constructions in this instance. -/
def recursiveInitial : Initial recursive :=
  chainInitial (ChainColimit.cocone recursiveSequence) recursivePreserved
    (ChainColimit.isColimit recursiveSequence)

def zero : recursive.Carrier () := recursive.roll .zero (fun pos => nomatch pos)

def succ (x : recursive.Carrier ()) : recursive.Carrier () :=
  recursive.roll .succ (fun (_pos) => x)

end KanonMeta.NatConstruction
