/-
Copyright (c) 2026 Onyeka Obi. All rights reserved.
Released under MIT OR Apache 2.0 license.
-/

import KanonMeta.NatConstruction

/-!
Regression checks for the recursive initial algebra constructed from its
quotient chain colimit. Lean's naturals serve only as an observation algebra.
-/

namespace KanonMeta.InitialChain.Tests

open Initiality NatConstruction

def three : recursive.Carrier () := succ (succ (succ zero))

/-- Lean's naturals are an observation algebra, not an initiality premise. -/
def natural : Algebra natPolynomial where
  Carrier := fun (_i) => Nat
  roll := fun shape xs => match shape with
    | .zero => 0
    | .succ => Nat.succ (xs ())

def observe {i : Unit} (x : recursive.Carrier i) : Nat :=
  (recursiveInitial.fold natural).map x

theorem observe_roll {i : Unit} (shape : natPolynomial.Shape i)
    (xs : (pos : natPolynomial.Position shape) →
      recursive.Carrier (natPolynomial.child shape pos)) :
    observe (recursive.roll shape xs) =
      natural.roll shape (fun pos => observe (xs pos)) :=
  (recursiveInitial.fold natural).comm shape xs

theorem observe_zero : observe zero = 0 :=
  observe_roll .zero (fun pos => nomatch pos)

theorem observe_succ (x : recursive.Carrier ()) : observe (succ x) = Nat.succ (observe x) :=
  observe_roll .succ (fun (_pos) => x)

theorem observe_three : observe three = 3 :=
  (observe_succ (succ (succ zero))).trans
    (congrArg Nat.succ ((observe_succ (succ zero)).trans
      (congrArg Nat.succ ((observe_succ zero).trans
        (congrArg Nat.succ observe_zero)))))

/-- Each recursive step retains evidence that its count matches observation. -/
def counted : Displayed recursive where
  Fibre := fun x => {n : Nat // n = observe x}
  step := fun shape => match shape with
    | .zero => fun xs (_ih) => ⟨0, (observe_roll .zero xs).symm⟩
    | .succ => fun xs ih =>
      ⟨Nat.succ (ih ()).val,
        (congrArg Nat.succ (ih ()).property).trans (observe_roll .succ xs).symm⟩

def count {i : Unit} (x : recursive.Carrier i) : counted.Fibre x :=
  elim recursiveInitial counted x

theorem count_zero : (count zero).val = 0 :=
  congrArg Subtype.val
    (elim_beta recursiveInitial counted (i := ()) .zero (fun pos => nomatch pos))

theorem count_succ (x : recursive.Carrier ()) :
    (count (succ x)).val = Nat.succ (count x).val :=
  congrArg Subtype.val
    (elim_beta recursiveInitial counted (i := ()) .succ (fun (_pos) => x))

/-- Three dependent beta steps compute through the constructed initiality. -/
theorem count_three : (count three).val = 3 :=
  (count_succ (succ (succ zero))).trans
    (congrArg Nat.succ ((count_succ (succ zero)).trans
      (congrArg Nat.succ ((count_succ zero).trans
        (congrArg Nat.succ count_zero)))))

theorem zero_ne_succ_zero : zero ≠ succ zero :=
  fun h => Nat.noConfusion
    (observe_zero.symm.trans
      ((congrArg observe h).trans
        ((observe_succ zero).trans (congrArg Nat.succ observe_zero))))

/-- A constant map fails the unary constructor law on this genuine carrier. -/
theorem collapse_not_hom :
    ¬ ∃ f : Hom recursive recursive, ∀ x : recursive.Carrier (), f.map x = zero :=
  fun ⟨f, constant⟩ => zero_ne_succ_zero
    ((constant (succ zero)).symm.trans
      ((f.comm .succ (fun (_pos) => zero)).trans
        (congrArg (recursive.roll .succ)
          (funext (fun (_pos) => constant zero)))))

#print axioms observe_three
#print axioms count_three
#print axioms collapse_not_hom

end KanonMeta.InitialChain.Tests
