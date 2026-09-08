(** The bidirectional checker, plan section 6.  The context is tot's
    (kan-lang-tot-pin/lib/check.ml:14 and :27):  an evaluation
    environment, the locals with their name, quantity and type, the size
    that turns an index into a level, and the budget.

    [infer] reads a type out of a term and [check] pushes an expected
    type into one.  Four constructors are checked and never inferred:  a
    section and an injection need the former they live in, and an
    elimination without a motive needs the expected type as its constant
    cocone (kan-lang-tot-pin/lib/term.ml:38-40).  Everything else is
    inferred and then converted against the expectation.

    A binder at [Zero] exists at check time only. Stage K carries pure
    runtime usage alongside each checked type, then discharges [One]
    binders exactly once per reachable path at their scope boundary.
    Type inference and conversion at [Zero] contribute no usage.

    Every entry point takes an optional budget and every [infer] polls
    it, so a driver can stop a check that does not end.

    No shape name appears in this file.  Each former, injection, section,
    projection and elimination goes to the pack of its shape, and the
    pack is looked up in rules.ml. *)

let ( let* ) = Result.bind

type ctx = {
  globals : Global.t;
  env : Value.t list;  (** one value per local, innermost first *)
  locals : (string * Quantity.t * Value.t) list;  (** innermost first *)
  size : int;
  budget : Budget.t;
}

let make (globals : Global.t) (budget : Budget.t) : ctx =
  { globals; env = []; locals = []; size = 0; budget }

(** A bound local stands for itself, so its value is the variable at the
    level the context has grown to (kan-lang-tot-pin/lib/check.ml:27). *)
let bind (x : string) (q : Quantity.t) (ty : Value.t) (c : ctx) : ctx =
  {
    c with
    env = Value.var c.size :: c.env;
    locals = (x, q, ty) :: c.locals;
    size = c.size + 1;
  }

(** A let bound local stands for its definition. *)
let define (x : string) (q : Quantity.t) (ty : Value.t) (v : Value.t) (c : ctx) : ctx =
  { c with env = v :: c.env; locals = (x, q, ty) :: c.locals; size = c.size + 1 }

let budget_msg : string = "the check budget is exhausted"
let string_word : string = "string types arrive at M1"

let no_infer (what : string) : Error.t =
  Error.Cannot_infer (what ^ " has no type of its own;  it needs an expected type")

(** A local at [Zero] is check time only.  At mode [Zero] every local
    reads, at a runtime mode an erased one does not (SB-D3:  [One] is a
    runtime mode at M0). *)
let readable (mode : Quantity.t) (q : Quantity.t) : bool =
  Quantity.equal mode Quantity.Zero || not (Quantity.equal q Quantity.Zero)

let names_of (c : ctx) : string list =
  List.map
    (fun ((x : string), (_q : Quantity.t), (_ty : Value.t)) -> x)
    c.locals

(** Levels identify binders independently of spelling and shadowing.
    Unreachable eliminations have no returning runtime path to discharge. *)
let close ?(affine : bool = false) (c : ctx) (size : int) (mode : Quantity.t) (uses : Quantity.usage) :
    (Quantity.usage, Error.t) result =
  List.fold_left
    (fun acc (level, (name, q, _ty)) ->
      let* free = acc in
      if level < size then Ok free
      else if not (Quantity.equal mode Quantity.Zero) && Quantity.equal q Quantity.One
              && not ((if affine then Quantity.at_most_once else Quantity.exactly_once) level free) then
        let message = if affine then "the linear alias " ^ name ^ " may be used at most once"
          else "the linear binder " ^ name ^ " must be used exactly once on every runtime path" in
        Error (Error.Quantity message)
      else Ok (Quantity.remove level free))
    (Ok uses) (List.mapi (fun ix local -> c.size - ix - 1, local) c.locals)

