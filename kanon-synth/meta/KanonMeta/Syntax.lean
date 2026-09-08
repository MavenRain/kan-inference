/-
Copyright (c) 2026 Onyeka Obi.  All rights reserved.
Released under MIT OR Apache 2.0 license.

The object language of the kanon kernel, mirrored in Lean 4.

`Shape` carries the two shapes that SPEC.md:143 admits at M0, `SPi` and
`SColl`, in the order of lib/shape.ml:11-12.  `SPar`, `SMu` and `SNu`
stay out (SF-D4): Lean carries no milestone refusal, so a shape that the
kernel refuses has no Lean mirror.

`Term` carries the twelve M0 constructors of lib/term.ml, in the order of
SPEC.md:26-42.  `Auto` stays out because check.ml refuses it until M2.
Variables are de Bruijn indices, as lib/term.ml holds `Var of int`
(SF-D5).  `Level.t` is an OCaml `int` at lib/level.ml:2, so `univ` holds
a `Nat`.

Shapes, addresses, legs and motives carry terms in one mutual family.
Legs retain their binder lists, and motives bind their indices followed
by their self variable, as in lib/term.ml.
-/

namespace KanonMeta

/-- The usage marks of the 0/1/omega fragment, from lib/quantity.ml:10-13. -/
inductive Quantity where
  | zero
  | one
  | many

mutual

/-- A point address retains its argument separately from the fibre or
function head.  Recursive constructor addresses stay out at M0. -/
inductive Addr where
  | apt (q : Quantity) (arg : Term)
  | aleg (k : Nat)

/-- A section leg or elimination branch with its explicit binders. -/
inductive Leg where
  | mk (binders : List (Quantity × String)) (body : Term)

/-- The motive body binds the indices and then the self variable. -/
inductive Motive where
  | mk (ind : Option String) (idx : List String) (self : String) (body : Term)

/-- The two admitted shapes (SPEC.md:143). -/
inductive Shape where
  | SPi (q : Quantity) (name : String) (dom : Term)
  | SColl (n : Nat)

/-- The kernel term at M0. -/
inductive Term where
  | var (i : Nat)
  | univ (l : Nat)
  | lan (s : Shape) (body : Term)
  | ran (s : Shape) (body : Term)
  | intro (s : Shape) (a : Addr) (args : List Term)
  | elim (s : Shape) (scrut : Term) (q : Quantity)
      (motive : Option Motive) (branches : List (Addr × Leg))
  | sec (s : Shape) (legs : List Leg)
  | out (s : Shape) (a : Addr) (tm : Term)
  | letIn (name : String) (ty : Term) (val : Term) (body : Term)
  | ann (tm : Term) (ty : Term)
  | global (name : String)
  | lit (n : Nat)

end

end KanonMeta
