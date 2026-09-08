(* carried from tot 8cf0b8b lib/literal.ml, delta: Stage K arbitrary precision integer payload and equality *)
(** String and integer literal values. Bignum owns the Stage K numeric
    representation; the literal constructors remain the closed M3 Stage A sum. *)

type t =
  | LString of string
  | LInt of Bignum.t

let equal (a : t) (b : t) : bool =
  match (a, b) with
  | LString s1, LString s2 -> String.equal s1 s2
  | LInt n1, LInt n2 -> Bignum.equal n1 n2
  | LString _, LInt _ -> false
  | LInt _, LString _ -> false
