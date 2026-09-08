/-
Copyright (c) 2026 Onyeka Obi. All rights reserved.
Released under MIT OR Apache 2.0 license.

Concrete models for the conditional initiality bridge. Nat's initiality
is established using Lean's existing Nat recursor, not inferred from Kan
extensions. The negative model has an unconstrained extra inhabitant.
-/

import KanonMeta.Initiality

namespace KanonMeta.Initiality.Tests

inductive NatShape where
  | zero
  | succ

def natPolynomial : Polynomial Unit where
  Shape := fun (_i) => NatShape
  Position := fun shape => match shape with
    | .zero => Empty
    | .succ => Unit
  child := fun (_shape) (_pos) => ()

def natural : Algebra natPolynomial where
  Carrier := fun (_i) => Nat
  roll := fun shape xs => match shape with
    | .zero => 0
    | .succ => Nat.succ (xs ())

def foldNat (B : Algebra natPolynomial) : Nat → B.Carrier () :=
  Nat.rec (B.roll .zero (fun pos => nomatch pos))
    (fun (_n) ih => B.roll .succ (fun (_pos) => ih))

def foldNatHom (B : Algebra natPolynomial) : Hom natural B where
  map := fun {i} => match i with | () => foldNat B
  comm := fun {i} => match i with
    | () => fun shape => match shape with
      | .zero => fun (_xs) =>
        congrArg (B.roll .zero) (funext (fun pos => nomatch pos))
      | .succ => fun (_xs) =>
        congrArg (B.roll .succ) (funext (fun pos => match pos with | () => rfl))

def natInitial : Initial natural where
  fold := foldNatHom
  unique := fun B f g {i} => match i with
    | () => Nat.rec
      ((f.comm .zero Empty.elim).trans
        ((congrArg (B.roll .zero) (funext (fun pos => nomatch pos))).trans
          (g.comm .zero Empty.elim).symm))
      (fun n ih =>
        (f.comm .succ (fun (_pos) => n)).trans
          ((congrArg (B.roll .succ) (funext (fun (_pos) => ih))).trans
            (g.comm .succ (fun (_pos) => n)).symm))

/-- The dependent fibre grows with the input, and each step uses its witness. -/
def boundedCount : Displayed natural where
  Fibre := fun (n : Nat) => Fin (n + 1)
  step := fun shape => match shape with
    | .zero => fun (_xs) (_ih) => ⟨0, Nat.zero_lt_succ 0⟩
    | .succ => fun (_xs) ih => (ih ()).succ

def count (n : Nat) : Fin (n + 1) := elim natInitial boundedCount (i := ()) n

theorem count_zero : count 0 = ⟨0, Nat.zero_lt_succ 0⟩ :=
  elim_beta natInitial boundedCount (i := ()) .zero Empty.elim

theorem count_succ (n : Nat) : count (n + 1) = (count n).succ :=
  elim_beta natInitial boundedCount (i := ()) .succ (fun (_pos) => n)

theorem count_three : (count 3).val = 3 :=
  congrArg Fin.val
    ((count_succ 2).trans
      (congrArg Fin.succ ((count_succ 1).trans
        (congrArg Fin.succ ((count_succ 0).trans
          (congrArg Fin.succ count_zero))))))

theorem nat_projection (n : Nat) :
    ((natInitial.fold boundedCount.total).map (i := ()) n).1 = n :=
  projection_fold natInitial boundedCount n

/-- One nullary constructor at each of two distinct indices. -/
def pointPolynomial : Polynomial Bool where
  Shape := fun (_i) => Unit
  Position := fun (_shape) => Empty
  child := fun {_i} (_shape) pos => nomatch pos

def junk : Algebra pointPolynomial where
  Carrier := fun (_i) => Bool
  roll := fun (_shape) (_xs) => false

/-- This preserves the sole constructor but disagrees with identity on junk. -/
def collapse : Hom junk junk where
  map := fun (_x) => false
  comm := fun (_shape) (_xs) => rfl

/-- Folds exist to every algebra, so existence alone does not suffice. -/
def junkFold (B : Algebra pointPolynomial) : Hom junk B where
  map := fun (_x) => B.roll () (fun pos => nomatch pos)
  comm := fun shape => match shape with
    | () => fun (_xs) =>
      congrArg (B.roll ()) (funext (fun pos => nomatch pos))

theorem junk_not_initial : ¬ Nonempty (Initial junk) :=
  fun ⟨h⟩ => Bool.noConfusion
    (h.unique junk collapse (Hom.id junk) (i := false) true)

/-- A valid displayed algebra whose fibre over the extra inhabitant is empty. -/
def missingWitness : Displayed junk where
  Fibre := fun (b : Bool) => if b then Empty else Unit
  step := fun (_shape) (_xs) (_ih) => ()

theorem junk_no_section :
    ¬ Nonempty ({i : Bool} → (x : junk.Carrier i) → missingWitness.Fibre x) :=
  fun ⟨chooseWitness⟩ => Empty.elim (chooseWitness (i := true) true)

#print axioms natInitial
#print axioms count_three
#print axioms nat_projection
#print axioms junkFold
#print axioms junk_not_initial
#print axioms junk_no_section

end KanonMeta.Initiality.Tests
