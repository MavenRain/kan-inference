(** Type directed erasure, plan section 6 "Erasure", row by row, into the
    IR of eterm.ml.  The module mirrors kan-lang-tot-pin/lib/erase.ml arm
    by arm:  tot's [ctx] of kept flags is here at [slot]
    (kan-lang-tot-pin/lib/erase.ml:9), tot's [kept_index] is [lookup]
    (:12), tot's [term] is [term] and [node] (:15), and tot's [closed] is
    [program] (:90).  tot's four term arms that M0 splits are named at
    the arm that carries them.

    What the checker has already proved (Stage B hand-off note).  Every
    type position is read at mode [Zero] through [Check.infer_univ], a
    local stamped [Zero] is readable at mode [Zero] alone, and a runtime
    read of one is [Error (Quantity ..)].  So erasure drops exactly the
    binders stamped [Zero], the positions whose term is a type and the
    positions whose term is a proof, and no runtime position reads one of
    them.

    Classification is type directed and asks the checker (SC-D4).  A
    position carries the type its parent expects, or the type
    [Check.infer] reads out of it when the parent expects none, because
    [Check.infer] refuses a section and an injection exactly as the
    checker does (SC-D23).  Emission walks the original syntax: a
    primitive application stays a [KApp] of a [KGlobal].  The checking
    environment retains let definitions and instantiates dependent
    fibres at their points, just as the checker does.  These semantic
    values resolve types only; they never replace emitted runtime terms.

    This file spells shape names, and plan section 9 excludes it from the
    R0-AUDIT gate leg for that reason.  It is not in the trusted base:
    every erased declaration is re-checked by its golden. *)

let ( let* ) = Result.bind

(** What one declaration becomes.  [Code] holds the rec group, then the
    lifted functions, then the declaration's own function, in that order
    (SC-D3). *)
type entry =
  | Dropped  (** a type, a proposition or a proof:  nothing at runtime *)
  | Postulate of Eterm.repr  (** an axiom with a runtime type;  a use is KGlobal *)
  | Code of Eterm.kdecl list
      (** a def:  its rec group, its lifted functions, its own function *)

(** One entry per binder in scope, innermost first
    (kan-lang-tot-pin/lib/erase.ml:9, where the flag is a bool).  M0 adds
    the third case:  a [KLet] that erasure itself introduces binds a
    runtime value with no kernel binder behind it, so index lookup counts
    kernel binders and runtime binders apart (SC-D12). *)
type slot =
  | SDrop  (** a kernel binder with no runtime value *)
  | SKeep  (** a kernel binder that survives *)
  | SExtra  (** a runtime binder erasure introduced *)

type ectx = {
  c : Check.ctx;  (** the checker context this erasure stands in *)
  slots : slot list;  (** innermost first, one entry per binder in scope *)
  self : string;  (** the declaration being erased, the stem of every fid *)
}

(** The state that crosses the whole declaration:  the number of lambdas
    already lifted, in preorder from 0, the lifted functions in the order
    they finished (SC-D29), and the leg names of every mu family the
    declaration builds or eliminates (M1 Stage J, SJ-D21). *)
type acc = {
  next : int;
  lifted : Eterm.kdecl list;
  groups : Eterm.tid list;
      (** The leg struct names, in first mention order.  The rec group of
          the declaration carries them, so one rec group names one family
          and link.ml reads the layout of every branch binder off the tid
          text alone (D-M1-5, brief 3.2). *)
}

let globals_of (ec : ectx) : Global.t = ec.c.Check.globals
let size_of (ec : ectx) : int = ec.c.Check.size
let env_of (ec : ectx) : Value.t list = ec.c.Check.env

(** [Option.fold] reads its [~none] argument eagerly, so a branch that
    must not run when the option is [Some] sits behind a thunk. *)
