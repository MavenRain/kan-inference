/-
Copyright (c) 2026 Onyeka Obi. All rights reserved.
Released under MIT OR Apache 2.0 license.
-/

import KanonMeta.VectorConstruction

/-!
Regression for the constructed vector algebra. Naturals observe payloads;
their initiality and Lean's vector recursor are never premises. This checks
the semantic shape of mu-dependent-copy.kan, not its parser or compiler.
-/

namespace KanonMeta.VectorConstruction.Tests

open Initiality

def totalAlgebra : Algebra (polynomial Nat) where
  Carrier := fun (_n) => Nat
  roll := fun shape => match shape with
    | .inl .nil => fun (_xs) => 0
    | .inr (.cons (_n) value) => fun xs => value + xs PUnit.unit

def total {n : Nat} (xs : (recursive Nat).Carrier n) : Nat :=
  ((recursiveInitial Nat).fold totalAlgebra).map xs

theorem total_roll {n : Nat} (shape : (polynomial Nat).Shape n)
    (xs : (pos : (polynomial Nat).Position shape) →
      (recursive Nat).Carrier ((polynomial Nat).child shape pos)) :
    total ((recursive Nat).roll shape xs) =
      totalAlgebra.roll shape (fun pos => total (xs pos)) :=
  ((recursiveInitial Nat).fold totalAlgebra).comm shape xs

theorem total_nil : total nil = 0 :=
  total_roll (.inl .nil) (fun pos => nomatch pos)

theorem total_cons {n : Nat} (value : Nat) (tail : (recursive Nat).Carrier n) :
    total (cons value tail) = value + total tail :=
  total_roll (.inr (.cons n value)) (fun (_pos) => tail)

def values : (recursive Nat).Carrier 2 := cons 17 (cons 25 nil)

def copied : (recursive Nat).Carrier 2 := copy values

theorem total_values : total values = 42 :=
  (total_cons 17 (cons 25 nil)).trans
    (congrArg (Nat.add 17) ((total_cons 25 nil).trans
      (congrArg (Nat.add 25) total_nil)))

theorem total_copied : total copied = 42 :=
  (congrArg total (copy_eq values)).trans total_values

/-- The fibre depends on the actual vector, not just its length. -/
def counted : Displayed (recursive Nat) where
  Fibre := fun xs => {value : Nat // value = total xs}
  step := fun shape => match shape with
    | .inl .nil => fun xs (_ih) => ⟨0, (total_roll (.inl .nil) xs).symm⟩
    | .inr (.cons n value) => fun xs ih =>
      ⟨value + (ih PUnit.unit).val,
        (congrArg (Nat.add value) (ih PUnit.unit).property).trans
          (total_roll (.inr (.cons n value)) xs).symm⟩

def count {n : Nat} (xs : (recursive Nat).Carrier n) : counted.Fibre xs :=
  elim (recursiveInitial Nat) counted xs

theorem count_nil : (count nil).val = 0 :=
  congrArg Subtype.val
    (elim_beta (recursiveInitial Nat) counted (.inl .nil) (fun pos => nomatch pos))

theorem count_cons {n : Nat} (value : Nat) (tail : (recursive Nat).Carrier n) :
    (count (cons value tail)).val = value + (count tail).val :=
  congrArg Subtype.val
    (elim_beta (recursiveInitial Nat) counted (.inr (.cons n value)) (fun (_pos) => tail))

theorem count_values : (count values).val = 42 :=
  (count_cons 17 (cons 25 nil)).trans
    (congrArg (Nat.add 17) ((count_cons 25 nil).trans
      (congrArg (Nat.add 25) count_nil)))

theorem count_copied : (count copied).val = 42 :=
  (congrArg (fun xs : (recursive Nat).Carrier 2 => (count xs).val)
    (copy_eq values)).trans count_values

theorem total_singleton (value : Nat) : total (cons value nil) = value :=
  (total_cons value nil).trans (congrArg (Nat.add value) total_nil)

/-- Equal lengths do not collapse distinct constructor payloads. -/
theorem singleton_payload_ne {a b : Nat} (h : a ≠ b) : cons a nil ≠ cons b nil :=
  fun eq => h ((total_singleton a).symm.trans
    ((congrArg total eq).trans (total_singleton b)))

def erasingAlgebra : Algebra (polynomial Nat) where
  Carrier := (recursive Nat).Carrier
  roll := fun shape => match shape with
    | .inl .nil => fun (_xs) => nil
    | .inr (.cons (_n) (_value)) => fun xs => cons 0 (xs PUnit.unit)

def erase {n : Nat} (xs : (recursive Nat).Carrier n) : (recursive Nat).Carrier n :=
  ((recursiveInitial Nat).fold erasingAlgebra).map xs

theorem erase_nil : erase nil = nil :=
  ((recursiveInitial Nat).fold erasingAlgebra).comm (.inl .nil) (fun pos => nomatch pos)

theorem erase_cons {n : Nat} (value : Nat) (tail : (recursive Nat).Carrier n) :
    erase (cons value tail) = cons 0 (erase tail) :=
  ((recursiveInitial Nat).fold erasingAlgebra).comm
    (.inr (.cons n value)) (fun (_pos) => tail)

/-- Payload erasure preserves length but cannot preserve the original algebra. -/
theorem erasure_not_hom :
    ¬ ∃ f : Hom (recursive Nat) (recursive Nat),
      ∀ n (xs : (recursive Nat).Carrier n), f.map xs = erase xs :=
  fun ⟨f, agrees⟩ => singleton_payload_ne (Nat.succ_ne_zero 16)
    (((recursiveInitial Nat).unique (recursive Nat) (Hom.id (recursive Nat)) f
      (cons 17 nil)).trans
      ((agrees 1 (cons 17 nil)).trans
        ((erase_cons 17 nil).trans (congrArg (cons 0) erase_nil))))

#print axioms total_copied
#print axioms count_values
#print axioms count_copied
#print axioms singleton_payload_ne
#print axioms erasure_not_hom

end KanonMeta.VectorConstruction.Tests