let rec ops : ctx Rules.ops =
  {
    Rules.o_infer = (fun (c : ctx) (q : Quantity.t) (t : Term.t) -> infer_uses c q t);
    o_check = (fun (c : ctx) (q : Quantity.t) (t : Term.t) (ty : Value.t) -> check_uses c q t ty);
    o_close = (fun c size mode uses -> close c size mode uses);
    o_infer_univ = (fun (c : ctx) (t : Term.t) -> infer_univ c t);
    o_conv = (fun (c : ctx) ~(ty : Value.t) (a : Value.t) (b : Value.t) -> Conv.conv ops c ~ty a b);
    o_conv_type = (fun (c : ctx) (a : Value.t) (b : Value.t) -> Conv.conv_type ops c a b);
    o_eval = (fun (c : ctx) (t : Term.t) -> Eval.eval c.globals c.env t);
    o_whnf = (fun (c : ctx) (v : Value.t) -> Eval.whnf c.globals v);
    o_bind = (fun (x : string) (q : Quantity.t) (ty : Value.t) (c : ctx) -> bind x q ty c);
    o_size = (fun (c : ctx) -> c.size);
    o_env = (fun (c : ctx) -> c.env);
    o_ev = (fun (c : ctx) -> Eval.ev c.globals);
    o_pp = (fun (c : ctx) (v : Value.t) -> pp_value c v);
    o_quote = (fun (c : ctx) (v : Value.t) -> Eval.quote c.globals c.size v);
    o_head_ty = (fun (c : ctx) (h : Value.head) -> head_ty c h);
    (* M1 Stage G, brief 3.3:  the one accessor the mu pack reads a
       family record through (SG-D2).  This file holds no other family
       lookup on a checking path. *)
    o_family = (fun (c : ctx) (n : string) -> Global.find_family n c.globals);
  }

and pp_value (c : ctx) (v : Value.t) : string =
  Eval.quote c.globals c.size v
  |> Result.map (Pp.term (names_of c))
  |> Result.value ~default:"a value that does not read back"

(** The type a neutral head carries, which is what lets conversion walk a
    spine at a type. *)
and head_ty (c : ctx) (h : Value.head) : (Value.t, Error.t) result =
  match h with
  | Value.HLocal lvl ->
      Rules.at (c.size - lvl - 1) c.locals
      |> Option.to_result
           ~none:(Error.Unbound "a local level is outside the context")
      |> Result.map (fun ((_x : string), (_q : Quantity.t), (ty : Value.t)) -> ty)
  | Value.HGlobal n ->
      Global.find n c.globals
      |> Option.to_result ~none:(Error.Unbound n)
      |> Fun.flip Result.bind (fun (e : Global.entry) ->
             Eval.eval c.globals [] (Global.entry_ty e))

(** The universe a term lives at.  A type is read at mode [Zero], so an
    erased local may appear in it. *)
and infer_univ (c : ctx) (t : Term.t) : (Level.t, Error.t) result =
  let* v, _uses = infer_uses c Quantity.Zero t in
  let* w = Eval.whnf c.globals v in
  Value.as_univ w
  |> Option.to_result
       ~none:
         (Error.Universe
            ("a term used as a type is not a universe:  " ^ pp_value c w))

and infer_uses (c : ctx) (mode : Quantity.t) (t : Term.t) : (Value.t * Quantity.usage, Error.t) result =
  if Budget.exhausted c.budget then Error (Error.Budget_exhausted budget_msg)
  else infer_node c mode t

