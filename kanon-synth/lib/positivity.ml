(** Strict positivity and the family record, brief 3.2 and 3.3, new at
    M1 Stage G (M1-PLAN.md:49).  The record carries the pin's fields
    field for field, kan-lang-tot-pin/lib/global.ml:45-70.  SG-D14:  the
    record type lives here, not in global.ml, because global.ml:132
    reads [Prim.catalog] and prim.ml:61 reads [Rules.arrow], so rules.ml
    can never name a type global.ml declares;  the table and its one
    accessor stay beside the Global table (global.ml:56-79) and
    [Global.entry] gains no constructor (SG-D1, R-Q3).  No shape name
    appears here, so R0-AUDIT stays green (dev/r0-audit.sh:6-11):  a
    former is read through [Shape.family], [Shape.point_dom] and
    [Shape.payload].  The walk is total, runs once when the constructors
    are installed (Check.define_ctors) and stores its verdict on the
    record (A4, M1-PLAN.md:95, pin check.ml:2059);  formation reads that
    verdict (rules.ml [mu_family]). *)

let ( let* ) = Result.bind

(** The M2 word of D-M1-2 (RATIFICATIONS.md:60), which every refusal of
    this file carries;  a nested inductive is refused with it (R-Q5). *)
let nonpositive_word : string = "a family that is not strictly positive arrives at M2"

(** Binder telescope, outermost first, each type scoped under the
    binders before it (pin lib/global.ml:36-38). *)
type telescope = (Quantity.t * string * Term.t) list

(** The three state constructor status, pin lib/global.ml:39-42:  no
    constructor yet, a family the kernel owns, and the constructor names
    in declaration order. *)
type ctor_status = Provisional | Builtin | Complete of string list

(** A data constructor, pin lib/global.ml:54-70:  the argument telescope
    (:58), the result index expressions under the parameters and the
    arguments (:59-61), the full arity (:63) and [self_rec] (:67,
    computed at pin check.ml:2059). *)
type ctor = {
  c_name : string;
  c_args : telescope;
  c_res_idx : Term.t list;
  c_full_arity : int;
  c_self_rec : bool;
}

(** A family, pin lib/global.ml:45-52, with the stored verdict of A4
    beside its fields.  An index binder is under the parameters and at
    [Quantity.Zero], refused otherwise as [Index_not_zero] (pin
    global.ml:49 and pin check.ml:1819). *)
type family = {
  f_name : string;
  f_params : telescope;
  f_indices : telescope;
  f_level : Level.t;
  f_status : ctor_status;
  f_ctors : ctor list;
  f_positive : bool;
}

(** The constructor of a family by name, read off the record the one
    accessor of brief 3.3 answers with. *)
let ctor_of (name : string) (f : family) : ctor option =
  List.find_opt (fun (c : ctor) -> String.equal c.c_name name) f.f_ctors

(** Does one of the mutual group occur in a term?  The walk is exhaustive
    over term.ml:21-59, so a new constructor is a compile error in
    [Term.exists_name]. *)
let occurs (names : string list) (t : Term.t) : bool =
  Term.exists_name ~include_families:true names t

let is_member (names : string list) (n : string option) : bool =
  n |> Option.fold ~none:false ~some:(fun (m : string) -> List.exists (String.equal m) names)

(** No occurrence at all.  Every position that is not the right of an
    arrow asks one of these two (D-M1-2). *)
let absent (names : string list) (t : Term.t) : (unit, Error.t) result =
  if occurs names t then Error (Error.Not_yet nonpositive_word) else Ok ()

let absent_list (names : string list) (ts : Term.t list) : (unit, Error.t) result =
  if List.exists (occurs names) ts then Error (Error.Not_yet nonpositive_word) else Ok ()

(** A strictly positive position.  A left former at a member of the
    group is the self reference and is admitted when its index payload
    and its diagram hold no occurrence.  An occurrence right of an arrow
    is admitted and the arrow domain (rules.ml:220) holds none.  Every
    other former refuses one inside it, so a nested inductive is M2
    (R-Q5). *)
let rec positive (names : string list) (t : Term.t) : (unit, Error.t) result =
  match t with
  | Term.Lan (s, d) ->
      if is_member names (Shape.family s) then
        Result.bind (absent_list names (Shape.payload s)) (fun () -> absent names d)
      else absent names t
  | Term.Ran (s, cod) ->
      Shape.point_dom s
      |> Option.fold ~none:(absent names t) ~some:(fun (dom : Term.t) ->
             let* () = absent names dom in
             positive names cod)
  | Term.Out (s, a, head) ->
      Option.bind (Shape.point_dom s) (fun (_dom : Term.t) -> Term.as_apt a)
      |> Option.fold ~none:(absent names t)
           ~some:(fun ((_q : Quantity.t), (arg : Term.t)) ->
             let* () = absent names arg in
             positive names head)
  | Term.Global _ -> Ok ()
  | Term.Var _ | Term.Univ _ | Term.In (_, _, _) | Term.Elim _ | Term.Sec (_, _)
  | Term.Let (_, _, _, _) | Term.Ann (_, _) | Term.Lit _ | Term.Auto ->
      absent names t

(** Brief 3.2:  every field of one constructor admits the family only
    strictly positively, in declaration order. *)
let ctor_fields (names : string list) (args : telescope) : (unit, Error.t) result =
  List.fold_left
    (fun (acc : (unit, Error.t) result) ((_q : Quantity.t), (_x : string), (ty : Term.t)) ->
      let* () = acc in
      positive names ty)
    (Ok ()) args

(** [self_rec] of the pin, computed as pin check.ml:2059 does. *)
let self_rec (names : string list) (args : telescope) : bool =
  List.exists (fun ((_q : Quantity.t), (_x : string), (ty : Term.t)) -> occurs names ty) args
