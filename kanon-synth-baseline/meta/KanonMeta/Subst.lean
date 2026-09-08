/-
Copyright (c) 2026 Onyeka Obi.  All rights reserved.
Released under MIT OR Apache 2.0 license.

Renaming and substitution for the object language of Syntax.lean.

Two layers, in the usual order.  `ren` renames with a map on indices and
`upRen` lifts that map under one binder.  `up` then lifts a substitution
under one binder, and it needs `ren` to weaken the terms it carries, so
renaming comes first.  `subst` is the total substitution and
`substShape` is the shape action, which rewrites the point domain and
leaves the collection shape alone, because lib/shape.ml:12 gives `SColl`
an `int` and no term.

Every function is total and structurally recursive through the equation
compiler.  Each definition is total, with no escape hatch and no tactic.

The binder count of a diagram is the kernel's: the point diagram opens
one binder and the collection diagram opens none, which lib/rules.ml:635
and lib/rules.ml:637 state as `spi_diagram_arity` and
`coll_diagram_arity`.  The two former arms therefore split on the shape
and lift the substitution only under `SPi` (SF-D15).  Each section leg
and elimination branch lifts under its explicit binders.  A motive
lifts under its indices and its self variable.  Point addresses carry
their own term, which is renamed and substituted in the outer context.
-/

import KanonMeta.Syntax

namespace KanonMeta

/-- A renaming of de Bruijn indices. -/
abbrev Ren : Type := Nat -> Nat

/-- Lift a renaming under one binder. -/
def upRen (rho : Ren) : Ren :=
  fun i =>
    match i with
    | 0 => 0
    | Nat.succ m => Nat.succ (rho m)

/-- Lift a renaming under an explicit number of binders. -/
def upRenN (n : Nat) (rho : Ren) : Ren :=
  match n with
  | 0 => rho
  | Nat.succ m => upRen (upRenN m rho)

mutual

/-- Rename every free index of a term. -/
def ren (rho : Ren) (tm : Term) : Term :=
  match tm with
  | Term.var i => Term.var (rho i)
  | Term.univ l => Term.univ l
  | Term.lan (Shape.SPi q name dom) body =>
      Term.lan (renShape rho (Shape.SPi q name dom)) (ren (upRen rho) body)
  | Term.lan (Shape.SColl n) body =>
      Term.lan (renShape rho (Shape.SColl n)) (ren rho body)
  | Term.ran (Shape.SPi q name dom) body =>
      Term.ran (renShape rho (Shape.SPi q name dom)) (ren (upRen rho) body)
  | Term.ran (Shape.SColl n) body =>
      Term.ran (renShape rho (Shape.SColl n)) (ren rho body)
  | Term.intro s a args =>
      Term.intro (renShape rho s) (renAddr rho a) (renArgs rho args)
  | Term.elim s scrut q motive branches =>
      Term.elim (renShape rho s) (ren rho scrut) q
        (renOptionalMotive rho motive)
        (renBranches rho branches)
  | Term.sec s legs => Term.sec (renShape rho s) (renLegs rho legs)
  | Term.out s a body => Term.out (renShape rho s) (renAddr rho a) (ren rho body)
  | Term.letIn name ty val body =>
      Term.letIn name (ren rho ty) (ren rho val) (ren (upRen rho) body)
  | Term.ann body ty => Term.ann (ren rho body) (ren rho ty)
  | Term.global name => Term.global name
  | Term.lit n => Term.lit n

/-- Traverse fibre arguments by structural recursion. -/
def renArgs (rho : Ren) (args : List Term) : List Term :=
  match args with
  | [] => []
  | tm :: rest => ren rho tm :: renArgs rho rest

/-- Traverse the section legs without changing their order. -/
def renLegs (rho : Ren) (legs : List Leg) : List Leg :=
  match legs with
  | [] => []
  | leg :: rest => renLeg rho leg :: renLegs rho rest

/-- Traverse an optional motive. -/
def renOptionalMotive (rho : Ren) (motive : Option Motive) : Option Motive :=
  match motive with
  | none => none
  | some m => some (renMotive rho m)

/-- Traverse a branch key and its scoped leg separately. -/
def renBranch (rho : Ren) (branch : Addr × Leg) : Addr × Leg :=
  match branch with
  | (a, leg) => (renAddr rho a, renLeg rho leg)

/-- Traverse the branches without changing their order. -/
def renBranches (rho : Ren) (branches : List (Addr × Leg)) : List (Addr × Leg) :=
  match branches with
  | [] => []
  | branch :: rest => renBranch rho branch :: renBranches rho rest

/-- Rename every free index of a shape. -/
def renShape (rho : Ren) (s : Shape) : Shape :=
  match s with
  | Shape.SPi q name dom => Shape.SPi q name (ren rho dom)
  | Shape.SColl n => Shape.SColl n

/-- Rename point arguments in the outer context. -/
def renAddr (rho : Ren) (a : Addr) : Addr :=
  match a with
  | Addr.apt q arg => Addr.apt q (ren rho arg)
  | Addr.aleg k => Addr.aleg k

