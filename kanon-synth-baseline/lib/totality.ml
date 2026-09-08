(** Totality, plan section 6 "Totality".  M1 Stage I fills the body:
    structural recursion is an elaborator translation into an
    elimination with a certificate that is checked before the
    translation, and not a driver flag.

    The certificate lives in lib/order.ml, which mirrors tot's guard
    (kan-lang-tot-pin/lib/totality.ml:188) part for part.  This file
    keeps the entry point at the signature M0 published (I-F7,
    SC-D15), so no call site changes shape:  [guard ?budget globals
    name ty body] answers [Ok (Some k)] for a body whose every
    recursive call decreases at formal position [k], [Ok None] for a
    body with no self call, and the termination error of SI-D6
    otherwise (lib/error.ml:36 and lib/error.ml:45).

    [guard_group] is the same rule over a mutual group and it answers
    the certificate itself, so the caller that translates a group hands
    that value to [Order.translate] (lib/order.ml:537) and the order is
    computed once.  [guard] is the group of one (brief 3.2, SI-D7), so
    the kernel holds one order and not two.

    The budget stays the backstop it was at M0 and its text does not
    move:  one poll per node of each body, before the certificate runs,
    so a driver cutoff fires at the same arm with the same message
    (SB-D19).

    No shape name appears in this file (SA-D5, gate leg R0-AUDIT):  the
    subterms of a former are read through [Rules.map_shape], the one
    total walk over a shape that rules.ml exports.  This file counts
    toward the TRUSTED-LINES budget. *)

let ( let* ) = Result.bind
let budget_msg : string = "the totality budget is exhausted"

(** One exhaustive traversal over the thirteen constructors of
    [Term.t], the shape of tot's [peel] and [spine] walks
    (kan-lang-tot-pin/lib/totality.ml:29 and :41) with the two of them
    fused.  It reads nothing:  it polls the budget at every node.  The
    certificate walk of lib/order.ml carries no budget of its own, so
    the cutoff of a driver is paid here, once, over the same term. *)
let rec spend (budget : Budget.t) (t : Term.t) : (unit, Error.t) result =
  if Budget.exhausted budget then Error (Error.Budget_exhausted budget_msg)
  else spend_node budget t

and spend_node (budget : Budget.t) (t : Term.t) : (unit, Error.t) result =
  match t with
  | Term.Var _ -> Ok ()
  | Term.Univ _ -> Ok ()
  | Term.Global _ -> Ok ()
  | Term.Lit _ -> Ok ()
  | Term.Auto -> Ok ()
  | Term.Lan (s, d) | Term.Ran (s, d) ->
      let* () = spend_shape budget s in
      spend budget d
  | Term.In (s, a, args) ->
      let* () = spend_shape budget s in
      let* () = spend_addr budget a in
      spend_all budget args
  | Term.Out (s, a, head) ->
      let* () = spend_shape budget s in
      let* () = spend_addr budget a in
      spend budget head
  | Term.Sec (s, legs) ->
      let* () = spend_shape budget s in
      spend_all budget (List.map (fun (lg : Term.leg) -> lg.Term.l_body) legs)
  | Term.Elim e ->
      let* () = spend_shape budget e.Term.e_shape in
      let* () = spend budget e.Term.e_scrut in
      let* () = spend_motive budget e.Term.e_motive in
      spend_branches budget e.Term.e_branches
  | Term.Let (_x, ty, def, body) ->
      let* () = spend budget ty in
      let* () = spend budget def in
      spend budget body
  | Term.Ann (tm, ty) ->
      let* () = spend budget tm in
      spend budget ty

(** The subterms of a shape, read through the total walk of rules.ml so
    that no shape name appears here.  The walk answers a shape, which
    this file drops. *)
and spend_shape (budget : Budget.t) (s : Term.t Shape.t) : (unit, Error.t) result =
  Rules.map_shape
    (fun (x : Term.t) -> Result.map (fun (() : unit) -> x) (spend budget x))
    s
  |> Result.map (fun (_s : Term.t Shape.t) -> ())

and spend_addr (budget : Budget.t) (a : Term.addr) : (unit, Error.t) result =
  Term.as_apt a
  |> Option.fold ~none:(Ok ())
       ~some:(fun ((_q : Quantity.t), (arg : Term.t)) -> spend budget arg)

and spend_motive (budget : Budget.t) (mo : Term.motive option) : (unit, Error.t) result =
  mo
  |> Option.fold ~none:(Ok ()) ~some:(fun (m : Term.motive) -> spend budget m.Term.m_body)

and spend_branches (budget : Budget.t) (brs : (Term.addr * Term.leg) list) :
    (unit, Error.t) result =
  List.fold_left
    (fun (acc : (unit, Error.t) result) ((a : Term.addr), (lg : Term.leg)) ->
      let* () = acc in
      let* () = spend_addr budget a in
      spend budget lg.Term.l_body)
    (Ok ()) brs

and spend_all (budget : Budget.t) (ts : Term.t list) : (unit, Error.t) result =
  List.fold_left
    (fun (acc : (unit, Error.t) result) (t : Term.t) ->
      let* () = acc in
      spend budget t)
    (Ok ()) ts

(** M1 Stage I, brief 3.2 and SI-D7:  the guard of a whole definition
    group.  [members] pairs each name of the group with its stamped
    body, in declaration order, and the answer is the certificate of
    lib/order.ml:459, so one caller reads the guarded position, the
    calls of every member and the constructor chain of every call from
    one value, and [Order.translate] needs no second search.

    [globals] stands in this signature for the reason it stands in
    [guard] below:  the environment tells the shape of a constructor.
    The structural rule reads the term alone
    (kan-lang-tot-pin/lib/totality.ml:97-109), so the table is not read
    here and the argument keeps every call site of M1 at one shape. *)
let guard_group ?(budget : Budget.t = Budget.unlimited) (globals : Global.t)
    (members : (string * Term.t) list) : (Order.t option, Error.t) result =
  let _ = globals in
  let* () = spend_all budget (List.map snd members) in
  Order.certify members

(** The M1 entry point (kan-lang-tot-pin/lib/totality.ml:188).  [guard
    globals name ty body] answers the guarded argument index of a
    structurally recursive definition:  [Ok (Some k)] when every call
    of [name] in [body] stands at a strictly smaller argument at the
    formal position [k], [Ok None] when [body] holds no call of [name]
    at all, and [Error (Error.Termination name)] otherwise (SI-D6).

    The direct case is the group of one, so this is [guard_group] at a
    single member and the two answers cannot drift apart.  [ty] stands
    in the signature because the declared type gives the formals that
    tot's [peel] counts;  lib/order.ml:151 peels the body instead, so
    the type is not read. *)
let guard ?(budget : Budget.t = Budget.unlimited) (globals : Global.t) (name : string)
    (ty : Term.t) (body : Term.t) : (int option, Error.t) result =
  let _ = ty in
  guard_group ~budget globals [ (name, body) ]
  |> Result.map (Option.map (fun (c : Order.t) -> c.Order.o_arg))
