/-
Copyright (c) 2026 Onyeka Obi. All rights reserved.
Released under MIT OR Apache 2.0 license.
-/

import KanonMeta.InitialChain

/-!
Construct the colimit of any sequence of indexed Type families, pointwise,
by identifying each tagged stage element with its image at the next stage.
This supplies an actual universal-property witness, with no colimit-existence
hypothesis. It uses Lean's quotient machinery in the metatheory. It does not
assert that Kanon's closed shape grammar already admits this countable
diagram, nor that every polynomial preserves its colimit.
-/

namespace KanonMeta.ChainColimit

open InitialChain

universe u

variable {Index : Type u} (S : Sequence Index)

/-- A value together with the finite stage where it appears. -/
abbrev Tagged (i : Index) := (n : Nat) × S.obj n i

/-- Adjacent-stage identifications generate the quotient equality. -/
def step (i : Index) (a b : Tagged S i) : Prop :=
  b = ⟨a.1 + 1, S.next a.1 i a.2⟩

def carrier : Family Index := fun i => Quot (step S i)

def cocone : Cocone S (carrier S) where
  leg := fun n i x => Quot.mk (step S i) ⟨n, x⟩
  comm := fun n i x =>
    (Quot.sound (show step S i ⟨n, x⟩ ⟨n + 1, S.next n i x⟩ from rfl)).symm

/-- A compatible cocone respects every adjacent-stage identification. -/
theorem respects {Y : Family Index} (d : Cocone S Y)
    (i : Index) (a b : Tagged S i) (h : step S i a b) :
    d.leg a.1 i a.2 = d.leg b.1 i b.2 :=
  ((congrArg (fun z : Tagged S i => d.leg z.1 i z.2) h).trans
    (d.comm a.1 i a.2)).symm

def descend {Y : Family Index} (d : Cocone S Y) : Map (carrier S) Y :=
  fun i => Quot.lift (fun a => d.leg a.1 i a.2) (respects S d i)

/-- Quotient descent computes directly on a representative. -/
theorem descend_on_leg {Y : Family Index} (d : Cocone S Y) n i x :
    descend S d i ((cocone S).leg n i x) = d.leg n i x := rfl

/-- Every sequence has this chosen colimit in the same universe. -/
def isColimit : Colimit (cocone S) where
  descend := descend S
  factor := descend_on_leg S
  unique := fun _f _g h i q => Quot.inductionOn q (fun a => h a.1 i a.2)

/-- The constructed colimit leaves preservation as the only hypothesis. -/
def initialOfPreserves (P : Initiality.Polynomial.{u, u, u} Index)
    (preserved : Colimit (mappedCocone P (cocone (initialSequence P)))) :
    Initiality.Initial (chainAlgebra (cocone (initialSequence P)) preserved) :=
  chainInitial (cocone (initialSequence P)) preserved (isColimit (initialSequence P))

end KanonMeta.ChainColimit