/-- Rename a leg under all its binders. -/
def renLeg (rho : Ren) (leg : Leg) : Leg :=
  match leg with
  | Leg.mk binders body => Leg.mk binders (ren (upRenN binders.length rho) body)

/-- Rename a motive under its indices and self variable. -/
def renMotive (rho : Ren) (motive : Motive) : Motive :=
  match motive with
  | Motive.mk ind idx self body =>
      Motive.mk ind idx self (ren (upRenN (idx.length + 1) rho) body)

end

/-- A substitution sends each free index to a term. -/
abbrev Subst : Type := Nat -> Term

/-- Lift a substitution under one binder.  This is the `sigma` with a
plus of the Beck-Chevalley statements. -/
def up (sigma : Subst) : Subst :=
  fun i =>
    match i with
    | 0 => Term.var 0
    | Nat.succ m => ren Nat.succ (sigma m)

/-- Lift a substitution under an explicit number of binders. -/
def upN (n : Nat) (sigma : Subst) : Subst :=
  match n with
  | 0 => sigma
  | Nat.succ m => up (upN m sigma)

mutual

/-- Apply a substitution to a term. -/
def subst (sigma : Subst) (tm : Term) : Term :=
  match tm with
  | Term.var i => sigma i
  | Term.univ l => Term.univ l
  | Term.lan (Shape.SPi q name dom) body =>
      Term.lan (substShape sigma (Shape.SPi q name dom)) (subst (up sigma) body)
  | Term.lan (Shape.SColl n) body =>
      Term.lan (substShape sigma (Shape.SColl n)) (subst sigma body)
  | Term.ran (Shape.SPi q name dom) body =>
      Term.ran (substShape sigma (Shape.SPi q name dom)) (subst (up sigma) body)
  | Term.ran (Shape.SColl n) body =>
      Term.ran (substShape sigma (Shape.SColl n)) (subst sigma body)
  | Term.intro s a args =>
      Term.intro (substShape sigma s) (substAddr sigma a)
        (substArgs sigma args)
  | Term.elim s scrut q motive branches =>
      Term.elim (substShape sigma s) (subst sigma scrut) q
        (substOptionalMotive sigma motive)
        (substBranches sigma branches)
  | Term.sec s legs =>
      Term.sec (substShape sigma s) (substLegs sigma legs)
  | Term.out s a body =>
      Term.out (substShape sigma s) (substAddr sigma a) (subst sigma body)
  | Term.letIn name ty val body =>
      Term.letIn name (subst sigma ty) (subst sigma val) (subst (up sigma) body)
  | Term.ann body ty => Term.ann (subst sigma body) (subst sigma ty)
  | Term.global name => Term.global name
  | Term.lit n => Term.lit n

/-- Traverse fibre arguments by structural recursion. -/
def substArgs (sigma : Subst) (args : List Term) : List Term :=
  match args with
  | [] => []
  | tm :: rest => subst sigma tm :: substArgs sigma rest

/-- Traverse the section legs without changing their order. -/
def substLegs (sigma : Subst) (legs : List Leg) : List Leg :=
  match legs with
  | [] => []
  | leg :: rest => substLeg sigma leg :: substLegs sigma rest

/-- Traverse an optional motive. -/
def substOptionalMotive (sigma : Subst) (motive : Option Motive) : Option Motive :=
  match motive with
  | none => none
  | some m => some (substMotive sigma m)

/-- Traverse a branch key and its scoped leg separately. -/
def substBranch (sigma : Subst) (branch : Addr × Leg) : Addr × Leg :=
  match branch with
  | (a, leg) => (substAddr sigma a, substLeg sigma leg)

/-- Traverse the branches without changing their order. -/
def substBranches (sigma : Subst) (branches : List (Addr × Leg)) : List (Addr × Leg) :=
  match branches with
  | [] => []
  | branch :: rest => substBranch sigma branch :: substBranches sigma rest

/-- Apply a substitution to a shape.  The point shape carries its domain
through, and the collection shape holds no term and stays as it is. -/
def substShape (sigma : Subst) (s : Shape) : Shape :=
  match s with
  | Shape.SPi q name dom => Shape.SPi q name (subst sigma dom)
  | Shape.SColl n => Shape.SColl n

/-- Substitute point arguments in the outer context. -/
def substAddr (sigma : Subst) (a : Addr) : Addr :=
  match a with
  | Addr.apt q arg => Addr.apt q (subst sigma arg)
  | Addr.aleg k => Addr.aleg k

/-- Substitute a leg under all its binders. -/
def substLeg (sigma : Subst) (leg : Leg) : Leg :=
  match leg with
  | Leg.mk binders body => Leg.mk binders (subst (upN binders.length sigma) body)

/-- Substitute a motive under its indices and self variable. -/
def substMotive (sigma : Subst) (motive : Motive) : Motive :=
  match motive with
  | Motive.mk ind idx self body =>
      Motive.mk ind idx self (subst (upN (idx.length + 1) sigma) body)

end

end KanonMeta
