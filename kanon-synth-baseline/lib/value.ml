(** The NbE semantic domain, plan section 5.  Syntax uses de Bruijn
    indices, values use de Bruijn levels, and every closure keeps the
    environment it was built under.

    No shape name appears here (SA-D5, gate leg R0-AUDIT):  a former
    carries its shape as a [t Shape.t], so this file names the sum and
    never a member of it.

    The diagram of a former is a CLOSURE, not a value (SB-D23).  The two
    admitted shapes open a diagram in two different ways:  one binds a
    point, so its diagram opens by application, and the other is binder
    free, so its diagram opens by forcing.  One carrier serves both, and
    rules.ml decides which opening a shape takes, so no reader outside
    the pack has to know.

    The [Level.t option] slot of [VLan] and [VRan] is the SB-D7 carrier.
    [Eval] fills it from an [Ann] whose annotation is a universe, and
    conversion compares it through the pack, so the empty collection at
    [Univ zero] and the empty collection at [Univ one] are two values
    that never convert.  Every other shape reads its universe from the
    diagram, so the pack ignores the slot there. *)

type t =
  | VUniv of Level.t
  | VLan of t Shape.t * closure * Level.t option
  | VRan of t Shape.t * closure * Level.t option
  | VIn of t Shape.t * vaddr * t list
  | VSec of t Shape.t * vleg list
  | VLit of Literal.t
  | VNeutral of head * spine list  (** spine newest first *)

and vaddr =
  | VAPt of Quantity.t * t
  | VALeg of int
  | VACtor of string

and vleg = {
  vl_binders : (Quantity.t * string) list;
  vl_clo : closure;
}

and head =
  | HLocal of int  (** de Bruijn level *)
  | HGlobal of string

and spine =
  | SOut of t Shape.t * vaddr
  | SElim of stuck_elim

(** A stuck elimination freezes its motive and its branch bodies as terms
    beside the environment they close over, as tot's [stuck_match] does
    (kan-lang-tot-pin/lib/value.ml). *)
and stuck_elim = {
  s_shape : t Shape.t;
  s_scrut_q : Quantity.t;
  s_motive : Term.motive option;
  s_branches : (Term.addr * Term.leg) list;
  s_env : t list;
}

and closure = {
  env : t list;
  body : Term.t;
}

let var (lvl : int) : t = VNeutral (HLocal lvl, [])

(** A closure over an environment and a body.  Callers that hold a term
    and an environment build a diagram or a leg with it, so no other
    module writes the record fields. *)
let close (env : t list) (body : Term.t) : closure = { env; body }

(** Total views.  Plan section 11 bans a partial projection, so every
    reader of a value asks one of these and folds the [option]. *)

let as_univ (v : t) : Level.t option =
  match v with
  | VUniv l -> Some l
  | VLan (_, _, _) | VRan (_, _, _) | VIn (_, _, _) | VSec (_, _) | VLit _ | VNeutral (_, _)
    ->
      None

let as_lan (v : t) : (t Shape.t * closure * Level.t option) option =
  match v with
  | VLan (s, d, u) -> Some (s, d, u)
  | VUniv _ | VRan (_, _, _) | VIn (_, _, _) | VSec (_, _) | VLit _ | VNeutral (_, _) -> None

let as_ran (v : t) : (t Shape.t * closure * Level.t option) option =
  match v with
  | VRan (s, d, u) -> Some (s, d, u)
  | VUniv _ | VLan (_, _, _) | VIn (_, _, _) | VSec (_, _) | VLit _ | VNeutral (_, _) -> None

let as_in (v : t) : (t Shape.t * vaddr * t list) option =
  match v with
  | VIn (s, a, args) -> Some (s, a, args)
  | VUniv _ | VLan (_, _, _) | VRan (_, _, _) | VSec (_, _) | VLit _ | VNeutral (_, _) ->
      None

let as_sec (v : t) : (t Shape.t * vleg list) option =
  match v with
  | VSec (s, legs) -> Some (s, legs)
  | VUniv _ | VLan (_, _, _) | VRan (_, _, _) | VIn (_, _, _) | VLit _ | VNeutral (_, _) ->
      None

let as_lit (v : t) : Literal.t option =
  match v with
  | VLit l -> Some l
  | VUniv _ | VLan (_, _, _) | VRan (_, _, _) | VIn (_, _, _) | VSec (_, _) | VNeutral (_, _)
    ->
      None

let as_neutral (v : t) : (head * spine list) option =
  match v with
  | VNeutral (h, sp) -> Some (h, sp)
  | VUniv _ | VLan (_, _, _) | VRan (_, _, _) | VIn (_, _, _) | VSec (_, _) | VLit _ -> None

let as_pt (a : vaddr) : (Quantity.t * t) option =
  match a with
  | VAPt (q, v) -> Some (q, v)
  | VALeg _ | VACtor _ -> None

let as_leg (a : vaddr) : int option =
  match a with
  | VALeg k -> Some k
  | VAPt (_, _) | VACtor _ -> None

let as_ctor (a : vaddr) : string option =
  match a with
  | VACtor c -> Some c
  | VAPt (_, _) | VALeg _ -> None

let head_equal (a : head) (b : head) : bool =
  match (a, b) with
  | HLocal i, HLocal j -> Int.equal i j
  | HGlobal m, HGlobal n -> String.equal m n
  | HLocal _, HGlobal _ -> false
  | HGlobal _, HLocal _ -> false