and infer_node (c : ctx) (mode : Quantity.t) (t : Term.t) : (Value.t * Quantity.usage, Error.t) result =
  match t with
  | Term.Var ix ->
      let* x, q, ty =
        Rules.at ix c.locals
        |> Option.to_result
             ~none:
               (Error.Unbound
                  (Printf.sprintf "de Bruijn index %d is outside the context" ix))
      in
      if readable mode q then Ok (ty, Quantity.occurrence (c.size - ix - 1) mode)
      else
        Error
          (Error.Quantity
             (Printf.sprintf "the erased binder %s is read in a runtime position" x))
  | Term.Univ l -> Ok (Value.VUniv (Level.succ l), Quantity.empty)
  | Term.Lan (s, diagram) ->
      let* (pack : ctx Rules.rule_pack) = Rules.rules s in
      let* l = pack.Rules.form_lan ops c s diagram ~expected:None in
      Ok (Value.VUniv l, Quantity.empty)
  | Term.Ran (s, diagram) ->
      let* (pack : ctx Rules.rule_pack) = Rules.rules s in
      let* l = pack.Rules.form_ran ops c s diagram ~expected:None in
      Ok (Value.VUniv l, Quantity.empty)
  | Term.Out (s, addr, scrut) ->
      let* (pack : ctx Rules.rule_pack) = Rules.rules s in
      pack.Rules.elim_out ops c mode s addr scrut
  | Term.Elim e ->
      let* (pack : ctx Rules.rule_pack) = Rules.rules e.Term.e_shape in
      pack.Rules.elim_elim ops c mode e ~expected:None
  | Term.Let (x, ty, def, body) ->
      let_body c mode x ty def (fun c' -> infer_uses c' mode body)
  | Term.Ann (tm, ty) ->
      let* _l = infer_univ c ty in
      let* tyv = Eval.eval c.globals c.env ty in
      let* uses = check_uses c mode tm tyv in
      Ok (tyv, uses)
  | Term.Global n ->
      let* ty = head_ty c (Value.HGlobal n) in
      Ok (ty, Quantity.empty)
  | Term.Lit (Literal.LInt value) ->
      if Bignum.sign value < 0 then Error (Error.Mismatch "a Nat literal must be nonnegative")
      else
        let* ty = Eval.eval c.globals [] Prim.nat_ty in
        Ok (ty, Quantity.empty)
  | Term.Lit (Literal.LString _) -> Error (Error.Not_yet string_word)
  | Term.In (_, _, _) -> Error (no_infer "an injection")
  | Term.Sec (_, _) -> Error (no_infer "a section")
  | Term.Auto -> Error (Error.Not_yet Rules.auto_word)

