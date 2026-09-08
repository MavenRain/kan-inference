/-
Copyright (c) 2026 Onyeka Obi. All rights reserved.
Released under MIT OR Apache 2.0 license.
-/

import KanonMeta.LinearConstruction

/-!
Constructed initial length-indexed vectors with payloads in `Type`.
At payload type Nat, the nullary and unary shapes match the mathematical
signature used by mu-dependent-copy.kan, with Lean Nat as the length index.
This is a semantic model, not a translation theorem for parsed SMu.
-/

namespace KanonMeta.VectorConstruction

open Initiality

inductive NilShape : Nat → Type where
  | nil : NilShape 0

inductive ConsShape (A : Type) : Nat → Type where
  | cons (n : Nat) (value : A) : ConsShape A (n + 1)

def signature (A : Type) : LinearConstruction.Signature Nat where
  Nullary := NilShape
  Unary := ConsShape A
  child := fun shape => match shape with
    | .cons n (_value) => n

abbrev polynomial (A : Type) := (signature A).polynomial

abbrev recursive (A : Type) := LinearConstruction.recursive (signature A)

/-- Both colimit properties and initiality are constructed, with no premises. -/
def recursiveInitial (A : Type) : Initial (recursive A) :=
  LinearConstruction.recursiveInitial (signature A)

def nil {A : Type} : (recursive A).Carrier 0 :=
  (recursive A).roll (.inl .nil) (fun pos => nomatch pos)

def cons {A : Type} {n : Nat} (value : A) (tail : (recursive A).Carrier n) :
    (recursive A).Carrier (n + 1) :=
  (recursive A).roll (.inr (.cons n value)) (fun (_pos) => tail)

/-- The fold copies the constructor payload and preserves the length index. -/
def copy {A : Type} {n : Nat} (xs : (recursive A).Carrier n) :
    (recursive A).Carrier n :=
  ((recursiveInitial A).fold (recursive A)).map xs

theorem copy_eq {A : Type} {n : Nat} (xs : (recursive A).Carrier n) : copy xs = xs :=
  (recursiveInitial A).unique (recursive A)
    ((recursiveInitial A).fold (recursive A)) (Hom.id (recursive A)) xs

theorem copy_nil {A : Type} : copy (nil (A := A)) = nil := copy_eq nil

theorem copy_cons {A : Type} {n : Nat} (value : A) (tail : (recursive A).Carrier n) :
    copy (cons value tail) = cons value (copy tail) :=
  ((recursiveInitial A).fold (recursive A)).comm (.inr (.cons n value)) (fun (_pos) => tail)

end KanonMeta.VectorConstruction