let lazy_fold (o : 'a option) ~(none : unit -> 'b) ~(some : 'a -> 'b) : 'b =
  Option.fold ~none ~some:(fun (x : 'a) (() : unit) -> some x) o ()

(** The answer of an index lookup.  A dropped binder is not an error:
    plan section 6 makes its use [KErased] (SC-D12), where tot's erasure
    answers [Erased_use] because tot has no such position
    (kan-lang-tot-pin/lib/erase.ml:22-26). *)
type found =
  | LKeep of int
  | LDrop
  | LOut

(** How many runtime binders sit strictly closer to the use site than the
    kernel binder [ix] (kan-lang-tot-pin/lib/erase.ml:12). *)
let rec lookup (ix : int) (slots : slot list) (seen : int) : found =
  match slots with
  | [] -> LOut
  | SExtra :: rest -> lookup ix rest (seen + 1)
  | SKeep :: rest ->
      if Int.equal ix 0 then LKeep seen else lookup (ix - 1) rest (seen + 1)
  | SDrop :: rest -> if Int.equal ix 0 then LDrop else lookup (ix - 1) rest seen

(** A binder at [Zero] exists at check time alone, so it is never a
    runtime parameter.  [One] counts as [Many] at M0 (SB-D3). *)
let quantity_runtime (q : Quantity.t) : bool =
  (* SC-M1 site *)
  not (Quantity.equal q Quantity.Zero)

(** A total view on a value that stands for a type.  The four cases are
    the four the repr table of SC-D5 keys on. *)
type form =
  | FUniv
  | FLan of Value.t Shape.t * Value.closure
  | FRan of Value.t Shape.t * Value.closure
  | FNat
  | FOther

(** A total view on the shape of a former.  The two admitted shapes are
    the point shape and the collection shape;  every other shape is
    refused with the milestone word rules.ml holds. *)
type point =
  | PPoint of Quantity.t * string * Value.t
  | PColl of int
  | POther

let form_of (w : Value.t) : form =
  let neutral (() : unit) : form =
    Value.as_neutral w
    |> Option.fold ~none:FOther
         ~some:(fun ((h : Value.head), (sp : Value.spine list)) ->
           if Value.head_equal h (Value.HGlobal Prim.nat_name) && List.is_empty sp then
             FNat
           else FOther)
  in
  Value.as_univ w
  |> Option.fold
       ~none:
         (Value.as_lan w
         |> Option.fold
              ~none:
                (Value.as_ran w
                |> Option.fold ~none:(neutral ())
                     ~some:(fun
                         ( (s : Value.t Shape.t),
                           (d : Value.closure),
                           (_u : Level.t option) )
                       -> FRan (s, d)))
              ~some:(fun
                  ((s : Value.t Shape.t), (d : Value.closure), (_u : Level.t option))
                -> FLan (s, d)))
       ~some:(fun (_l : Level.t) -> FUniv)

let point_of (s : Value.t Shape.t) : point =
  Rules.as_vpi s
  |> Option.fold
       ~none:
         (Rules.as_vcoll s
         |> Option.fold ~none:POther ~some:(fun (n : int) -> PColl n))
       ~some:(fun ((q : Quantity.t), (x : string), (dom : Value.t)) ->
         PPoint (q, x, dom))

(** The two width zero formers are erased at every position (SC-D5), so a
    binder at one of them is dropped as a [Zero] binder is (SC-D20). *)
let width_zero (w : Value.t) : bool =
  let coll (o : (Value.t Shape.t * Value.closure * Level.t option) option) : bool =
    o
    |> Option.fold ~none:false
         ~some:(fun
             ((s : Value.t Shape.t), (_d : Value.closure), (_u : Level.t option)) ->
           Option.equal Int.equal (Rules.as_vcoll s) (Some 0))
  in
  coll (Value.as_lan w) || coll (Value.as_ran w)

(** The proof test.  The term at this position is a proof when the type
    it carries lives at the proposition universe (plan section 6). *)
let proof_free (ec : ectx) (w : Value.t) : (bool, Error.t) result =
  let* t = Eval.quote (globals_of ec) (size_of ec) w in
  let* l = Check.infer_univ ec.c t in
  (* SC-M2 site *)
  Ok (not (Level.equal l Level.zero))

(** Is a position with this type a runtime position.  It is not when the
    term there is a type, when the term there is a proof, and when the
    type is one of the two width zero formers. *)
let runtime_ty (ec : ectx) (ty : Value.t) : (bool, Error.t) result =
  let* w = Eval.whnf (globals_of ec) ty in
  match () with
  | () when Option.is_some (Value.as_univ w) -> Ok false
  | () when width_zero w -> Ok false
  | () -> proof_free ec w

(** A binder is runtime when its mark is not [Zero] and its type is a
    runtime type. *)
let point_runtime (ec : ectx) (q : Quantity.t) (dom : Value.t) : (bool, Error.t) result =
  if quantity_runtime q then runtime_ty ec dom else Ok false

(** The repr of a runtime value whose type is outside the table of
    SC-D5:  a neutral type, an axiom type, an application of an axiom
    family.  link.ml resolves it to eqref at Stage D (SC-D6). *)
let any_repr : Eterm.repr = Eterm.RUnion (Eterm.Tid "any")

let unit_leg : string = "unit"

(** The name of the synthetic binder a pair elimination gives its
    scrutinee (SC-D24). *)
let scrut_name : string = "scrut"

(** M1 Stage J, brief 3.2 and SJ-D5:  the tid of a value of a mu family
    is the family name alone.  An index argument never reaches the text,
    because every index binder of the family record stands at quantity
    Zero and erases (A2, M1-PLAN.md:105), so two constructors that differ
    only in indices carry one tid and one tag.  link.ml dedups by this
    text (wasm/link.ml:167-168). *)
let mu_tid (n : string) : Eterm.tid = Eterm.Tid ("mu<" ^ n ^ ">")

(** SJ-D5:  the leg struct of the constructor at index [k] of the family
    [n], in the shape of the M0 leg name:  the family tid, the
    constructor index and the reprs of the runtime fields in declaration
    order, and no repr at all for a constructor with no runtime field.
    The legs of one family share the prefix [leg<mu<NAME>,], so the
    boundary of a rec group reads off the text alone (brief 3.2). *)
let mu_leg_tid (n : string) (k : int) (rs : Eterm.repr list) : Eterm.tid =
  Eterm.Tid
    (Printf.sprintf "leg<%s,%d%s>"
       (Eterm.tid_text (mu_tid n))
       k
       (String.concat ""
          (List.map (fun (r : Eterm.repr) -> "," ^ Eterm.print_repr r) rs)))

(** The position of a name in a list, which is the constructor index of
    SJ-D5.  The fold answers the first hit and never indexes the list. *)
let position (x : string) (xs : string list) : int option =
  snd
    (List.fold_left
       (fun ((i : int), (found : int option)) (y : string) ->
         ( i + 1,
           lazy_fold found
             ~none:(fun (() : unit) ->
               match String.equal x y with true -> Some i | false -> None)
             ~some:(fun (j : int) -> Some j) ))
       (0, None) xs)

(** The word a branch whose binders do not match its constructor gets.
    The checker rejects such a leg long before erasure (rules.ml
    [mu_branch]), so the arm stands for totality alone. *)
let branch_arity_word : string =
  "a branch binds a different number of fields than its constructor takes"

(** The repr table of SC-D5, read off the type after weak head normal
    form.  The tid is the structural name, printed the same way
    everywhere, so link.ml dedups by string at Stage D. *)
let rec repr_of (ec : ectx) (v : Value.t) : (Eterm.repr, Error.t) result =
  let* w = Eval.whnf (globals_of ec) v in
  match form_of w with
  | FNat -> Ok (Eterm.RUnion (Eterm.Tid "nat"))
  | FUniv -> Ok any_repr
  | FOther -> Ok any_repr
  | FRan (s, d) -> ran_repr ec s d
  | FLan (s, d) -> lan_repr ec s d

and ran_repr (ec : ectx) (s : Value.t Shape.t) (d : Value.closure) :
    (Eterm.repr, Error.t) result =
  match point_of s with
  | PPoint (_q, _x, _dom) ->
      let* n = arity_of ec 0 s d in
      Ok (Eterm.RFunc (Eterm.Tid (Printf.sprintf "fn<%d>" n)))
  | PColl n ->
      if Int.equal n 0 then Ok any_repr
      else
        let* texts = tuple_texts ec n d in
        Ok (Eterm.RStruct (Eterm.Tid ("tuple<" ^ String.concat "," texts ^ ">")))
  | POther -> Ok any_repr

and lan_repr (ec : ectx) (s : Value.t Shape.t) (d : Value.closure) :
    (Eterm.repr, Error.t) result =
  lazy_fold (Rules.as_vmu s)
    ~none:(fun (() : unit) -> lan_point_repr ec s d)
    ~some:(fun (((n : string), (_ix : Value.t list)) : string * Value.t list) ->
      Ok (Eterm.RUnion (mu_tid n)))

(** Every left former that is not a mu family (SC-D5). *)
and lan_point_repr (ec : ectx) (s : Value.t Shape.t) (d : Value.closure) :
    (Eterm.repr, Error.t) result =
  match point_of s with
  | PPoint (q, x, dom) ->
      let* texts = pair_texts ec q x dom d in
      Ok (Eterm.RStruct (Eterm.Tid ("pair<" ^ String.concat "," texts ^ ">")))
  | PColl n ->
      if Int.equal n 0 then Ok any_repr
      else
        let* texts = sum_texts ec n d in
        Ok (Eterm.RUnion (Eterm.Tid ("sum<" ^ String.concat "|" texts ^ ">")))
  | POther -> Ok any_repr

(** The arity class of a function type:  the number of runtime points of
    the whole chain, so a [Zero] point and a proof point are not counted
    and the class matches the parameter list the chain lifts to. *)
and arity_of (ec : ectx) (n : int) (s : Value.t Shape.t) (d : Value.closure) :
    (int, Error.t) result =
  match point_of s with
  | PColl _ -> Ok n
  | POther -> Ok n
  | PPoint (q, x, dom) ->
      let* keep = point_runtime ec q dom in
      let* ec', cod = under_point ec x q dom d in
      let* w = Eval.whnf (globals_of ec') cod in
      arity_rest ec' (if keep then n + 1 else n) w

and arity_rest (ec : ectx) (n : int) (w : Value.t) : (int, Error.t) result =
  match form_of w with
  | FRan (s, d) -> arity_of ec n s d
  | FLan (_, _) | FUniv | FNat | FOther -> Ok n

(** The codomain used for a structural repr, opened at a fresh variable
    so the layout does not depend on a particular constructor point. *)
and under_point (ec : ectx) (x : string) (q : Quantity.t) (dom : Value.t)
    (d : Value.closure) : (ectx * Value.t, Error.t) result =
  let* cod =
    Rules.open_closure (Eval.ev (globals_of ec)) d [ Value.var (size_of ec) ]
  in
  Ok ({ ec with c = Check.bind x q dom ec.c; slots = SDrop :: ec.slots }, cod)

and pair_texts (ec : ectx) (q : Quantity.t) (x : string) (dom : Value.t)
    (d : Value.closure) : (string list, Error.t) result =
  let* keep1 = point_runtime ec q dom in
  let* first = repr_text ec keep1 dom in
  let* ec', cod = under_point ec x q dom d in
  let* keep2 = runtime_ty ec' cod in
  let* second = repr_text ec' keep2 cod in
  Ok (first @ second)

and repr_text (ec : ectx) (keep : bool) (ty : Value.t) : (string list, Error.t) result =
  if keep then Result.map (fun (r : Eterm.repr) -> [ Eterm.print_repr r ]) (repr_of ec ty)
  else Ok []

(** The leg types of a collection diagram, in leg order. *)
and leg_types (ec : ectx) (n : int) (d : Value.closure) : (Value.t list, Error.t) result =
  let* legs = Rules.coll_legs_of Check.ops ec.c d in
  Rules.all_ok
    (List.map
       (fun (k : int) -> Rules.coll_leg_ty Check.ops ec.c legs k)
       (List.init n Fun.id))

(** Which legs of a collection carry a runtime value, in leg order. *)
and leg_flags (ec : ectx) (n : int) (d : Value.closure) : (bool list, Error.t) result =
  let* tys = leg_types ec n d in
  Rules.all_ok (List.map (fun (ty : Value.t) -> runtime_ty ec ty) tys)

and sum_texts (ec : ectx) (n : int) (d : Value.closure) : (string list, Error.t) result =
  let* tys = leg_types ec n d in
  Rules.all_ok
    (List.map
       (fun (ty : Value.t) ->
         let* rt = runtime_ty ec ty in
         if rt then Result.map Eterm.print_repr (repr_of ec ty) else Ok unit_leg)
       tys)

and tuple_texts (ec : ectx) (n : int) (d : Value.closure) :
    (string list, Error.t) result =
  let* tys = leg_types ec n d in
  let* texts =
    Rules.all_ok
      (List.map
         (fun (ty : Value.t) ->
           let* rt = runtime_ty ec ty in
           repr_text ec rt ty)
         tys)
  in
  Ok (List.concat texts)

(** The tid of a structured runtime type.  A KStruct, a KTag and a KProj
    all read their tid here, so the tid a term names and the tid its repr
    names are one string (SC-D5). *)
and tid_of (ec : ectx) (ty : Value.t) : (Eterm.tid, Error.t) result =
  let* r = repr_of ec ty in
  match r with
  | Eterm.RStruct t -> Ok t
  | Eterm.RUnion t -> Ok t
  | Eterm.RFunc t -> Ok t
  | Eterm.RThunk t -> Ok t
  | Eterm.RI31 ->
      Error (Error.Mismatch "a structured value stands at a type whose repr is i31")

(** One layout slot per constructor field, in declaration order.
    Parameters and earlier fields remain neutral here.  None marks a
    field that always erases; Some records its storage representation. *)
let rec mu_leg_reprs (ec : ectx) (env : Value.t list)
    (tele : Positivity.telescope) : (Eterm.repr option list, Error.t) result =
  match tele with
  | [] -> Ok []
  | ((q : Quantity.t), (x : string), (ty : Term.t)) :: rest ->
      let* tyv = Eval.eval (globals_of ec) env ty in
      let* keep = point_runtime ec q tyv in
      let* here =
        if keep then Result.map Option.some (repr_of ec tyv)
        else Ok None
      in
      let ec' =
        { ec with c = Check.bind x q tyv ec.c; slots = SDrop :: ec.slots }
      in
      let* more = mu_leg_reprs ec' (Value.var (size_of ec) :: env) rest in
      Ok (here :: more)

(** Layouts open parameters as variables, so every instantiation of a
    nominal family uses the same fields and representations. *)
let rec mu_parameters (ec : ectx) (tele : Positivity.telescope) :
    (ectx, Error.t) result =
  match tele with
  | [] -> Ok ec
  | (q, x, ty) :: rest ->
      let* tyv = Eval.eval (globals_of ec) (env_of ec) ty in
      mu_parameters
        { ec with c = Check.bind x q tyv ec.c; slots = SDrop :: ec.slots }
        rest

let mu_layout (ec : ectx) (fam : Positivity.family) (ct : Positivity.ctor) :
    (Eterm.repr option list, Error.t) result =
  let fresh =
    { ec with c = Check.make (globals_of ec) ec.c.Check.budget; slots = [] }
  in
  let* params = mu_parameters fresh fam.Positivity.f_params in
  mu_leg_reprs params (env_of params) ct.Positivity.c_args

(** SJ-D5 and SJ-D21:  the leg names of a whole family, in declaration
    order.  A declaration publishes these names in its rec group, so
    link.ml has one text channel that carries the layout of every branch
    binder and the boundary of the group (D-M1-5, brief 3.2). *)
let mu_group_tids (ec : ectx) (n : string) (fam : Positivity.family) :
    (Eterm.tid list, Error.t) result =
  let* names = Rules.mu_ctor_names n fam in
  Rules.all_ok
    (List.mapi
       (fun (k : int) (c : string) ->
         let* ct =
           Positivity.ctor_of c fam
           |> Option.to_result
                ~none:(Error.Unbound (c ^ " is not a constructor of " ^ n))
         in
         let* rs = mu_layout ec fam ct in
         Ok (mu_leg_tid n k (List.filter_map Fun.id rs)))
       names)

(** A total zip:  a pair list as long as the shorter side.  The lists
    this file zips are two readings of one leg list, so they are the same
    length whenever the checker passed. *)
let rec zip (xs : 'a list) (ys : 'b list) : ('a * 'b) list =
  match (xs, ys) with
  | [], [] -> []
  | [], _y :: _yr -> []
  | _x :: _xr, [] -> []
  | x :: xr, y :: yr -> (x, y) :: zip xr yr

(** Candidate kernel indices in value syntax, relative to the enclosing
    scope, with repeats. Types, shapes and motives have no runtime reads.
    Leg bodies and let bodies advance depth by their kernel binders. *)
let rec free_vars (depth : int) (t : Term.t) : int list =
  match t with
  | Term.Var ix -> if ix >= depth then [ ix - depth ] else []
  | Term.Univ _ -> []
  | Term.Global _ -> []
  | Term.Lit _ -> []
  | Term.Auto -> []
  | Term.Lan (_s, _d) -> []
  | Term.Ran (_s, _d) -> []
  | Term.In (_s, a, args) -> free_addr depth a @ List.concat_map (free_vars depth) args
  | Term.Out (_s, a, head) -> free_addr depth a @ free_vars depth head
  | Term.Sec (_s, legs) -> List.concat_map (free_leg depth) legs
  | Term.Elim e ->
      free_vars depth e.Term.e_scrut
      @ List.concat_map
          (fun ((_a : Term.addr), (lg : Term.leg)) -> free_leg depth lg)
          e.Term.e_branches
  | Term.Let (_x, _ty, def, body) -> free_vars depth def @ free_vars (depth + 1) body
  | Term.Ann (tm, _ty) -> free_vars depth tm

and free_addr (depth : int) (a : Term.addr) : int list =
  Term.as_apt a
  |> Option.fold ~none:[] ~some:(fun ((_q : Quantity.t), (arg : Term.t)) ->
         free_vars depth arg)

and free_leg (depth : int) (lg : Term.leg) : int list =
  free_vars (depth + List.length lg.Term.l_binders) lg.Term.l_body

(** Conservative runtime capture candidates, without type syntax. APt
    arguments remain candidates regardless of their annotation: the
    checked function quantity, read by erasure, controls their liveness.
    The erased-body pass below removes candidates whose positions erase. *)
let captures_of (ec : ectx) (t : Term.t) : int list =
  List.sort_uniq Int.compare
    (List.filter
       (fun (ix : int) ->
         match lookup ix ec.slots 0 with
         | LKeep _ -> true
         | LDrop -> false
         | LOut -> false)
       (free_vars 0 t))

(** Rewrite free runtime indices. Branch payloads and lets bind locally;
    closure capture arguments are expressions in the enclosing context. *)
let rec reindex_runtime (index : int -> int) (depth : int) (t : Eterm.ktm) : Eterm.ktm =
  let shift = reindex_runtime index depth in
  match t with
  | Eterm.KVar i -> Eterm.KVar (if i >= depth then depth + index (i - depth) else i)
  | Eterm.KLit _ | Eterm.KGlobal _ | Eterm.KErased -> t
  | Eterm.KLet (x, v, b) ->
      Eterm.KLet (x, shift v, reindex_runtime index (depth + 1) b)
  | Eterm.KClos (f, n, cs) -> Eterm.KClos (f, n, List.map shift cs)
  | Eterm.KApp (h, args) -> Eterm.KApp (shift h, List.map shift args)
  | Eterm.KTail (h, args) -> Eterm.KTail (shift h, List.map shift args)
  | Eterm.KStruct (tid, fs) -> Eterm.KStruct (tid, List.map shift fs)
  | Eterm.KProj (tid, k, s) -> Eterm.KProj (tid, k, shift s)
  | Eterm.KTag (tid, k, ps) -> Eterm.KTag (tid, k, List.map shift ps)
  | Eterm.KCase (tid, s, bs) ->
      Eterm.KCase
        ( tid, shift s,
          List.map
            (fun (b : Eterm.kbranch) ->
              { b with body = reindex_runtime index (depth + b.arity) b.body })
            bs )
  | Eterm.KDelay (f, cs) -> Eterm.KDelay (f, List.map shift cs)
  | Eterm.KForce x -> Eterm.KForce (shift x)

let shift_runtime (by : int) (depth : int) (t : Eterm.ktm) : Eterm.ktm =
  reindex_runtime (fun (i : int) -> i + by) depth t

(** Actual reads after quantity and proof erasure, including the reads
    used to construct nested closure environments. *)
let rec runtime_vars (depth : int) (t : Eterm.ktm) : int list =
  let walk = runtime_vars depth in
  match t with
  | Eterm.KVar i -> if i >= depth then [ i - depth ] else []
  | Eterm.KLit _ | Eterm.KGlobal _ | Eterm.KErased -> []
  | Eterm.KLet (_x, v, b) -> walk v @ runtime_vars (depth + 1) b
  | Eterm.KClos (_, _, cs) | Eterm.KDelay (_, cs) -> List.concat_map walk cs
  | Eterm.KApp (h, args) | Eterm.KTail (h, args) -> walk h @ List.concat_map walk args
  | Eterm.KStruct (_, fs) | Eterm.KTag (_, _, fs) -> List.concat_map walk fs
  | Eterm.KProj (_, _, x) | Eterm.KForce x -> walk x
  | Eterm.KCase (_tid, s, bs) ->
      walk s @ List.concat_map
        (fun (b : Eterm.kbranch) -> runtime_vars (depth + b.arity) b.body) bs

(** Captures precede ordinary parameters in a lifted signature. Keep
    their declaration order and compress only those outer indices that
    disappeared during erasure. This is applied after nested lifting. *)
let prune_captures (ps : Eterm.repr list) (args : Eterm.ktm list) (params : int)
    (body : Eterm.ktm) : Eterm.repr list * Eterm.ktm list * Eterm.ktm =
  let count = List.length ps in
  let live = List.sort_uniq Int.compare
    (List.filter_map
       (fun (i : int) -> if i >= params && i < params + count then Some (i - params)
         else None) (runtime_vars 0 body)) in
  let keep (i : int) : bool = List.mem (count - i - 1) live in
  let index (i : int) : int =
    if i < params then i
    else params + List.length (List.filter (fun (j : int) -> j < i - params) live) in
  (List.filteri (fun (i : int) (_r : Eterm.repr) -> keep i) ps,
   List.filteri (fun (i : int) (_arg : Eterm.ktm) -> keep i) args,
   reindex_runtime index 0 body)

(** A shape past M0 never reaches erasure, because the checker refused it
    first.  The arm is total and reads its word from rules.ml, so no
    milestone word is written twice (SA-D5). *)
let refused (s : Term.t Shape.t) : (Eterm.ktm * acc, Error.t) result =
  let* (_pack : Check.ctx Rules.rule_pack) = Rules.rules s in
  Error (Error.Not_yet "an erasure at a shape past M0")

(** M1 Stage J, brief 3.1 and A6.  The interim word of Stage G is gone:
    an introduction at a mu family and an elimination of a mu family have
    rows of their own below ([mu_intro] and [mu_elim],
    M1-PLAN.md:103-106).  SPar and SNu keep [refused] above, and a
    section and a section elimination at a mu shape keep the word
    rules.ml already holds, because the right former at that shape
    arrives at M2 (rules.ml [mu_ran_word], SA-D5). *)

(** The application view.  [Out] at a point shape with a point address is
    one argument of a spine;  every other node ends the spine. *)
let as_app (t : Term.t) : (Quantity.t * Term.t * Term.t * Term.t) option =
  match t with
  | Term.Out (Shape.SPi (_q, _x, dom), Term.APt (qa, arg), head) ->
      Some (qa, dom, arg, head)
  | Term.Out (Shape.SPi (_, _, _), Term.ALeg _, _) -> None
  | Term.Out (Shape.SPi (_, _, _), Term.ACtor _, _) -> None
  | Term.Out (Shape.SColl _, _, _) -> None
  | Term.Out (Shape.SPar (_, _), _, _) -> None
  | Term.Out (Shape.SMu (_, _), _, _) -> None
  | Term.Out (Shape.SNu (_, _), _, _) -> None
  | Term.Var _ -> None
  | Term.Univ _ -> None
  | Term.Lan (_, _) -> None
  | Term.Ran (_, _) -> None
  | Term.In (_, _, _) -> None
  | Term.Sec (_, _) -> None
  | Term.Elim _ -> None
  | Term.Let (_, _, _, _) -> None
  | Term.Ann (_, _) -> None
  | Term.Global _ -> None
  | Term.Lit _ -> None
  | Term.Auto -> None

(** The head of an application spine and its arguments, outermost last,
    each with the mark and the domain the shape gave it. *)
let rec spine (t : Term.t) (args : (Quantity.t * Term.t * Term.t) list) :
    Term.t * (Quantity.t * Term.t * Term.t) list =
  lazy_fold (as_app t)
    ~none:(fun (() : unit) -> (t, args))
    ~some:(fun
        ( (q : Quantity.t),
          (dom : Term.t),
          (arg : Term.t),
          (head : Term.t) )
      -> spine head ((q, dom, arg) :: args))

(** The whole erasure, one bidirectional walk (SC-D23):  the expected
    type travels down from the parent, because [Check.infer] refuses an
    introduction form, and inference runs only where no parent said what
    the position holds. *)
let rec term (ec : ectx) (ac : acc) ~(tail : bool) ~(expected : Value.t option)
    (t : Term.t) : (Eterm.ktm * acc, Error.t) result =
  let* ty = position_ty ec expected t in
  let* rt = runtime_ty ec ty in
  if rt then node ec ac ~tail ~ty t else Ok (Eterm.KErased, ac)

(** The type of the position.  The thunk matters:  [Option.fold] reads
    [~none] eagerly, so an unguarded call would infer at every node. *)
and position_ty (ec : ectx) (expected : Value.t option) (t : Term.t) :
    (Value.t, Error.t) result =
  lazy_fold expected
    ~none:(fun (() : unit) -> Check.infer ec.c Quantity.Many t)
    ~some:(fun (ty : Value.t) -> Ok ty)

and node (ec : ectx) (ac : acc) ~(tail : bool) ~(ty : Value.t) (t : Term.t) :
    (Eterm.ktm * acc, Error.t) result =
  match t with
  (* kan-lang-tot-pin/lib/erase.ml:17 *)
  | Term.Var ix -> var_arm ec ac ix
  (* kan-lang-tot-pin/lib/erase.ml:27 and :28.  A universe and a former
     are types, so [runtime_ty] answered false above them and these three
     arms are the total backstop. *)
  | Term.Univ _ -> Ok (Eterm.KErased, ac)
  | Term.Lan (_, _) -> Ok (Eterm.KErased, ac)
  | Term.Ran (_, _) -> Ok (Eterm.KErased, ac)
  (* kan-lang-tot-pin/lib/erase.ml:29 *)
  | Term.Sec (s, legs) -> sec_arm ec ac ~ty s legs t
  (* kan-lang-tot-pin/lib/erase.ml:31 *)
  | Term.In (s, a, args) -> in_arm ec ac ~ty s a args
  (* kan-lang-tot-pin/lib/erase.ml:33 *)
  | Term.Out (s, a, head) -> out_arm ec ac ~tail ~ty s a head t
  (* kan-lang-tot-pin/lib/erase.ml:49 *)
  | Term.Elim e -> elim_arm ec ac ~tail ~ty e
  (* kan-lang-tot-pin/lib/erase.ml:38 *)
  | Term.Let (x, lty, v, body) -> let_arm ec ac ~tail ~ty x lty v body
  (* kan-lang-tot-pin/lib/erase.ml:42:  the annotation is a type and the
     term under it stands at that same type. *)
  | Term.Ann (tm, _aty) -> term ec ac ~tail ~expected:(Some ty) tm
  (* kan-lang-tot-pin/lib/erase.ml:43 *)
  | Term.Global n -> Ok (Eterm.KGlobal n, ac)
  | Term.Lit l -> Ok (Eterm.KLit l, ac)
  | Term.Auto -> Error (Error.Not_yet Rules.auto_word)

and var_arm (ec : ectx) (ac : acc) (ix : int) : (Eterm.ktm * acc, Error.t) result =
  match lookup ix ec.slots 0 with
  | LKeep i -> Ok (Eterm.KVar i, ac)
  | LDrop -> Ok (Eterm.KErased, ac)
  | LOut ->
      Error
        (Error.Unbound
           (Printf.sprintf "the erasure context has no binder at index %d" ix))

(** Erase a list of positions in order, threading the lifted functions. *)
and erase_fold (ec : ectx) (ac : acc) (jobs : (Value.t option * Term.t) list) :
    (Eterm.ktm list * acc, Error.t) result =
  List.fold_left
    (fun (r : (Eterm.ktm list * acc, Error.t) result)
         ((e : Value.t option), (t : Term.t)) ->
      let* xs, a = r in
      let* x, a' = term ec a ~tail:false ~expected:e t in
      Ok (xs @ [ x ], a'))
    (Ok ([], ac)) jobs

(** The lambda view:  one leg with one binder at a point shape. *)
and as_lam (t : Term.t) : Term.leg option =
  match t with
  | Term.Sec (Shape.SPi (_, _, _), [ lg ]) -> Some lg
  | Term.Sec (Shape.SPi (_, _, _), []) -> None
  | Term.Sec (Shape.SPi (_, _, _), _ :: _ :: _) -> None
  | Term.Sec (Shape.SColl _, _) -> None
  | Term.Sec (Shape.SPar (_, _), _) -> None
  | Term.Sec (Shape.SMu (_, _), _) -> None
  | Term.Sec (Shape.SNu (_, _), _) -> None
  | Term.Var _ -> None
  | Term.Univ _ -> None
  | Term.Lan (_, _) -> None
  | Term.Ran (_, _) -> None
  | Term.In (_, _, _) -> None
  | Term.Out (_, _, _) -> None
  | Term.Elim _ -> None
  | Term.Let (_, _, _, _) -> None
  | Term.Ann (_, _) -> None
  | Term.Global _ -> None
  | Term.Lit _ -> None
  | Term.Auto -> None

and sec_arm (ec : ectx) (ac : acc) ~(ty : Value.t) (s : Term.t Shape.t)
    (legs : Term.leg list) (t : Term.t) : (Eterm.ktm * acc, Error.t) result =
  match s with
  | Shape.SPi (_, _, _) -> lift_arm ec ac ~ty t
  | Shape.SColl n -> tuple_arm ec ac ~ty n legs
  | Shape.SPar (_, _) -> refused s
  | Shape.SMu (_, _) -> Error (Error.Not_yet Rules.mu_ran_word)
  | Shape.SNu (_, _) -> refused s

(** A tuple keeps its runtime legs alone, and a tuple with no runtime leg
    is erased whole (SC-D11). *)
and tuple_arm (ec : ectx) (ac : acc) ~(ty : Value.t) (n : int)
    (legs : Term.leg list) : (Eterm.ktm * acc, Error.t) result =
  let* w = Eval.whnf (globals_of ec) ty in
  match form_of w with
  | FRan (_s, d) ->
      let* tys = leg_types ec n d in
      let* flags = Rules.all_ok (List.map (fun (v : Value.t) -> runtime_ty ec v) tys) in
      let jobs =
        List.filter_map
          (fun ((((lg : Term.leg), (lty : Value.t)), (f : bool))) ->
            if f then Some (Some lty, lg.Term.l_body) else None)
          (zip (zip legs tys) flags)
      in
      let* fields, ac1 = erase_fold ec ac jobs in
      if List.is_empty fields then Ok (Eterm.KErased, ac1)
      else
        let* tid = tid_of ec ty in
        Ok (Eterm.KStruct (tid, fields), ac1)
  | FLan (_, _) | FUniv | FNat | FOther ->
      Error (Error.Mismatch "a tuple stands at a type that is not a right former")

(** SC-D3:  a lambda lifts to a [KFun] and leaves a [KClos] behind.  The
    parameter list is the runtime captures, outermost first, and then the
    runtime points of the whole chain, so a capture and a point are one
    kind of parameter inside the lifted body (SC-D25). *)
and lift_arm (ec : ectx) (ac : acc) ~(ty : Value.t) (t : Term.t) :
    (Eterm.ktm * acc, Error.t) result =
  let caps = captures_of ec t in
  let outer = List.rev caps in
  let* cap_tys =
    Rules.all_ok
      (List.map (fun (ix : int) -> Check.infer ec.c Quantity.Many (Term.Var ix)) outer)
  in
  let* cap_reprs = Rules.all_ok (List.map (fun (v : Value.t) -> repr_of ec v) cap_tys) in
  let* cap_args =
    Rules.all_ok
      (List.map
         (fun (ix : int) -> Result.map (fun ((k : Eterm.ktm), (_a : acc)) -> k) (var_arm ec ac ix))
         outer)
  in
  let fid = Eterm.Fid (Printf.sprintf "%s$%d" ec.self ac.next) in
  let ec0 = { ec with slots = frame ec.slots caps } in
  let* params, ret, body, ac1 = chain ec0 { ac with next = ac.next + 1 } [] ~ty t in
  let cap_reprs, cap_args, body =
    prune_captures cap_reprs cap_args (List.length params) body in
  let decl = Eterm.KFun (fid, cap_reprs @ params, ret, body) in
  Ok
    ( Eterm.KClos (fid, List.length params, cap_args),
      { ac1 with lifted = ac1.lifted @ [ decl ] } )

(** The slots of the enclosing scope as the lifted body reads them:  a
    captured binder stays a parameter, every other binder is gone, and the
    synthetic binders leave the list because no kernel index names one. *)
and frame (slots : slot list) (caps : int list) : slot list =
  List.mapi
    (fun (j : int) (s : slot) ->
      match s with
      | SKeep -> if List.exists (Int.equal j) caps then SKeep else SDrop
      | SDrop -> SDrop
      | SExtra -> SDrop)
    (List.filter
       (fun (s : slot) ->
         match s with SExtra -> false | SKeep -> true | SDrop -> true)
       slots)

(** Peel the lambda chain against the type chain and complete any
    remaining point parameters by eta expansion.  A body whose type is
    no longer a point former is a tail position (SC-D14). *)
and chain (ec : ectx) (ac : acc) (params : Eterm.repr list) ~(ty : Value.t)
    (t : Term.t) : (Eterm.repr list * Eterm.repr * Eterm.ktm * acc, Error.t) result =
  let* w = Eval.whnf (globals_of ec) ty in
  let stop (() : unit) :
      (Eterm.repr list * Eterm.repr * Eterm.ktm * acc, Error.t) result =
    let* ret = repr_of ec ty in
    let* body, ac1 = term ec ac ~tail:true ~expected:(Some ty) t in
    Ok (params, ret, body, ac1)
  in
  match (as_lam t, form_of w) with
  | Some lg, FRan (s, d) -> chain_step ec ac params ~stop lg s d
  | Some _lg, FUniv -> stop ()
  | Some _lg, FLan (_, _) -> stop ()
  | Some _lg, FNat -> stop ()
  | Some _lg, FOther -> stop ()
  | None, FUniv -> stop ()
  | None, FLan (_, _) -> stop ()
  | None, FRan (s, d) -> (
      match point_of s with
      | PPoint (_, _, _) -> eta_chain ec ac params ~ty t s d
      | PColl _ | POther -> stop ())
  | None, FNat -> stop ()
  | None, FOther -> stop ()

(** Complete a function-valued body to its type's whole parameter chain.
    This makes aliases and partial applications obey the same calling
    convention as explicit lambdas, including a chain of erased binders.
    The head is erased before the fresh runtime parameters are introduced. *)
and eta_chain (ec : ectx) (ac : acc) (params : Eterm.repr list) ~(ty : Value.t)
    (t : Term.t) (s : Value.t Shape.t) (d : Value.closure) :
    (Eterm.repr list * Eterm.repr * Eterm.ktm * acc, Error.t) result =
  let* head, ac1 = term ec ac ~tail:false ~expected:(Some ty) t in
  let* extra, ret = remaining_signature ec s d in
  let n = List.length extra in
  let args = List.init n (fun (i : int) -> Eterm.KVar (n - i - 1)) in
  let body = Eterm.KTail (shift_runtime n 0 head, args) in
  Ok (params @ extra, ret, body, ac1)

and remaining_signature (ec : ectx) (s : Value.t Shape.t) (d : Value.closure) :
    (Eterm.repr list * Eterm.repr, Error.t) result =
  match point_of s with
  | PPoint (q, x, dom) ->
      let* keep = point_runtime ec q dom in
      let* here =
        if keep then Result.map (fun (r : Eterm.repr) -> [ r ]) (repr_of ec dom)
        else Ok []
      in
      let* ec', cod = under_point ec x q dom d in
      let* w = Eval.whnf (globals_of ec') cod in
      let* rest, ret =
        match form_of w with
        | FRan (s', d') -> remaining_signature ec' s' d'
        | FLan (_, _) | FUniv | FNat | FOther ->
            Result.map (fun (r : Eterm.repr) -> ([], r)) (repr_of ec' cod)
      in
      Ok (here @ rest, ret)
  | PColl _ | POther ->
      Result.map (fun (r : Eterm.repr) -> ([], r)) (ran_repr ec s d)

and chain_step (ec : ectx) (ac : acc) (params : Eterm.repr list)
    ~(stop : unit -> (Eterm.repr list * Eterm.repr * Eterm.ktm * acc, Error.t) result)
    (lg : Term.leg) (s : Value.t Shape.t) (d : Value.closure) :
    (Eterm.repr list * Eterm.repr * Eterm.ktm * acc, Error.t) result =
  match point_of s with
  | PColl _ -> stop ()
  | POther -> stop ()
  | PPoint (q, x, dom) ->
      let* keep = point_runtime ec q dom in
      let* params' =
        if keep then Result.map (fun (r : Eterm.repr) -> params @ [ r ]) (repr_of ec dom)
        else Ok params
      in
      let* cod =
        Rules.open_closure (Eval.ev (globals_of ec)) d [ Value.var (size_of ec) ]
      in
      let ec' =
        {
          ec with
          c = Check.bind x q dom ec.c;
          slots = (if keep then SKeep else SDrop) :: ec.slots;
        }
      in
      chain ec' ac params' ~ty:cod lg.Term.l_body

and in_arm (ec : ectx) (ac : acc) ~(ty : Value.t) (s : Term.t Shape.t)
    (a : Term.addr) (args : Term.t list) : (Eterm.ktm * acc, Error.t) result =
  match s with
  | Shape.SPar (_, _) -> refused s
  | Shape.SMu (_, _) -> mu_intro ec ac ~ty a args
  | Shape.SNu (_, _) -> refused s
  | Shape.SPi (_, _, _) -> in_typed ec ac ~ty a args
  | Shape.SColl _ -> in_typed ec ac ~ty a args

and in_typed (ec : ectx) (ac : acc) ~(ty : Value.t) (a : Term.addr)
    (args : Term.t list) : (Eterm.ktm * acc, Error.t) result =
  let* w = Eval.whnf (globals_of ec) ty in
  match form_of w with
  | FLan (sv, d) -> (
      match point_of sv with
      | PPoint (q, x, dom) -> pair_intro ec ac ~ty q x dom d a args
      | PColl n -> tag_intro ec ac ~ty n d a args
      | POther -> Error (Error.Mismatch "an introduction at a shape past M0"))
  | FRan (_, _) | FUniv | FNat | FOther ->
      Error (Error.Mismatch "an introduction stands at a type that is not a left former")

(** A pair keeps the point when the point is runtime and the fibre when
    the fibre is runtime, and a pair with neither is erased whole. *)
and pair_intro (ec : ectx) (ac : acc) ~(ty : Value.t) (q : Quantity.t) (x : string)
    (dom : Value.t) (d : Value.closure) (a : Term.addr) (args : Term.t list) :
    (Eterm.ktm * acc, Error.t) result =
  let* point =
    Term.as_apt a
    |> Option.map (fun ((_q : Quantity.t), (p : Term.t)) -> p)
    |> Option.to_result ~none:(Error.Mismatch "a pair takes a point address")
  in
  let* fibre =
    Rules.one_of args |> Option.to_result ~none:(Error.Mismatch "a pair takes one fibre")
  in
  let* keep1 = point_runtime ec q dom in
  let* ec', cod = under_point ec x q dom d in
  let* keep2 = runtime_ty ec' cod in
  let* point_v = Eval.eval (globals_of ec) (env_of ec) point in
  let* fibre_ty = Rules.open_closure (Eval.ev (globals_of ec)) d [ point_v ] in
  let jobs =
    (if keep1 then [ (Some dom, point) ] else [])
    @ if keep2 then [ (Some fibre_ty, fibre) ] else []
  in
  let* fields, ac1 = erase_fold ec ac jobs in
  if List.is_empty fields then Ok (Eterm.KErased, ac1)
  else
    let* tid = tid_of ec ty in
    Ok (Eterm.KStruct (tid, fields), ac1)

(** An injection keeps its leg number, because a case reads the same
    numbers, and drops a payload that is not runtime (SC-D13). *)
and tag_intro (ec : ectx) (ac : acc) ~(ty : Value.t) (n : int) (d : Value.closure)
    (a : Term.addr) (args : Term.t list) : (Eterm.ktm * acc, Error.t) result =
  let* k =
    Term.as_aleg a
    |> Option.to_result ~none:(Error.Mismatch "an injection takes a leg address")
  in
  let* tys = leg_types ec n d in
  let* lty =
    Rules.at k tys
    |> Option.to_result ~none:(Error.Mismatch "the leg address is outside the collection")
  in
  let* rt = runtime_ty ec lty in
  let* payload =
    Rules.one_of args
    |> Option.to_result ~none:(Error.Mismatch "an injection takes one payload")
  in
  let* fields, ac1 = erase_fold ec ac (if rt then [ (Some lty, payload) ] else []) in
  let* tid = tid_of ec ty in
  Ok (Eterm.KTag (tid, k, fields), ac1)

(** M1 Stage J, brief 3.1 and the row of M1-PLAN.md:103.  A constructor
    of a mu family becomes [KTag] of the family tid, the constructor
    index in declaration order and the erased runtime fields.  A
    constructor with no runtime field carries no payload, which is
    exactly the tagged integer [tag_intro] above already writes for a
    payload-free leg (SD-D5).  The index arguments of the type are never
    read here, so two constructors that differ only in indices give one
    tid and one tag (A2, SJ-D4, M1-PLAN.md:105). *)
and mu_intro (ec : ectx) (ac : acc) ~(ty : Value.t) (a : Term.addr)
    (args : Term.t list) : (Eterm.ktm * acc, Error.t) result =
  let* w = Eval.whnf (globals_of ec) ty in
  match form_of w with
  | FLan (sv, d) ->
      let* n, _ixv =
        Rules.as_vmu sv
        |> Option.to_result
             ~none:(Error.Mismatch "an introduction at a shape past M0")
      in
      mu_tag ec ac n d a args
  | FRan (_, _) | FUniv | FNat | FOther ->
      Error
        (Error.Mismatch "an introduction stands at a type that is not a left former")

(** The tag itself, once the family is known.  The rec group of the
    declaration gains the leg names of the family, so the group a link
    step reads names every constructor and not the one built here
    (SJ-D21). *)
and mu_tag (ec : ectx) (ac : acc) (n : string) (d : Value.closure)
    (a : Term.addr) (args : Term.t list) : (Eterm.ktm * acc, Error.t) result =
  let* c =
    Term.as_actor a
    |> Option.to_result
         ~none:(Error.Mismatch "a constructor takes a constructor address")
  in
  let* fam = Rules.mu_family Check.ops ec.c n in
  let* names = Rules.mu_ctor_names n fam in
  let* k =
    position c names
    |> Option.to_result
         ~none:(Error.Unbound (c ^ " is not a constructor of " ^ n))
  in
  let* ct =
    Positivity.ctor_of c fam
    |> Option.to_result
         ~none:(Error.Unbound (c ^ " is not a constructor of " ^ n))
  in
  let* penv = Rules.mu_param_env Check.ops ec.c d in
  let* layout = mu_layout ec fam ct in
  let* fields, ac1 = mu_fields ec ac penv ct.Positivity.c_args args layout in
  let* group = mu_group_tids ec n fam in
  Ok (Eterm.KTag (mu_tid n, k, fields), { ac1 with groups = ac1.groups @ group })

(** Payload slots follow the declaration layout.  Actual field types
    still guide erasure.  When a generic slot is instantiated at an
    erased type, KErased supplies its placeholder so subsequent fields
    and branch binders keep their positions. *)
and mu_fields (ec : ectx) (ac : acc) (env : Value.t list)
    (tele : Positivity.telescope) (args : Term.t list)
    (layout : Eterm.repr option list) :
    (Eterm.ktm list * acc, Error.t) result =
  match (tele, args, layout) with
  | [], [], [] -> Ok ([], ac)
  | ((_q : Quantity.t), (_x : string), (ty : Term.t)) :: tele',
    arg :: args', field :: layout' ->
      let* tyv = Eval.eval (globals_of ec) env ty in
      let* here, ac1 =
        if Option.is_some field then
          let* f, a1 = term ec ac ~tail:false ~expected:(Some tyv) arg in
          Ok ([ f ], a1)
        else Ok ([], ac)
      in
      let* v = Eval.eval (globals_of ec) (env_of ec) arg in
      let* more, ac2 = mu_fields ec ac1 (v :: env) tele' args' layout' in
      Ok (here @ more, ac2)
  | _tele, _args, _layout -> Error (Error.Mismatch branch_arity_word)

(** Brief 3.1 and the row of M1-PLAN.md:104.  An elimination at a family
    becomes [KCase] over the same dispatch [case_elim] below writes, with
    one branch per constructor in declaration order, so the tag a branch
    answers is the tag [mu_tag] wrote.  The motive is a type and is
    dropped (SC-D10).  The tail flag reaches the branch bodies unchanged,
    so a branch body that IS the recursive call becomes [KTail] at
    [app_arm] above and this row writes no guard of its own (A10,
    M1-PLAN.md:106). *)
and mu_elim (ec : ectx) (ac : acc) ~(tail : bool) (e : Term.elim) :
    (Eterm.ktm * acc, Error.t) result =
  let* sty = Check.infer ec.c Quantity.Many e.Term.e_scrut in
  let* w = Eval.whnf (globals_of ec) sty in
  match form_of w with
  | FLan (sv, d) ->
      let* n, ixv =
        Rules.as_vmu sv
        |> Option.to_result
             ~none:(Error.Mismatch "an elimination at a shape past M0")
      in
      mu_case ec ac ~tail ~sty e n ixv d
  | FRan (_, _) | FUniv | FNat | FOther ->
      Error
        (Error.Mismatch
           "an elimination stands on a value that is not a left former")

(** The case itself, once the family is known. *)
and mu_case (ec : ectx) (ac : acc) ~(tail : bool) ~(sty : Value.t)
    (e : Term.elim) (n : string) (ixv : Value.t list) (d : Value.closure) :
    (Eterm.ktm * acc, Error.t) result =
  let* fam = Rules.mu_family Check.ops ec.c n in
  let* mo = Rules.mu_motive_of n fam ixv e in
  let* names = Rules.mu_ctor_names n fam in
  let* penv = Rules.mu_param_env Check.ops ec.c d in
  let* scrut, ac1 = term ec ac ~tail:false ~expected:(Some sty) e.Term.e_scrut in
  let* brs, ac2 =
    List.fold_left
      (fun (r : (Eterm.kbranch list * acc, Error.t) result)
           (((k : int), (c : string)) : int * string) ->
        let* bs, a = r in
        let* b, a' = mu_branch_of ec a ~tail n fam mo penv e.Term.e_branches k c in
        Ok (bs @ [ b ], a'))
      (Ok ([], ac1))
      (List.mapi (fun (k : int) (c : string) -> (k, c)) names)
  in
  let* group = mu_group_tids ec n fam in
  Ok
    ( Eterm.KCase (mu_tid n, scrut, brs),
      { ac2 with groups = ac2.groups @ group } )

(** One branch:  the leg its constructor address names, its binders at
    the marks the field record carries, and its body at the type the
    motive gives that constructor, which is the rule the checker uses
    (rules.ml [mu_branch], SH-D7 and SH-D9).  The arity counts the
    runtime fields alone, so a field at quantity Zero binds no runtime
    binder and the last runtime field is the innermost one. *)
and mu_branch_of (ec : ectx) (ac : acc) ~(tail : bool) (n : string)
    (fam : Positivity.family) (mo : Term.motive) (penv : Value.t list)
    (branches : (Term.addr * Term.leg) list) (k : int) (c : string) :
    (Eterm.kbranch * acc, Error.t) result =
  let* ct =
    Positivity.ctor_of c fam
    |> Option.to_result
         ~none:(Error.Unbound (c ^ " is not a constructor of " ^ n))
  in
  let* _key, lg =
    List.find_opt
      (fun ((a : Term.addr), (_l : Term.leg)) ->
        Option.equal String.equal (Term.as_actor a) (Some c))
      branches
    |> Option.to_result
         ~none:
           (Error.Missing_branch
              (Printf.sprintf "the elimination of %s has no branch at %s" n c))
  in
  let* layout = mu_layout ec fam ct in
  let* ec', env, vals, arity =
    mu_binders ec (penv, [], 0) ct.Positivity.c_args lg.Term.l_binders layout
  in
  let* idx =
    Rules.all_ok
      (List.map
         (fun (r : Term.t) -> Eval.eval (globals_of ec) env r)
         ct.Positivity.c_res_idx)
  in
  let self = Value.VIn (Shape.SMu (n, idx), Value.VACtor c, List.rev vals) in
  let* target = Rules.mu_result Check.ops ec.c mo idx self in
  let* body, ac1 = term ec' ac ~tail ~expected:(Some target) lg.Term.l_body in
  Ok ({ Eterm.tag = k; arity; body }, ac1)

(** The binders of one branch:  one kernel binder per field, in
    declaration order, at the field's own mark, and a runtime slot for
    the fields that survive.  The environment and the value list mirror
    the checker's fold, so the erased body reads the indices the checker
    bound (rules.ml [mu_branch]). *)
and mu_binders (ec : ectx) (st : Value.t list * Value.t list * int)
    (tele : Positivity.telescope) (binders : (Quantity.t * string) list)
    (layout : Eterm.repr option list) :
    (ectx * Value.t list * Value.t list * int, Error.t) result =
  let env, vals, arity = st in
  match (tele, binders, layout) with
  | [], [], [] -> Ok (ec, env, vals, arity)
  | ( ((q : Quantity.t), (_x : string), (ty : Term.t)) :: tele',
      ((_bq : Quantity.t), (bx : string)) :: binders', field :: layout' ) ->
      let* tyv = Eval.eval (globals_of ec) env ty in
      let keep = Option.is_some field in
      let v = Value.var (size_of ec) in
      let ec' =
        {
          ec with
          c = Check.bind bx q tyv ec.c;
          slots = (if keep then SKeep else SDrop) :: ec.slots;
        }
      in
      mu_binders ec'
        (v :: env, v :: vals, (if keep then arity + 1 else arity))
        tele' binders' layout'
  | _tele, _binders, _layout -> Error (Error.Missing_branch branch_arity_word)

and out_arm (ec : ectx) (ac : acc) ~(tail : bool) ~(ty : Value.t)
    (s : Term.t Shape.t) (a : Term.addr) (head : Term.t) (t : Term.t) :
    (Eterm.ktm * acc, Error.t) result =
  match s with
  | Shape.SPi (_, _, _) -> app_arm ec ac ~tail ~ty t
  | Shape.SColl n -> proj_arm ec ac n a head
  | Shape.SPar (_, _) -> refused s
  | Shape.SMu (_, _) -> Error (Error.Not_yet Rules.mu_ran_word)
  | Shape.SNu (_, _) -> refused s

(** An empty erased application preserves its head when source
    parameters remain, including parameters that themselves erase.
    Only a fully applied source function invokes a nullary closure. *)
and function_result (ec : ectx) (ty : Value.t) : (bool, Error.t) result =
  let* w = Eval.whnf (globals_of ec) ty in
  match form_of w with
  | FRan (s, _d) -> Ok (Option.is_some (Rules.as_vpi s))
  | FLan (_, _) | FUniv | FNat | FOther -> Ok false

(** The whole spine is erased at once, so an argument that is erased
    leaves no hole.  A call with no runtime argument preserves the head
    while source parameters remain; otherwise it invokes the nullary
    function.  The result type, rather than the head's runtime arity,
    distinguishes those cases. Quantities and domains come from the
    checked function type, never from the shape or APt annotations. *)
and app_arm (ec : ectx) (ac : acc) ~(tail : bool) ~(ty : Value.t) (t : Term.t) :
    (Eterm.ktm * acc, Error.t) result =
  let head, args = spine t [] in
  match args with
  | [] -> Error (Error.Mismatch "an application at a point shape with no point address")
  | _ :: _ ->
      let* head_ty = Check.infer ec.c Quantity.Many head in
      let* jobs, _result_ty =
        List.fold_left
          (fun (r : ((Value.t option * Term.t) list * Value.t, Error.t) result)
               ((_qa : Quantity.t), (_dom : Term.t), (arg : Term.t)) ->
            let* js, fn_ty = r in
            let* w = Eval.whnf (globals_of ec) fn_ty in
            let bad = Error (Error.Mismatch "an application needs a point function type") in
            let* q, dom_v, d =
              match form_of w with
              | FRan (s, d) -> (match point_of s with
                  | PPoint (q, _x, dom_v) -> Ok (q, dom_v, d)
                  | PColl _ | POther -> bad)
              | FLan (_, _) | FUniv | FNat | FOther -> bad in
            let* keep = point_runtime ec q dom_v in
            let* av = Eval.eval (globals_of ec) (env_of ec) arg in
            let* result_ty = Rules.open_closure (Eval.ev (globals_of ec)) d [ av ] in
            Ok ((if keep then js @ [ (Some dom_v, arg) ] else js), result_ty))
          (Ok ([], head_ty)) args
      in
      let* head', ac1 = term ec ac ~tail:false ~expected:(Some head_ty) head in
      let* args', ac2 = erase_fold ec ac1 jobs in
      let* bare =
        if List.is_empty args' then
          function_result ec ty
        else Ok false
      in
      (match () with
      | () when bare -> Ok (head', ac2)
      | () when tail -> Ok (Eterm.KTail (head', args'), ac2)
      | () -> Ok (Eterm.KApp (head', args'), ac2))

(** A projection renumbers its leg, because the erased tuple holds the
    runtime legs alone (SC-D11). *)
and proj_arm (ec : ectx) (ac : acc) (n : int) (a : Term.addr) (head : Term.t) :
    (Eterm.ktm * acc, Error.t) result =
  let* k =
    Term.as_aleg a
    |> Option.to_result ~none:(Error.Mismatch "a projection takes a leg address")
  in
  let* sty = Check.infer ec.c Quantity.Many head in
  let* w = Eval.whnf (globals_of ec) sty in
  match form_of w with
  | FRan (_sv, d) ->
      let* flags = leg_flags ec n d in
      let before =
        List.length
          (List.filter Fun.id (List.filteri (fun (i : int) (_f : bool) -> i < k) flags))
      in
      let* scrut, ac1 = term ec ac ~tail:false ~expected:(Some sty) head in
      let* tid = tid_of ec sty in
      Ok (Eterm.KProj (tid, before, scrut), ac1)
  | FLan (_, _) | FUniv | FNat | FOther ->
      Error (Error.Mismatch "a projection stands on a value that is not a right former")

and elim_arm (ec : ectx) (ac : acc) ~(tail : bool) ~(ty : Value.t) (e : Term.elim) :
    (Eterm.ktm * acc, Error.t) result =
  match e.Term.e_shape with
  | Shape.SPar (_, _) -> refused e.Term.e_shape
  | Shape.SMu (_, _) -> mu_elim ec ac ~tail e
  | Shape.SNu (_, _) -> refused e.Term.e_shape
  | Shape.SPi (_, _, _) -> elim_typed ec ac ~tail ~ty e
  | Shape.SColl _ -> elim_typed ec ac ~tail ~ty e

(** The motive is a type and is dropped at every elimination (SC-D10). *)
and elim_typed (ec : ectx) (ac : acc) ~(tail : bool) ~(ty : Value.t) (e : Term.elim) :
    (Eterm.ktm * acc, Error.t) result =
  let* sty = Check.infer ec.c Quantity.Many e.Term.e_scrut in
  let* w = Eval.whnf (globals_of ec) sty in
  match form_of w with
  | FLan (sv, d) -> (
      match point_of sv with
      | PPoint (q, x, dom) -> pair_elim ec ac ~tail ~ty ~sty e q x dom d
      | PColl n -> case_elim ec ac ~tail ~ty ~sty e n d
      | POther -> Error (Error.Mismatch "an elimination at a shape past M0"))
  | FRan (_, _) | FUniv | FNat | FOther ->
      Error (Error.Mismatch "an elimination stands on a value that is not a left former")

(** The pair elimination becomes a let of the scrutinee and one let per
    runtime component, so the scrutinee is evaluated once (SC-D24).  The
    synthetic scrutinee binder holds a slot no kernel index names. *)
and pair_elim (ec : ectx) (ac : acc) ~(tail : bool) ~(ty : Value.t) ~(sty : Value.t)
    (e : Term.elim) (q : Quantity.t) (x : string) (dom : Value.t) (d : Value.closure) :
    (Eterm.ktm * acc, Error.t) result =
  let* _key, lg =
    Rules.one_of e.Term.e_branches
    |> Option.to_result ~none:(Error.Mismatch "a pair elimination takes one branch")
  in
  let* b1, b2 =
    Rules.two_of lg.Term.l_binders
    |> Option.to_result ~none:(Error.Mismatch "a pair branch takes two binders")
  in
  let _ = b1 in
  let _ = b2 in
  let* keep1 = point_runtime ec q dom in
  let* cod =
    Rules.open_closure (Eval.ev (globals_of ec)) d [ Value.var (size_of ec) ]
  in
  let ec1 =
    {
      ec with
      c = Check.bind x q dom ec.c;
      slots = (if keep1 then SKeep else SDrop) :: SExtra :: ec.slots;
    }
  in
  let* keep2 = runtime_ty ec1 cod in
  let x2 = snd b2 in
  let ec2 =
    {
      ec1 with
      c = Check.bind x2 Quantity.Many cod ec1.c;
      slots = (if keep2 then SKeep else SDrop) :: ec1.slots;
    }
  in
  let* scrut, ac1 = term ec ac ~tail:false ~expected:(Some sty) e.Term.e_scrut in
  let* sv = Rules.map_shape (Eval.eval (globals_of ec) (env_of ec)) e.Term.e_shape in
  let self =
    Value.VIn
      (sv, Value.VAPt (q, Value.var (size_of ec)), [ Value.var (size_of ec + 1) ])
  in
  let* target = Rules.elim_result Check.ops ec.c e.Term.e_motive (Some ty) self in
  let* body, ac2 = term ec2 ac1 ~tail ~expected:(Some target) lg.Term.l_body in
  let* tid = tid_of ec sty in
  let d2 = if keep1 then 1 else 0 in
  let inner2 =
    if keep2 then
      Eterm.KLet (x2, Eterm.KProj (tid, d2, Eterm.KVar d2), body)
    else body
  in
  let inner1 =
    if keep1 then Eterm.KLet (x, Eterm.KProj (tid, 0, Eterm.KVar 0), inner2) else inner2
  in
  Ok (Eterm.KLet (scrut_name, scrut, inner1), ac2)

(** A case keeps every leg of the collection, in leg order, so the tag a
    branch answers is the tag the injection wrote (SC-D13).  A collection
    of width zero has no branch and no leg, and its case is a case with an
    empty branch list. *)
and case_elim (ec : ectx) (ac : acc) ~(tail : bool) ~(ty : Value.t) ~(sty : Value.t)
    (e : Term.elim) (n : int) (d : Value.closure) : (Eterm.ktm * acc, Error.t) result =
  let* scrut, ac1 = term ec ac ~tail:false ~expected:(Some sty) e.Term.e_scrut in
  let* tys = leg_types ec n d in
  let* brs, ac2 =
    List.fold_left
      (fun (r : (Eterm.kbranch list * acc, Error.t) result) (k : int) ->
        let* bs, a = r in
        let* b, a' = branch_of ec a ~tail ~ty tys e k in
        Ok (bs @ [ b ], a'))
      (Ok ([], ac1)) (List.init n Fun.id)
  in
  let* tid = tid_of ec sty in
  Ok (Eterm.KCase (tid, scrut, brs), ac2)

and branch_of (ec : ectx) (ac : acc) ~(tail : bool) ~(ty : Value.t) (tys : Value.t list)
    (e : Term.elim) (k : int) : (Eterm.kbranch * acc, Error.t) result =
  let* lty =
    Rules.at k tys
    |> Option.to_result ~none:(Error.Mismatch "a leg number is outside the collection")
  in
  let* _a, lg =
    List.find_opt
      (fun ((a : Term.addr), (_lg : Term.leg)) ->
        Option.equal Int.equal (Term.as_aleg a) (Some k))
      e.Term.e_branches
    |> Option.to_result ~none:(Error.Mismatch "a case is missing a branch")
  in
  let* bq, bx =
    Rules.one_of lg.Term.l_binders
    |> Option.to_result ~none:(Error.Mismatch "a case branch takes one binder")
  in
  let* keep = point_runtime ec bq lty in
  let ec' =
    {
      ec with
      c = Check.bind bx bq lty ec.c;
      slots = (if keep then SKeep else SDrop) :: ec.slots;
    }
  in
  let self =
    Value.VIn (Shape.SColl (List.length tys), Value.VALeg k, [ Value.var (size_of ec) ])
  in
  let* target = Rules.elim_result Check.ops ec.c e.Term.e_motive (Some ty) self in
  let* body, ac1 = term ec' ac ~tail ~expected:(Some target) lg.Term.l_body in
  Ok ({ Eterm.tag = k; arity = (if keep then 1 else 0); body }, ac1)

(** Retain the checker's let definition for dependent types in the body.
    Its semantic value is used only by the checking context.  A runtime
    let still emits its original definition and binds a runtime slot;
    types and proofs only extend the checking context. *)
and let_arm (ec : ectx) (ac : acc) ~(tail : bool) ~(ty : Value.t) (x : string)
    (lty : Term.t) (v : Term.t) (body : Term.t) : (Eterm.ktm * acc, Error.t) result =
  let* lty_v = Eval.eval (globals_of ec) (env_of ec) lty in
  let* rt = runtime_ty ec lty_v in
  let* vv = Eval.eval (globals_of ec) (env_of ec) v in
  let ec' =
    {
      ec with
      c = Check.define x Quantity.Many lty_v vv ec.c;
      slots = (if rt then SKeep else SDrop) :: ec.slots;
    }
  in
  if rt then
    let* v', ac1 = term ec ac ~tail:false ~expected:(Some lty_v) v in
    let* b', ac2 = term ec' ac1 ~tail ~expected:(Some ty) body in
    Ok (Eterm.KLet (x, v', b'), ac2)
  else term ec' ac ~tail ~expected:(Some ty) body

(** The type names a declaration mentions, deduplicated by their printed
    text and in first mention order.  The group heads the declaration so
    that link.ml reads every type it must lay out before it reads the
    functions that use them (SC-D33). *)
let rec tids_ktm (t : Eterm.ktm) : Eterm.tid list =
  match t with
  | Eterm.KVar _ -> []
  | Eterm.KLit _ -> []
  | Eterm.KGlobal _ -> []
  | Eterm.KErased -> []
  | Eterm.KLet (_x, v, b) -> tids_ktm v @ tids_ktm b
  | Eterm.KClos (_f, _n, cs) -> List.concat_map tids_ktm cs
  | Eterm.KApp (f, xs) -> tids_ktm f @ List.concat_map tids_ktm xs
  | Eterm.KTail (f, xs) -> tids_ktm f @ List.concat_map tids_ktm xs
  | Eterm.KStruct (t0, xs) -> t0 :: List.concat_map tids_ktm xs
  | Eterm.KProj (t0, _k, x) -> t0 :: tids_ktm x
  | Eterm.KTag (t0, _k, xs) -> t0 :: List.concat_map tids_ktm xs
  | Eterm.KCase (tid, x, brs) ->
      tid :: tids_ktm x
      @ List.concat_map (fun (b : Eterm.kbranch) -> tids_ktm b.Eterm.body) brs
  | Eterm.KDelay (_f, xs) -> List.concat_map tids_ktm xs
  | Eterm.KForce x -> tids_ktm x

let tids_repr (r : Eterm.repr) : Eterm.tid list =
  match r with
  | Eterm.RI31 -> []
  | Eterm.RStruct t -> [ t ]
  | Eterm.RUnion t -> [ t ]
  | Eterm.RFunc t -> [ t ]
  | Eterm.RThunk t -> [ t ]

let tids_decl (d : Eterm.kdecl) : Eterm.tid list =
  match d with
  | Eterm.KFun (_f, ps, ret, b) ->
      List.concat_map tids_repr ps @ tids_repr ret @ tids_ktm b
  | Eterm.KRec ts -> ts

let dedup_tids (ts : Eterm.tid list) : Eterm.tid list =
  List.fold_left
    (fun (acc : Eterm.tid list) (t : Eterm.tid) ->
      if
        List.exists
          (fun (u : Eterm.tid) -> String.equal (Eterm.tid_text u) (Eterm.tid_text t))
          acc
      then acc
      else acc @ [ t ])
    [] ts

(** One checked declaration.  A prim is dropped, because its body is the
    runtime's own (SC-D18);  an axiom at a runtime type keeps its repr, so
    the emitter can refuse a program that reaches one; a definition at a
    runtime type erases to its rec group, the functions its lambdas lifted
    and its own function, in that order (SC-D29). *)
let rec decl (g : Global.t) (budget : Budget.t) (name : string) (en : Global.entry) :
    (entry, Error.t) result =
  let ec = { c = Check.make g budget; slots = []; self = name } in
  match en with
  | Global.Prim _ -> Ok Dropped
  | Global.Axiom a ->
      let* ty_v = Eval.eval g [] a.Global.ax_ty in
      let* rt = runtime_ty ec ty_v in
      if rt then Result.map (fun (r : Eterm.repr) -> Postulate r) (repr_of ec ty_v)
      else Ok Dropped
  | Global.Def d ->
      let* ty_v = Eval.eval g [] d.Global.ty in
      let* rt = runtime_ty ec ty_v in
      if rt then def_code ec name ty_v d.Global.def else Ok Dropped

(** The whole type chain supplies the definition's own parameters,
    whether the body is a lambda chain, an alias or a partial application.
    A definition of arity two is one function of two parameters. *)
and def_code (ec : ectx) (name : string) (ty_v : Value.t) (body : Term.t) :
    (entry, Error.t) result =
  let* params, ret, body', ac =
    chain ec { next = 0; lifted = []; groups = [] } [] ~ty:ty_v body
  in
  let own = Eterm.KFun (Eterm.Fid name, params, ret, body') in
  let ds = ac.lifted @ [ own ] in
  Ok
    (Code
       (Eterm.KRec (dedup_tids (List.concat_map tids_decl ds @ ac.groups)) :: ds))

(** The whole program, in declaration order.  Every row extends the
    environment the next row is erased in, exactly as check_decls built
    it, so a definition reads the types of the definitions before it. *)
let program ?(budget : Budget.t = Budget.unlimited) (globals : Global.t)
    (rows : (string * Global.entry) list) : ((string * entry) list, Error.t) result =
  List.fold_left
    (fun (r : (Global.t * (string * entry) list, Error.t) result)
         ((name : string), (en : Global.entry)) ->
      let* g, out = r in
      let* e = decl g budget name en in
      Ok (Global.add name en g, out @ [ (name, e) ]))
    (Ok (globals, []))
    rows
  |> Result.map (fun ((_g : Global.t), (out : (string * entry) list)) -> out)

(** The printed form of SC-D2:  one line per erased declaration, one line
    per kernel declaration of a definition, and the name alone for a
    declaration that carries nothing at runtime. *)
let print (rows : (string * entry) list) : string =
  String.concat ""
    (List.map
       (fun ((name : string), (e : entry)) ->
         match e with
         | Dropped -> Printf.sprintf "erased %s\n" name
         | Postulate r -> Printf.sprintf "axiom %s : %s\n" name (Eterm.print_repr r)
         | Code ds ->
             String.concat ""
               (List.map (fun (d : Eterm.kdecl) -> Eterm.print_decl d ^ "\n") ds))
       rows)
