/-
Copyright (c) 2026 Onyeka Obi. All rights reserved.
Released under MIT OR Apache 2.0 license.
-/

import KanonMeta.ChainColimit

/-!
Indexed signatures with nullary and unary recursive positions preserve
sequential colimits. Shapes retain arbitrary payloads, and a unary child's
index may differ from its parent's. This does not cover finite branching
with two or more recursive positions or establish compiler soundness.
Indices, payloads, and carriers share the universe required by InitialChain.
-/

namespace KanonMeta.LinearConstruction

open Initiality InitialChain

universe u

structure Signature (Index : Type u) where
  Nullary : Index → Type u
  Unary : Index → Type u
  child : {i : Index} → Unary i → Index

variable {Index : Type u}

def Signature.polynomial (Q : Signature Index) : Polynomial.{u, u, u} Index where
  Shape := fun i => Q.Nullary i ⊕ Q.Unary i
  Position := fun shape => match shape with
    | .inl (_shape) => PEmpty
    | .inr (_shape) => PUnit
  child := fun shape pos => match shape with
    | .inl (_shape) => nomatch pos
    | .inr unary => Q.child unary

variable (Q : Signature Index)

def nullaryNode (X : Family Index) {i : Index} (shape : Q.Nullary i) :
    polyObj Q.polynomial X i :=
  ⟨.inl shape, fun pos => nomatch pos⟩

def unaryNode {X : Family Index} {i : Index} (shape : Q.Unary i)
    (x : X (Q.child shape)) : polyObj Q.polynomial X i :=
  ⟨.inr shape, fun (_pos) => x⟩

theorem nullary_node {X : Family Index} {i : Index} (shape : Q.Nullary i)
    (xs : (pos : Q.polynomial.Position (.inl shape)) →
      X (Q.polynomial.child (.inl shape) pos)) :
    nullaryNode Q X shape = (⟨.inl shape, xs⟩ : polyObj Q.polynomial X i) :=
  congrArg (fun ys : (pos : Q.polynomial.Position (.inl shape)) →
    X (Q.polynomial.child (.inl shape) pos) =>
      (⟨.inl shape, ys⟩ : polyObj Q.polynomial X i))
    (funext (fun pos => nomatch pos))

theorem unary_node {X : Family Index} {i : Index} (shape : Q.Unary i)
    (xs : (pos : Q.polynomial.Position (.inr shape)) →
      X (Q.polynomial.child (.inr shape) pos)) :
    unaryNode Q shape (xs PUnit.unit) =
      (⟨.inr shape, xs⟩ : polyObj Q.polynomial X i) :=
  congrArg (fun ys : PUnit → X (Q.child shape) =>
    (⟨.inr shape, ys⟩ : polyObj Q.polynomial X i))
    (funext (fun pos => match pos with | .unit => rfl))

theorem map_nullary {X Y : Family Index} (f : Map X Y)
    {i : Index} (shape : Q.Nullary i) :
    polyMap Q.polynomial f i (nullaryNode Q X shape) = nullaryNode Q Y shape :=
  (nullary_node Q shape _).symm

variable {S : Sequence Index} {L : Family Index}

/-- A cocone at one index extends to families by an equality argument.
This avoids choosing values in unrelated fibres. -/
def fibreCocone {j : Index} {Y : Type u}
    (leg : (n : Nat) → S.obj n j → Y)
    (comm : ∀ n x, leg (n + 1) (S.next n j x) = leg n x) :
    Cocone S (fun i => i = j → Y) where
  leg := fun n _i x e => leg n (e ▸ x)
  comm := fun n i x => funext (fun e : i = j =>
    Eq.rec (motive := fun k (eq : j = k) => (z : S.obj n k) →
      leg (n + 1) (eq.symm ▸ S.next n k z) = leg n (eq.symm ▸ z))
      (fun z => comm n z) e.symm x)

variable {c : Cocone S L} (colim : Colimit c)

def fibreDescend {j : Index} {Y : Type u}
    (leg : (n : Nat) → S.obj n j → Y)
    (comm : ∀ n x, leg (n + 1) (S.next n j x) = leg n x) : L j → Y :=
  fun x => colim.descend (fibreCocone leg comm) j x rfl