and check_uses (c : ctx) (mode : Quantity.t) (t : Term.t) (expected : Value.t) :
    (Quantity.usage, Error.t) result =
  match t with
  | Term.Sec (s, legs) ->
      let* (pack : ctx Rules.rule_pack) = Rules.rules s in
      pack.Rules.intro_sec ops c mode s legs ~expected
  | Term.In (s, addr, args) ->
      let* (pack : ctx Rules.rule_pack) = Rules.rules s in
      pack.Rules.intro_in ops c mode s addr args ~expected
  | Term.Elim e ->
      let* (pack : ctx Rules.rule_pack) = Rules.rules e.Term.e_shape in
      let* got, uses = pack.Rules.elim_elim ops c mode e ~expected:(Some expected) in
      let* () = ensure c got expected in
      Ok uses
  | Term.Lan (s, diagram) ->
      Result.map (fun () -> Quantity.empty) (check_former c s diagram expected ~left:true)
  | Term.Ran (s, diagram) ->
      Result.map (fun () -> Quantity.empty) (check_former c s diagram expected ~left:false)
  | Term.Let (x, ty, def, body) ->
      Result.map snd (let_body c mode x ty def (fun c' ->
        let* uses = check_uses c' mode body expected in Ok (expected, uses)))
  | Term.Var _ | Term.Univ _ | Term.Out (_, _, _) | Term.Ann (_, _) | Term.Global _
  | Term.Lit _ | Term.Auto ->
      let* got, uses = infer_uses c mode t in
      let* () = ensure c got expected in
      Ok uses

(** A former checked against a universe passes the expected level to the
    pack (SB-D6), which is what gives the width zero collection its
    universe (D-M0-6).  M0 has no cumulativity, so the level the pack
    reports must be the level expected (SB-D2). *)
and check_former (c : ctx) (s : Term.t Shape.t) (diagram : Term.t) (expected : Value.t)
    ~(left : bool) : (unit, Error.t) result =
  let* w = Eval.whnf c.globals expected in
  let* l0 =
    Value.as_univ w
    |> Option.to_result
         ~none:
           (Error.Universe
              ("a type former is checked against a type that is not a universe:  "
              ^ pp_value c w))
  in
  let* (pack : ctx Rules.rule_pack) = Rules.rules s in
  let former = if left then pack.Rules.form_lan else pack.Rules.form_ran in
  let* l = former ops c s diagram ~expected:(Some l0) in
  if Level.equal l l0 then Ok ()
  else
    Error
      (Error.Universe
         (Printf.sprintf "the former lives at %s and the expected universe is %s"
            (Level.to_string l) (Level.to_string l0)))

(** The subsumption step:  an inferred type must convert with the
    expected one.  There is no cumulativity at M0, so conversion is the
    whole relation. *)
and ensure (c : ctx) (got : Value.t) (expected : Value.t) : (unit, Error.t) result =
  let* eq = Conv.conv_type ops c got expected in
  if eq then Ok ()
  else
    Error
      (Error.Mismatch
         (Printf.sprintf "the term has type %s and the expected type is %s"
            (pp_value c got) (pp_value c expected)))

(** Eager definitions count once. An implicit alias carrying a linear
    resource is affine: its own reads may be zero or one, never duplicated. *)
and let_body (c : ctx) (mode : Quantity.t) (x : string) (ty : Term.t) (def : Term.t)
    (body : ctx -> (Value.t * Quantity.usage, Error.t) result) :
    (Value.t * Quantity.usage, Error.t) result =
  let* _l = infer_univ c ty in
  let* tyv = Eval.eval c.globals c.env ty in
  let* def_uses = check_uses c (Quantity.runtime mode) def tyv in
  let* defv = Eval.eval c.globals c.env def in
  let linear = List.exists (fun (ix, (_name, q, _ty)) ->
    Quantity.equal q Quantity.One && Quantity.used (c.size - ix - 1) def_uses)
    (List.mapi (fun ix local -> ix, local) c.locals) in
  let q = if Quantity.equal mode Quantity.Zero then Quantity.Zero
          else if linear then Quantity.One else Quantity.Many in
  let c' = define x q tyv defv c in
  let* result, uses = body c' in
  let* free = close ~affine:linear c' c.size mode uses in
  Ok (result, Quantity.sequence (Quantity.scale mode def_uses) free)

let infer (c : ctx) (mode : Quantity.t) (t : Term.t) : (Value.t, Error.t) result =
  Result.map fst (infer_uses c (Quantity.runtime mode) t)

let check (c : ctx) (mode : Quantity.t) (t : Term.t) (expected : Value.t) :
    (unit, Error.t) result =
  Result.map (fun _uses -> ()) (check_uses c (Quantity.runtime mode) t expected)

(** The two kinds of declaration M0 has.  A definition carries a body, an
    axiom does not (R-Q3). *)
type kind =
  | Definition
  | Postulate

type decl = {
  d_name : string;
  d_kind : kind;
  d_ty : Term.t;
  d_body : Term.t option;  (** [None] for a postulate *)
}

let missing_body (n : string) : Error.t =
  Error.Cannot_infer ("the definition " ^ n ^ " has no body")

(** Check one declaration against the environment built so far.  The name
    is added by the caller and only after this returns, so a self
    reference in the body is [Error (Unbound name)]. *)
let check_decl (globals : Global.t) (budget : Budget.t) (d : decl) :
    (Global.entry, Error.t) result =
  let c : ctx = make globals budget in
  let* _l = infer_univ c d.d_ty in
  let* tyv = Eval.eval globals [] d.d_ty in
  match d.d_kind with
  | Postulate -> Ok (Global.Axiom { Global.ax_ty = d.d_ty })
  | Definition ->
      let* body =
        d.d_body |> Option.to_result ~none:(missing_body d.d_name)
      in
      let* () = check c Quantity.Many body tyv in
      (* SB-D24:  M0 has no recursion, so unfolding ends and every
         definition is reducible with no guarded argument. *)
      Ok
        (Global.Def
           {
             Global.ty = d.d_ty;
             def = body;
             reducible = true;
             rec_arg = None;
             partial = false;
           })

(** Check a declaration list in order and return the checked entries in
    declaration order.  Each entry joins the environment the next
    declaration is checked against. *)
let check_decls ?(budget : Budget.t = Budget.unlimited) (globals : Global.t)
    (ds : decl list) : ((string * Global.entry) list, Error.t) result =
  List.fold_left
    (fun (acc : (Global.t * (string * Global.entry) list, Error.t) result) (d : decl) ->
      let* g, rows = acc in
      let* entry = check_decl g budget d in
      Ok (Global.add d.d_name entry g, (d.d_name, entry) :: rows))
    (Ok (globals, []))
    ds
  |> Result.map
       (fun ((_g : Global.t), (rows : (string * Global.entry) list)) -> List.rev rows)

(** M1 Stage G, brief 3.4:  the family declaration, mirroring pin
    check.ml:1800-1830.  A mutual group declares every member before the
    first constructor is installed (A4). *)
type family_decl = {
  fam_name : string;
  fam_params : Positivity.telescope;
  fam_indices : Positivity.telescope;
  fam_level : Level.t;
}

(** One constructor as the surface gives it, under the parameters. *)
type ctor_decl = {
  ct_name : string;
  ct_args : Positivity.telescope;
  ct_res_params : Term.t list;
  ct_res_idx : Term.t list;
}

(** Every type of a telescope is a type and each entry binds for the
    entries after it (pin check.ml:1804-1810). *)
let check_telescope (c : ctx) (tele : Positivity.telescope) : (ctx, Error.t) result =
  List.fold_left
    (fun (acc : (ctx, Error.t) result) ((q : Quantity.t), (x : string), (ty : Term.t)) ->
      let* c' = acc in
      let* _l = infer_univ c' ty in
      let* tyv = Eval.eval c'.globals c'.env ty in
      Ok (bind x q tyv c'))
    (Ok c) tele

(** The two index rules of brief 3.4.  An index binder is at
    [Quantity.Zero], refused as [Index_not_zero] (pin check.ml:1819, A2),
    which makes the Stage J erasure sound;  an index type is at or below
    the declared level by [Level.le], refused as [Index_above_universe]
    (pin check.ml:1820-1823, A5).  SG-M4 removes the first refusal. *)
let index_rules (c : ctx) (name : string) (level : Level.t)
    ((q, x, ty) : Quantity.t * string * Term.t) : (unit, Error.t) result =
  let* () =
    if Quantity.equal q Quantity.Zero then Ok ()
    else
      Error
        (Error.Index_not_zero
           (Printf.sprintf
              "the index %s of %s is at quantity %s and every index binder is at 0" x name
              (Quantity.to_string q)))
  in
  let* l = infer_univ c ty in
  if Level.le l level then Ok ()
  else
    Error
      (Error.Index_above_universe
         (Printf.sprintf "the index %s of %s lives at %s and %s is declared at %s" x name
            (Level.to_string l) name (Level.to_string level)))

(** The index telescope:  the two rules, then the binder of
    [check_telescope], so the two walks never drift. *)
let check_index_telescope (c : ctx) (name : string) (level : Level.t)
    (tele : Positivity.telescope) : (ctx, Error.t) result =
  List.fold_left
    (fun (acc : (ctx, Error.t) result) (e : Quantity.t * string * Term.t) ->
      let* c' = acc in
      let* () = index_rules c' name level e in
      check_telescope c' [ e ])
    (Ok c) tele

(** Declare one family.  The record enters the table at [Provisional]
    with no verdict, because no constructor is installed yet (A4). *)
let declare_family ?(budget : Budget.t = Budget.unlimited) (globals : Global.t)
    (d : family_decl) : (Global.t, Error.t) result =
  let* () =
    if Option.is_some (Global.find_family d.fam_name globals) then
      Error (Error.Mismatch ("the family " ^ d.fam_name ^ " is already declared"))
    else Ok ()
  in
  let c : ctx = make globals budget in
  let* pctx = check_telescope c d.fam_params in
  let* _ictx = check_index_telescope pctx d.fam_name d.fam_level d.fam_indices in
  Ok
    (Global.add_family d.fam_name
       {
         Positivity.f_name = d.fam_name;
         f_params = d.fam_params;
         f_indices = d.fam_indices;
         f_level = d.fam_level;
         f_status = Positivity.Provisional;
         f_ctors = [];
         f_positive = false;
       }
       globals)

(** A result parameter is the corresponding parameter variable under
    the constructor fields.  An annotation preserves that variable;
    its type is checked by the result telescope below. *)
let rec parameter_at (index : int) (tm : Term.t) : bool =
  match tm with
  | Term.Var i -> Int.equal i index
  | Term.Ann (body, _ty) -> parameter_at index body
  | Term.Univ _ | Term.Lan (_, _) | Term.Ran (_, _) | Term.In (_, _, _)
  | Term.Elim _ | Term.Sec (_, _) | Term.Out (_, _, _) | Term.Let (_, _, _, _)
  | Term.Global _ | Term.Lit _ | Term.Auto -> false

(** Constructor fields obey the declared predicative bound.  The result
    preserves the parameter variables and its indices check against the
    family telescope under all fields. *)
let check_ctor (c : ctx) (fam : Positivity.family) (group : string list)
    (cd : ctor_decl) : (Positivity.ctor, Error.t) result =
  let* actx =
    List.fold_left
      (fun (acc : (ctx, Error.t) result) ((q, x, ty) : Quantity.t * string * Term.t) ->
        let* c' = acc in
        let* l = infer_univ c' ty in
        let* () =
          if Level.le l fam.Positivity.f_level then Ok ()
          else Error (Error.Universe ("a field of " ^ cd.ct_name ^ " exceeds its family universe"))
        in
        check_telescope c' [ (q, x, ty) ])
      (Ok c) cd.ct_args
  in
  let* () = Positivity.ctor_fields group cd.ct_args in
  let np = List.length fam.Positivity.f_params in
  let depth = List.length cd.ct_args in
  let* () =
    if Int.equal (List.length cd.ct_res_params) np
       && List.for_all Fun.id
            (List.mapi (fun j tm -> parameter_at (depth + np - j - 1) tm) cd.ct_res_params)
    then Ok ()
    else Error (Error.Mismatch ("the constructor " ^ cd.ct_name ^ " must preserve its family parameters"))
  in
  let* penv =
    Rules.mu_telescope ops actx Quantity.Zero ("the parameters of " ^ cd.ct_name)
      fam.Positivity.f_params cd.ct_res_params []
  in
  let ni = List.length fam.Positivity.f_indices in
  let* () =
    if Int.equal (List.length cd.ct_res_idx) ni then Ok ()
    else
      Error
        (Error.Mismatch
           (Printf.sprintf "%s gives %d result indices and %s takes %d" cd.ct_name
              (List.length cd.ct_res_idx) fam.Positivity.f_name ni))
  in
  let* _ienv =
    Rules.mu_telescope ops actx Quantity.Zero ("the result indices of " ^ cd.ct_name)
      fam.Positivity.f_indices cd.ct_res_idx penv
  in
  Ok
    {
      Positivity.c_name = cd.ct_name;
      c_args = cd.ct_args;
      c_res_idx = cd.ct_res_idx;
      c_full_arity = List.length fam.Positivity.f_params + List.length cd.ct_args;
      c_self_rec = Positivity.self_rec group cd.ct_args;
    }

(** Install the constructors of one declared family (A4):  the verdict is
    computed once here and stored, formation reads it (rules.ml
    [mu_family], D-M1-2).  [group] is the mutual group.  SG-M1 mutates it. *)
let define_ctors ?(budget : Budget.t = Budget.unlimited) (globals : Global.t)
    ~(group : string list) ~(name : string) (cds : ctor_decl list) :
    (Global.t, Error.t) result =
  let* fam =
    Global.find_family name globals
    |> Option.to_result ~none:(Error.Unbound ("the family " ^ name ^ " is not declared"))
  in
  let* () =
    match fam.Positivity.f_status with
    | Positivity.Provisional -> Ok ()
    | Positivity.Builtin | Positivity.Complete _ ->
        Error (Error.Mismatch ("the constructors of " ^ name ^ " are already installed"))
  in
  let c : ctx = make globals budget in
  let* pctx = check_telescope c fam.Positivity.f_params in
  let* ctors =
    List.fold_left
      (fun (acc : (Positivity.ctor list, Error.t) result) (cd : ctor_decl) ->
        let* rows = acc in
        let* ct = check_ctor pctx fam group cd in
        Ok (rows @ [ ct ]))
      (Ok []) cds
  in
  Ok
    (Global.add_family name
       {
         fam with
         Positivity.f_status =
           Positivity.Complete (List.map (fun (cd : ctor_decl) -> cd.ct_name) cds);
         f_ctors = ctors;
         f_positive = true;
       }
       globals)

(** Entry points for one term, for a driver and for the suite. *)
let infer_term ?(budget : Budget.t = Budget.unlimited) (globals : Global.t)
    (t : Term.t) : (Value.t, Error.t) result =
  infer (make globals budget) Quantity.Many t

let check_term ?(budget : Budget.t = Budget.unlimited) (globals : Global.t) (t : Term.t)
    (ty : Value.t) : (unit, Error.t) result =
  check (make globals budget) Quantity.Many t ty
