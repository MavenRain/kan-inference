/-
Copyright (c) 2026 Onyeka Obi.  All rights reserved.
Released under MIT OR Apache 2.0 license.

Regression checks for the Stage F syntax and substitution review.
This target builds separately from the public library.
-/

import KanonMeta
import KanTactics

namespace KanonMeta.Tests

private def point : Shape := Shape.SPi .many "x" (.univ 0)
private def binders : List (Quantity × String) := [(.many, "x")]
private def pairBinders : List (Quantity × String) := [(.many, "x"), (.many, "y")]
private def replace : Subst := fun i => .lit (i + 7)

-- A closed identity section stays closed under both actions.
example : subst replace (.sec point [.mk binders (.var 0)])
    = .sec point [.mk binders (.var 0)] := by
  kan_rfl

example : ren Nat.succ (.sec point [.mk binders (.var 0)])
    = .sec point [.mk binders (.var 0)] := by
  kan_rfl

-- A free variable beneath the binder is still transformed.
example : subst replace (.sec point [.mk binders (.var 1)])
    = .sec point [.mk binders (.lit 7)] := by
  kan_rfl

example : ren Nat.succ (.sec point [.mk binders (.var 1)])
    = .sec point [.mk binders (.var 2)] := by
  kan_rfl

-- Both variables of a point elimination branch are bound.
example : subst replace
    (.elim point (.var 0) .many none
      [(.aleg 0, .mk pairBinders (.ann (.var 0) (.var 1)))])
    = .elim point (.lit 7) .many none
      [(.aleg 0, .mk pairBinders (.ann (.var 0) (.var 1)))] := by
  kan_rfl

example : ren Nat.succ
    (.elim point (.var 0) .many none
      [(.aleg 0, .mk pairBinders (.ann (.var 0) (.var 2)))])
    = .elim point (.var 1) .many none
      [(.aleg 0, .mk pairBinders (.ann (.var 0) (.var 3)))] := by
  kan_rfl

-- Substituted free terms must be weakened through every branch binder.
example : subst (fun i => .var (i + 1))
    (.elim point (.global "p") .many none
      [(.aleg 0, .mk pairBinders (.var 2))])
    = .elim point (.global "p") .many none
      [(.aleg 0, .mk pairBinders (.var 3))] := by
  kan_rfl

-- A substitution containing a closed section must not open its binder.
example : up (fun i => .sec point [.mk binders (.var i)]) 1
    = .sec point [.mk binders (.var 0)] := by
  kan_rfl

-- Collection legs bind nothing and preserve empty and multiple lists.
example : subst replace (.sec (.SColl 0) []) = .sec (.SColl 0) [] := by
  kan_rfl

example : subst replace (.sec (.SColl 2) [.mk [] (.var 0), .mk [] (.var 1)])
    = .sec (.SColl 2) [.mk [] (.lit 7), .mk [] (.lit 8)] := by
  kan_rfl

-- Application arguments and function heads remain independent.
example : subst replace (.out point (.apt .many (.var 0)) (.var 1))
    = .out point (.apt .many (.lit 7)) (.lit 8) := by
  kan_rfl

example : ren Nat.succ (.out point (.apt .many (.var 0)) (.var 1))
    = .out point (.apt .many (.var 1)) (.var 2) := by
  kan_rfl

-- Pair points and fibre elements remain independent too.
example : subst replace (.intro point (.apt .many (.var 0)) [.var 1])
    = .intro point (.apt .many (.lit 7)) [.lit 8] := by
  kan_rfl

example : ren Nat.succ (.intro point (.apt .many (.var 0)) [.var 1])
    = .intro point (.apt .many (.var 1)) [.var 2] := by
  kan_rfl

-- Motives bind indices followed by self; branch addresses are outside.
example : subst replace
    (.elim point (.var 0) .zero
      (some (.mk none ["i"] "self" (.ann (.var 0) (.var 2))))
      [(.apt .many (.var 1), .mk [] (.var 2))])
    = .elim point (.lit 7) .zero
      (some (.mk none ["i"] "self" (.ann (.var 0) (.lit 7))))
      [(.apt .many (.lit 8), .mk [] (.lit 9))] := by
  kan_rfl

example : ren Nat.succ
    (.elim point (.var 0) .zero
      (some (.mk none ["i"] "self" (.ann (.var 0) (.var 2)))) [])
    = .elim point (.var 1) .zero
      (some (.mk none ["i"] "self" (.ann (.var 0) (.var 3)))) [] := by
  kan_rfl

end KanonMeta.Tests