theorem fibre_factor {j : Index} {Y : Type u}
    (leg : (n : Nat) → S.obj n j → Y)
    (comm : ∀ n x, leg (n + 1) (S.next n j x) = leg n x)
    (n : Nat) (x : S.obj n j) :
    fibreDescend colim leg comm (c.leg n j x) = leg n x :=
  congrFun (colim.factor (fibreCocone leg comm) n j x) rfl

include colim in
theorem fibre_unique {j : Index} {Y : Type u} (f g : L j → Y)
    (h : ∀ n x, f (c.leg n j x) = g (c.leg n j x)) (x : L j) : f x = g x :=
  congrFun (colim.unique (Y := fun i => i = j → Y)
    (fun _i z e => f (e ▸ z))
    (fun _i z e => g (e ▸ z))
    (fun n i z => funext (fun e : i = j =>
      Eq.rec (motive := fun k (eq : j = k) => (w : S.obj n k) →
        f (eq.symm ▸ c.leg n k w) = g (eq.symm ▸ c.leg n k w))
        (fun w => h n w) e.symm z)) j x) rfl

variable {Y : Family Index}

theorem nullary_legs (d : Cocone (mappedSequence Q.polynomial S) Y)
    {i : Index} (shape : Q.Nullary i) :
    ∀ n, d.leg n i (nullaryNode Q (S.obj n) shape) =
      d.leg 0 i (nullaryNode Q (S.obj 0) shape) :=
  Nat.rec rfl (fun n ih =>
    (congrArg (d.leg (n + 1) i) (map_nullary Q (S.next n) shape).symm).trans
      ((d.comm n i (nullaryNode Q (S.obj n) shape)).trans ih))

def descend (d : Cocone (mappedSequence Q.polynomial S) Y) :
    Map (polyObj Q.polynomial L) Y :=
  fun i x => match x with
    | ⟨.inl shape, (_xs)⟩ => d.leg 0 i (nullaryNode Q (S.obj 0) shape)
    | ⟨.inr shape, xs⟩ => fibreDescend colim
        (fun n z => d.leg n i (unaryNode Q shape z))
        (fun n z => d.comm n i (unaryNode Q shape z)) (xs PUnit.unit)

/-- Preservation is proved for every sequence, including changed child indices. -/
def preserves : Colimit (mappedCocone Q.polynomial c) where
  descend := descend Q colim
  factor := fun d n i x => match x with
    | ⟨.inl shape, xs⟩ => (nullary_legs Q d shape n).symm.trans
        (congrArg (d.leg n i) (nullary_node Q shape xs))
    | ⟨.inr shape, xs⟩ =>
        (fibre_factor colim
          (fun k z => d.leg k i (unaryNode Q shape z))
          (fun k z => d.comm k i (unaryNode Q shape z)) n (xs PUnit.unit)).trans
          (congrArg (d.leg n i) (unary_node Q shape xs))
  unique := fun f g h i x => match x with
    | ⟨.inl shape, xs⟩ =>
        (congrArg (f i)
          ((map_nullary Q (c.leg 0) shape).trans (nullary_node Q shape xs)).symm).trans
          ((h 0 i (nullaryNode Q (S.obj 0) shape)).trans
            (congrArg (g i)
              ((map_nullary Q (c.leg 0) shape).trans (nullary_node Q shape xs))))
    | ⟨.inr shape, xs⟩ =>
        (congrArg (f i) (unary_node Q shape xs).symm).trans
          ((fibre_unique colim
            (fun z => f i (unaryNode Q shape z))
            (fun z => g i (unaryNode Q shape z))
            (fun n z => h n i (unaryNode Q shape z)) (xs PUnit.unit)).trans
            (congrArg (g i) (unary_node Q shape xs)))

abbrev recursiveSequence := initialSequence Q.polynomial

def recursivePreserved : Colimit
    (mappedCocone Q.polynomial (ChainColimit.cocone (recursiveSequence Q))) :=
  preserves Q (ChainColimit.isColimit (recursiveSequence Q))

/-- The carrier is the quotient of the signature's finite initial stages. -/
def recursive : Algebra Q.polynomial :=
  chainAlgebra (ChainColimit.cocone (recursiveSequence Q)) (recursivePreserved Q)

/-- No initiality or colimit universal property is supplied by the caller. -/
def recursiveInitial : Initial (recursive Q) :=
  chainInitial (ChainColimit.cocone (recursiveSequence Q)) (recursivePreserved Q)
    (ChainColimit.isColimit (recursiveSequence Q))

end KanonMeta.LinearConstruction
