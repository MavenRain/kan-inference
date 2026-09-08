(* carried from tot 8cf0b8b lib/global.ml, delta: header line; the Ind and Ctor entries with their views are dropped because the recursive shapes arrive at M1; the Prim entry is re-adapted at Stage B with prim_of, find_prim and initial *)
(** Global environment. [add] is kernel-internal: the only sound ways to
    extend the environment are [Check.define], [Check.declare_ind] and
    [Check.define_ind], which typecheck first. The namespace is flat: an
    inductive's name and its constructor names live in the same map. *)

module StringMap = Map.Make (String)

(** Binder telescope, outermost first; each type is scoped under the
    binders before it. *)
type telescope = (Quantity.t * string * Term.t) list

(** An ordinary (possibly recursive) definition. *)
type def_entry = {
  ty : Term.t;  (** closed *)
  def : Term.t;  (** closed *)
  reducible : bool;
      (** opaque by default: evaluation unfolds only when this is set,
          and conversion never unfolds on its own *)
  rec_arg : int option;
      (** [Some k]: a rec def; evaluation unfolds it only when argument
          [k] is a canonical constructor value (guarded unfolding) *)
  partial : bool;
      (** M3 Stage C: [true] for a [def rec partial] that skipped
          [Totality.guard] (decision 10 of the M3 design verdict): its
          codomain is Div-headed and it is forced [reducible = false],
          [rec_arg = None]. Consulted only for record-keeping /
          tooling; runtime and conversion behavior are fully
          determined by [reducible] and [rec_arg] alone, exactly as
          for any other opaque non-rec-guarded def. *)
}

(** M4 Stage B: a postulated statement. An [Axiom] has no [def] and no
    [reducible], so conversion can never step into it, by the same
    argument SPEC section 3 makes for prims. [Check] additionally refuses
    it at quantity mode w, so an axiom can never reach erased output and
    [tot run] never meets one. *)
type axiom_entry = { ax_ty : Term.t }  (** closed *)

(** R-Q3: [Axiom] exists from Stage A, so the [kanon axioms] disclosure
    path has a target from the first commit. *)
(** M0 Stage B: a native primitive holds the closed type it is declared
    at and the primitive itself, so evaluation reaches the literal fast
    path without a second lookup.  A [Prim] has no [def], so conversion
    can never step into it, exactly as for an [Axiom]. *)
type prim_entry = {
  p_ty : Term.t;  (** closed *)
  prim : Prim.t;
}

type entry =
  | Def of def_entry
  | Axiom of axiom_entry  (** M4 Stage B *)
  | Prim of prim_entry  (** M0 Stage B *)

(** M1 Stage G, brief 3.3 and SG-D1:  the family table lives beside the
    Global table, in the same record, and [entry] above gains no
    constructor, which keeps R-Q3 as ruled (M1-PLAN.md:9).  The record is
    [Positivity.family] (SG-D14):  this file reads Prim.catalog below and
    prim.ml:61 reads [Rules.arrow]. *)
type t = {
  entries : entry StringMap.t;
  families : Positivity.family StringMap.t;
}

let empty : t = { entries = StringMap.empty; families = StringMap.empty }
let find (name : string) (globals : t) : entry option = StringMap.find_opt name globals.entries

let add (name : string) (entry : entry) (globals : t) : t =
  { globals with entries = StringMap.add name entry globals.entries }

(** The one accessor of brief 3.3:  rules.ml reads a family through this
    and nothing else (SG-D2, dev/r0-audit.sh:6-11). *)
let find_family (name : string) (globals : t) : Positivity.family option =
  StringMap.find_opt name globals.families

(** The writer of check.ml [declare_family] and [define_ctors]. *)
let add_family (name : string) (fam : Positivity.family) (globals : t) : t =
  { globals with families = StringMap.add name fam globals.families }

(** The closed type every entry kind stores. *)
let entry_ty (e : entry) : Term.t =
  match e with
  | Def d -> d.ty
  | Axiom a -> a.ax_ty
  | Prim p -> p.p_ty

(** Payload views; Option-returning so callers stay total. *)
let def_of (e : entry) : def_entry option =
  match e with
  | Def d -> Some d
  | Axiom _ -> None
  | Prim _ -> None

(** M4 Stage B: view onto the [Axiom] payload, beside the other one. *)
let axiom_of (e : entry) : axiom_entry option =
  match e with
  | Axiom a -> Some a
  | Def _ -> None
  | Prim _ -> None

(** M0 Stage B: view onto the [Prim] payload, beside the other two. *)
let prim_of (e : entry) : prim_entry option =
  match e with
  | Prim p -> Some p
  | Def _ -> None
  | Axiom _ -> None

let find_def (name : string) (globals : t) : def_entry option =
  Option.bind (find name globals) def_of

let find_axiom (name : string) (globals : t) : axiom_entry option =
  Option.bind (find name globals) axiom_of

let find_prim (name : string) (globals : t) : prim_entry option =
  Option.bind (find name globals) prim_of

(** The environment every file is checked against (M0 Stage B).  [Nat] is
    postulated at [Type 0] and the five primitives of prim.ml are
    declared at the types of SB-D8.  [Nat] is an [Axiom] entry because a
    postulated type constant is what it is at M0;  the [kanon axioms]
    disclosure reads the declarations of the FILE, not this environment,
    so [Nat] never appears in that report. *)
let initial : t =
  let nat : entry = Axiom { ax_ty = Term.Univ Level.one } in
  List.fold_left
    (fun (g : t) (p : Prim.t) ->
      add (Prim.name p) (Prim { p_ty = Prim.ty p; prim = p }) g)
    (add Prim.nat_name nat empty)
    Prim.catalog
