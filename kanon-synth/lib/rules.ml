(** The single dispatch point, plan section 5.  [rules] answers one
    question, "what are the four schema rules of this shape", and every
    other kernel file asks it rather than reading a shape name.  This
    file, shape.ml and pp.ml are the only three in lib/ that spell a
    shape name, which is what the R0-AUDIT gate leg measures.

    Every match on a shape below has five arms, so a sixth shape is a
    compile error here before it is a silent fallthrough anywhere.

    Two departures from the plan's pack, each a Stage B decision.
    SB-D6:  [form_lan] and [form_ran] take [expected:Level.t option], so
    the empty collection reads its universe from an annotation.  SB-D18:
    the pack carries the descriptive [eta] row that spec_count.ml prints
    AND the two expansion functions that conv.ml applies, because conv
    must apply a row without naming the shape it belongs to. *)

let ( let* ) = Result.bind

(** The milestone words of the three shapes M0 does not admit. *)
let spar_word : string = "SPar arrives at M1"

let smu_word : string = "SMu arrives at M1"
let snu_word : string = "SNu arrives at M2"
let auto_word : string = "instances arrive at M2"

(** What a rule may ask of the evaluator.  [Eval] builds one of these
    from its own [eval] and hands it to [beta], so the pack reduces a
    redex without depending on eval.ml. *)
type evaluator = { ev_eval : Value.t list -> Term.t -> (Value.t, Error.t) result }

(** Open a closure over its binders.  The binder list is outermost
    first, so the arguments are consed innermost last. *)
let open_closure (ev : evaluator) (clo : Value.closure) (args : Value.t list) :
    (Value.t, Error.t) result =
  ev.ev_eval (List.rev_append args clo.Value.env) clo.Value.body

(** What a rule may ask of the checker.  The context is abstract, so
    rules.ml never depends on check.ml and the two are not a cycle
    (SB-D12: lib/ holds no cell of state). *)
type 'c ops = {
  o_infer : 'c -> Quantity.t -> Term.t -> (Value.t * Quantity.usage, Error.t) result;
  o_check : 'c -> Quantity.t -> Term.t -> Value.t -> (Quantity.usage, Error.t) result;
  o_close : 'c -> int -> Quantity.t -> Quantity.usage -> (Quantity.usage, Error.t) result;
  o_infer_univ : 'c -> Term.t -> (Level.t, Error.t) result;
  o_conv : 'c -> ty:Value.t -> Value.t -> Value.t -> (bool, Error.t) result;
  o_conv_type : 'c -> Value.t -> Value.t -> (bool, Error.t) result;
  o_eval : 'c -> Term.t -> (Value.t, Error.t) result;
  o_whnf : 'c -> Value.t -> (Value.t, Error.t) result;
  o_bind : string -> Quantity.t -> Value.t -> 'c -> 'c;
  o_size : 'c -> int;
  o_env : 'c -> Value.t list;
  o_ev : 'c -> evaluator;
  o_pp : 'c -> Value.t -> string;
  o_quote : 'c -> Value.t -> (Term.t, Error.t) result;
      (** readback, so a rule and conversion can ask the checker for the
          type of a type without holding the global environment *)
  o_head_ty : 'c -> Value.head -> (Value.t, Error.t) result;
      (** the type the context or the global environment gives a neutral
          head, so conversion can walk a spine at a type (SB-D25) *)
  o_family : 'c -> string -> Positivity.family option;
      (** M1 Stage G, brief 3.3:  the ONE accessor the mu pack reads a
          family record through (SG-D2).  A second reader would put a
          family lookup in check.ml and the R0-AUDIT leg forbids it
          (dev/r0-audit.sh:6-11). *)
}

(** The derived eta table of SPEC.md section 4:  a former gets a row
    when its shape has one introduction address and the structural
    expansion ends. *)
type eta_row = {
  eta_ran : bool;
  eta_lan : bool;
}

(** A redex the evaluator hands to [beta].  [BOut] is an elimination at
    the right former, [BElim] one at the left former;  the term-level
    branches ride with the environment they close over. *)
type beta_redex =
  | BOut of Value.t Shape.t * Value.vaddr * Value.t
  | BElim of Value.t Shape.t * (Term.addr * Term.leg) list * Value.t list * Value.t

(** One eta row applied:  the shape, the diagram closure and the two
    values to compare. *)
type 'c expansion =
  'c ops ->
  'c ->
  Value.t Shape.t ->
  Value.closure ->
  Value.t ->
  Value.t ->
  (bool, Error.t) result

type 'c rule_pack = {
  form_lan :
    'c ops -> 'c -> Term.t Shape.t -> Term.t -> expected:Level.t option ->
    (Level.t, Error.t) result;
  form_ran :
    'c ops -> 'c -> Term.t Shape.t -> Term.t -> expected:Level.t option ->
    (Level.t, Error.t) result;
  intro_in :
    'c ops -> 'c -> Quantity.t -> Term.t Shape.t -> Term.addr -> Term.t list ->
    expected:Value.t -> (Quantity.usage, Error.t) result;
  elim_elim :
    'c ops -> 'c -> Quantity.t -> Term.elim -> expected:Value.t option ->
    (Value.t * Quantity.usage, Error.t) result;
  intro_sec :
    'c ops -> 'c -> Quantity.t -> Term.t Shape.t -> Term.leg list -> expected:Value.t ->
    (Quantity.usage, Error.t) result;
  elim_out :
    'c ops -> 'c -> Quantity.t -> Term.t Shape.t -> Term.addr -> Term.t ->
    (Value.t * Quantity.usage, Error.t) result;
  beta : evaluator -> beta_redex -> (Value.t option, Error.t) result;
  eta : eta_row;
  diagram_arity : Value.t Shape.t -> int;
  spine_ty :
    'c ops ->
    'c ->
    Value.t Shape.t ->
    Value.closure ->
    Value.vaddr ->
    ((Value.t option * Value.t) option, Error.t) result;
      (** one step of a neutral spine at the right former:  the type of
          the address argument, when the address carries one, and the
          type the head has after the step.  [Ok None] means the address
          does not fit the shape, and conversion then falls back to a
          structural comparison (SB-D25). *)
  expand_ran : 'c expansion option;
  expand_lan : 'c expansion option;
  conv_diagram :
    'c ops -> 'c -> Value.t Shape.t -> Value.closure -> Value.closure ->
    (bool, Error.t) result;
  ann_lvl_eq : Value.t Shape.t -> Level.t option -> Level.t option -> bool;
  lan_lvl : 'c ops -> 'c -> Value.t Shape.t -> Level.t list -> (Level.t, Error.t) result;
  ran_lvl : 'c ops -> 'c -> Value.t Shape.t -> Level.t list -> (Level.t, Error.t) result;
      (** SG-D15:  the two level fields take the shape and the checker
          ops, and they answer a result.  The mu shape needs both:  its
          left former lives at the level the family record declares,
          which is not a function of the payload levels (brief 3.5), and
          its right former answers the M2 word, which no [Level.t]
          can carry (SG-D4). *)
  subsingleton : 'c ops -> 'c -> Value.t Shape.t -> (bool, Error.t) result;
      (** M1 Stage H, brief 3.5 and SH-D1:  the subsingleton criterion of
          brief 3.4, read through the pack.  Step one of conv.ml applies
          it as named rule 2, so no shape name and no family lookup
          enters conv.ml (dev/r0-audit.sh:6-11).  A shape that carries no
          criterion answers [Ok false] and the comparison goes on. *)
}

(** The framework axiom of R-Q6, SPEC.md section 6:  [imax l zero] is
    [zero], and it is what gives the proposition universe its
    impredicativity.  It lives here rather than in the carried level.ml
    (SB-D6). *)
(* SB-M3 site *)
let imax (l : Level.t) (l' : Level.t) : Level.t =
  if Level.equal l' Level.zero then Level.zero else Level.max l l'

let max_of (ls : Level.t list) : Level.t = List.fold_left Level.max Level.zero ls

(** A total read of a two-element list, so [ran_lvl] never indexes. *)
let level_pair (ls : Level.t list) : (Level.t * Level.t) option =
  match ls with
  | [ l; l' ] -> Some (l, l')
  | [] -> None
  | [ _ ] -> None
  | _ :: _ :: _ :: _ -> None

let one_of (xs : 'a list) : 'a option =
  match xs with
  | [ x ] -> Some x
  | [] -> None
  | _ :: _ :: _ -> None

let two_of (xs : 'a list) : ('a * 'a) option =
  match xs with
  | [ x; y ] -> Some (x, y)
  | [] -> None
  | [ _ ] -> None
  | _ :: _ :: _ :: _ -> None

(** Total indexing.  Plan section 11 bans every partial indexing
    is the one indexing combinator this file uses. *)
let rec at (n : int) (xs : 'a list) : 'a option =
  match xs with
  | [] -> None
  | x :: rest -> if Int.equal n 0 then Some x else at (n - 1) rest

let all_ok (xs : ('a, Error.t) result list) : ('a list, Error.t) result =
  List.fold_left
    (fun (acc : ('a list, Error.t) result) (x : ('a, Error.t) result) ->
      let* got = acc in
      let* v = x in
      Ok (got @ [ v ]))
    (Ok []) xs

(** Pairwise comparison of two shape payloads, [Ok false] when the
    lengths differ.  M1 Stage G:  two mu shapes are equal when the
    family name is the same and every index converts. *)
let rec payload_eq (eq : 'a -> 'a -> (bool, Error.t) result)
    (xs : 'a list) (ys : 'a list) : (bool, Error.t) result =
  match (xs, ys) with
  | [], [] -> Ok true
  | x :: xs', y :: ys' ->
      let* got = eq x y in
      if got then payload_eq eq xs' ys' else Ok false
  | [], _ :: _ -> Ok false
  | _ :: _, [] -> Ok false

(** Structural equality of two shapes over values, with the payload
    compared by the caller's conversion.  The two refused shapes carry
    their milestone word here too, so a shape that M1 does not admit can
    never be silently equal to itself. *)
let shape_eq (eq : Value.t -> Value.t -> (bool, Error.t) result) (a : Value.t Shape.t)
    (b : Value.t Shape.t) : (bool, Error.t) result =
  match (a, b) with
  | Shape.SPi (q1, _, d1), Shape.SPi (q2, _, d2) ->
      if Quantity.equal q1 q2 then eq d1 d2 else Ok false
  | Shape.SColl n1, Shape.SColl n2 -> Ok (Int.equal n1 n2)
  | Shape.SPar (_, _), Shape.SPar (_, _) -> Error (Error.Not_yet spar_word)
  (* M1 Stage G, brief 3.1:  the refusal this line carried is replaced
     by the structural row the pack needs. *)
  | Shape.SMu (n1, ix1), Shape.SMu (n2, ix2) ->
      if String.equal n1 n2 then payload_eq eq ix1 ix2 else Ok false
  | Shape.SNu (_, _), Shape.SNu (_, _) -> Error (Error.Not_yet snu_word)
  | Shape.SPi (_, _, _), (Shape.SColl _ | Shape.SPar (_, _) | Shape.SMu (_, _) | Shape.SNu (_, _))
    ->
      Ok false
  | Shape.SColl _, (Shape.SPi (_, _, _) | Shape.SPar (_, _) | Shape.SMu (_, _) | Shape.SNu (_, _))
    ->
      Ok false
  | Shape.SPar (_, _), (Shape.SPi (_, _, _) | Shape.SColl _ | Shape.SMu (_, _) | Shape.SNu (_, _))
    ->
      Ok false
  | Shape.SMu (_, _), (Shape.SPi (_, _, _) | Shape.SColl _ | Shape.SPar (_, _) | Shape.SNu (_, _))
    ->
      Ok false
  | Shape.SNu (_, _), (Shape.SPi (_, _, _) | Shape.SColl _ | Shape.SPar (_, _) | Shape.SMu (_, _))
    ->
      Ok false

(** Evaluate the payload a shape carries, so eval.ml turns a term shape
    into a value shape without naming one. *)
let map_shape (f : 'a -> ('b, Error.t) result) (s : 'a Shape.t) :
    ('b Shape.t, Error.t) result =
  match s with
  | Shape.SPi (q, x, dom) -> Result.map (fun v -> Shape.SPi (q, x, v)) (f dom)
  | Shape.SColl n -> Ok (Shape.SColl n)
  | Shape.SPar (_, _) -> Error (Error.Not_yet spar_word)
  (* M1 Stage G:  the index payload evaluates, so eval.ml turns a mu
     term shape into a mu value shape and still names no shape. *)
  | Shape.SMu (n, ix) ->
      Result.map (fun (vs : 'b list) -> Shape.SMu (n, vs)) (all_ok (List.map f ix))
  | Shape.SNu (_, _) -> Error (Error.Not_yet snu_word)

(** Term builders.  prim.ml and the driver need a closed type at the two
    admitted shapes and cannot spell one, so they ask here. *)

let arrow (q : Quantity.t) (x : string) (dom : Term.t) (cod : Term.t) : Term.t =
  Term.Ran (Shape.SPi (q, x, dom), cod)

let leg_of (body : Term.t) : Term.leg = { Term.l_binders = []; l_body = body }

let diagram_of (legs : Term.t list) : Term.t =
  Term.Sec (Shape.SColl (List.length legs), List.map leg_of legs)

let sum_ty (legs : Term.t list) : Term.t =
  Term.Lan (Shape.SColl (List.length legs), diagram_of legs)

let prod_ty (legs : Term.t list) : Term.t =
  Term.Ran (Shape.SColl (List.length legs), diagram_of legs)

(** The annotated empty product, the surface's [(prod () : Type n)]. *)
let unit_ty (l : Level.t) : Term.t = Term.Ann (prod_ty [], Term.Univ l)

let unit_val : Term.t = Term.Sec (Shape.SColl 0, [])

(** SB-D8:  the result type of the two comparisons.  [inj 0 of 2 ()] is
    false and [inj 1 of 2 ()] is true. *)
let bool_ty : Term.t = sum_ty [ unit_ty Level.one; unit_ty Level.one ]

let bool_value (b : bool) : Value.t =
  Value.VIn
    ( Shape.SColl 2,
      Value.VALeg (if b then 1 else 0),
      [ Value.VSec (Shape.SColl 0, []) ] )

(** Views on a shape, so a rule reads its own payload without a partial
    projection. *)

let as_vpi (s : 'a Shape.t) : (Quantity.t * string * 'a) option =
  match s with
  | Shape.SPi (q, x, dom) -> Some (q, x, dom)
  | Shape.SColl _ | Shape.SPar (_, _) | Shape.SMu (_, _) | Shape.SNu (_, _) -> None

let as_vcoll (s : 'a Shape.t) : int option =
  match s with
  | Shape.SColl n -> Some n
  | Shape.SPi (_, _, _) | Shape.SPar (_, _) | Shape.SMu (_, _) | Shape.SNu (_, _) -> None

let as_tsec (t : Term.t) : (Term.t Shape.t * Term.leg list) option =
  match t with
  | Term.Sec (s, legs) -> Some (s, legs)
  | Term.Var _ | Term.Univ _ | Term.Lan (_, _) | Term.Ran (_, _) | Term.In (_, _, _)
  | Term.Elim _ | Term.Out (_, _, _) | Term.Let (_, _, _, _) | Term.Ann (_, _)
  | Term.Global _ | Term.Lit _ | Term.Auto ->
      None

let rec zip (xs : 'a list) (ys : 'b list) : ('a * 'b) list option =
  match (xs, ys) with
  | [], [] -> Some []
  | x :: xr, y :: yr -> Option.map (fun (r : ('a * 'b) list) -> (x, y) :: r) (zip xr yr)
  | [], _ :: _ -> None
  | _ :: _, [] -> None

let wrong_pack : string = "the rule pack does not match the shape of the term"
let stuck_msg : string = "an elimination met a value it cannot eliminate"
let leg_msg : string = "the leg address is outside the collection"
let diagram_msg : string = "the diagram is not a section of the declared width"

(** All introduction and elimination rules inspect a former through the
    same weak-head check while preserving each rule's diagnostic. *)
let former_view (ops : 'c ops) (ctx : 'c) (view : Value.t -> 'a option)
    (message : string) (ty : Value.t) : (Value.t * 'a, Error.t) result =
  let* w = ops.o_whnf ctx ty in
  let* former = view w |> Option.to_result ~none:(Error.Mismatch message) in
  Ok (w, former)

let binder_quantity (subject : string) (source : string) (name : string)
    (marked : Quantity.t) (declared : Quantity.t) : (unit, Error.t) result =
  if Quantity.equal marked declared then Ok ()
  else
    Error (Error.Quantity
      (Printf.sprintf "the %s %s is marked %s and the %s marks it %s"
        subject name (Quantity.to_string marked) source (Quantity.to_string declared)))

let infer_scrutinee (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (e : Term.elim) =
  if not (Quantity.equal mode Quantity.Zero) && Quantity.equal e.Term.e_scrut_q Quantity.Zero then
    Error (Error.Quantity "an erased scrutinee cannot be eliminated at runtime")
  else ops.o_infer ctx (Quantity.mul mode e.Term.e_scrut_q) e.Term.e_scrut

(** A [let] binder for a partial view inside [beta]:  a view that does
    not match means the redex is stuck, and a stuck redex is [Ok None]. *)
let ( let@ ) (o : 'a option) (f : 'a -> (Value.t option, Error.t) result) :
    (Value.t option, Error.t) result =
  Option.fold ~none:(Ok None) ~some:f o

(** Apply an elimination at the right former to a value:  reduce it when
    the pack's [beta] fires, and freeze it on the spine when it does
    not. *)
let out_with (beta : evaluator -> beta_redex -> (Value.t option, Error.t) result)
    (ev : evaluator) (s : Value.t Shape.t) (addr : Value.vaddr) (v : Value.t) :
    (Value.t, Error.t) result =
  let* stepped = beta ev (BOut (s, addr, v)) in
  stepped
  |> Option.fold
       ~none:
         (Value.as_neutral v
         |> Option.fold
              ~none:(Error (Error.Mismatch stuck_msg))
              ~some:(fun ((h : Value.head), (sp : Value.spine list)) ->
                Ok (Value.VNeutral (h, Value.SOut (s, addr) :: sp))))
       ~some:(fun (x : Value.t) -> Ok x)

(** The same for an elimination at the left former. *)
let elim_with (beta : evaluator -> beta_redex -> (Value.t option, Error.t) result)
    (ev : evaluator) (s : Value.t Shape.t) (q : Quantity.t) (mo : Term.motive option)
    (branches : (Term.addr * Term.leg) list) (env : Value.t list) (v : Value.t) :
    (Value.t, Error.t) result =
  let* stepped = beta ev (BElim (s, branches, env, v)) in
  stepped
  |> Option.fold
       ~none:
         (Value.as_neutral v
         |> Option.fold
              ~none:(Error (Error.Mismatch stuck_msg))
              ~some:(fun ((h : Value.head), (sp : Value.spine list)) ->
                let frame =
                  Value.SElim
                    {
                      Value.s_shape = s;
                      s_scrut_q = q;
                      s_motive = mo;
                      s_branches = branches;
                      s_env = env;
                    }
                in
                Ok (Value.VNeutral (h, frame :: sp))))
       ~some:(fun (x : Value.t) -> Ok x)

(** The type an elimination returns:  the motive read at the value given,
    or the expected type standing in as the constant cocone (plan
    section 6). *)
let elim_result (ops : 'c ops) (ctx : 'c) (mo : Term.motive option)
    (expected : Value.t option) (self : Value.t) : (Value.t, Error.t) result =
  mo
  |> Option.fold
       ~none:
         (expected
         |> Option.to_result
              ~none:
                (Error.Cannot_infer
                   "an elimination without a motive needs an expected type"))
       ~some:(fun (m : Term.motive) ->
         (ops.o_ev ctx).ev_eval (self :: ops.o_env ctx) m.Term.m_body)

(** The motive is a type under the scrutinee, so a bad motive fails here
    and not at the first branch. *)
let check_motive (ops : 'c ops) (ctx : 'c) (mo : Term.motive option) (scrut_ty : Value.t)
    : (unit, Error.t) result =
  mo
  |> Option.fold ~none:(Ok ())
       ~some:(fun (m : Term.motive) ->
         let ctx' = ops.o_bind m.Term.m_self Quantity.Zero scrut_ty ctx in
         Result.map (fun (_ : Level.t) -> ()) (ops.o_infer_univ ctx' m.Term.m_body))

(* ---------------------------------------------------------------- *)
(* The pack of the point shape, plan section 5.                       *)
(* ---------------------------------------------------------------- *)

let spi_levels (ops : 'c ops) (ctx : 'c) (s : Term.t Shape.t) (diagram : Term.t) :
    (Level.t list, Error.t) result =
  as_vpi s
  |> Option.to_result ~none:(Error.Mismatch wrong_pack)
  |> Fun.flip Result.bind (fun ((q : Quantity.t), (x : string), (dom : Term.t)) ->
         let* l_dom = ops.o_infer_univ ctx dom in
         let* dom_v = ops.o_eval ctx dom in
         let* l_cod = ops.o_infer_univ (ops.o_bind x q dom_v ctx) diagram in
         Ok [ l_dom; l_cod ])

let spi_lan_lvl (ls : Level.t list) : Level.t = max_of ls

let spi_ran_lvl (ls : Level.t list) : Level.t =
  level_pair ls
  |> Option.fold ~none:(max_of ls) ~some:(fun ((l : Level.t), (l' : Level.t)) -> imax l l')

(** A level field on the interface SG-D15 gives it.  A shape that reads
    its levels off the payload alone lifts a plain function through
    this, so the ops, the context and the shape are never read. *)
let payload_lvl (f : Level.t list -> Level.t) (_ops : 'c ops) (_ctx : 'c)
    (_s : Value.t Shape.t) (ls : Level.t list) : (Level.t, Error.t) result =
  Ok (f ls)

let spi_form (level : Level.t list -> Level.t) (ops : 'c ops) (ctx : 'c)
    (s : Term.t Shape.t) (diagram : Term.t) ~expected:(_expected : Level.t option) :
    (Level.t, Error.t) result =
  Result.map level (spi_levels ops ctx s diagram)

let spi_beta (ev : evaluator) (r : beta_redex) : (Value.t option, Error.t) result =
  match r with
  | BOut (_s, addr, v) ->
      let@ _q, arg = Value.as_pt addr in
      let@ _vs, legs = Value.as_sec v in
      let@ lg = one_of legs in
      Result.map Option.some (open_closure ev lg.Value.vl_clo [ arg ])
  | BElim (_s, branches, env, v) ->
      let@ _vs, addr, args = Value.as_in v in
      let@ _q, arg = Value.as_pt addr in
      let@ fibre = one_of args in
      let@ _key, leg = one_of branches in
      Result.map Option.some (ev.ev_eval (fibre :: arg :: env) leg.Term.l_body)

(** The expected type of a section at the point shape, with the fibre
    opened at a fresh variable. *)
let spi_intro_sec (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (_s : Term.t Shape.t)
    (legs : Term.leg list) ~(expected : Value.t) : (Quantity.usage, Error.t) result =
  let* _w, (vs, dclo, _u) =
    former_view ops ctx Value.as_ran "a section needs a right former as its expected type" expected in
  let* q, _x, dom_v =
    as_vpi vs
    |> Option.to_result
         ~none:(Error.Mismatch "a section at the point shape needs a point former")
  in
  let* leg =
    one_of legs
    |> Option.to_result
         ~none:(Error.Mismatch "a section at the point shape has one leg")
  in
  let* bq, bx =
    one_of leg.Term.l_binders
    |> Option.to_result ~none:(Error.Mismatch "the leg binds the point once")
  in
  let* () = binder_quantity "binder" "type" bx bq q in
  let v = Value.var (ops.o_size ctx) in
  let* cod = open_closure (ops.o_ev ctx) dclo [ v ] in
  let ctx' = ops.o_bind bx q dom_v ctx in
  let* uses = ops.o_check ctx' (Quantity.runtime mode) leg.Term.l_body cod in
  let* free = ops.o_close ctx' (ops.o_size ctx) mode uses in
  Ok (Quantity.scale mode (Quantity.captures free))

let spi_intro_in (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (_s : Term.t Shape.t)
    (addr : Term.addr) (args : Term.t list) ~(expected : Value.t) :
    (Quantity.usage, Error.t) result =
  let* _w, (vs, dclo, _u) =
    former_view ops ctx Value.as_lan "a pair needs a left former as its expected type" expected in
  let* q, _x, dom_v =
    as_vpi vs
    |> Option.to_result ~none:(Error.Mismatch "a pair needs a point former")
  in
  let* _aq, point =
    Term.as_apt addr
    |> Option.to_result ~none:(Error.Wrong_leg "a pair takes the point address")
  in
  let* fibre =
    one_of args
    |> Option.to_result ~none:(Error.Mismatch "a pair carries one fibre element")
  in
  let* point_uses = ops.o_check ctx (Quantity.mul mode q) point dom_v in
  let* point_v = ops.o_eval ctx point in
  let* cod = open_closure (ops.o_ev ctx) dclo [ point_v ] in
  let* fibre_uses = ops.o_check ctx mode fibre cod in
  Ok (Quantity.sequence point_uses fibre_uses)

let spi_elim_out (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (_s : Term.t Shape.t)
    (addr : Term.addr) (head : Term.t) : (Value.t * Quantity.usage, Error.t) result =
  let* _aq, point =
    Term.as_apt addr
    |> Option.to_result ~none:(Error.Wrong_leg "an application takes the point address")
  in
  let* head_ty, head_uses = ops.o_infer ctx mode head in
  let* _w, (vs, dclo, _u) =
    former_view ops ctx Value.as_ran "the head of an application is not a function" head_ty in
  let* q, _x, dom_v =
    as_vpi vs
    |> Option.to_result
         ~none:(Error.Mismatch "the head of an application is not a function")
  in
  let* point_uses = ops.o_check ctx (Quantity.mul mode q) point dom_v in
  let* point_v = ops.o_eval ctx point in
  let* result = open_closure (ops.o_ev ctx) dclo [ point_v ] in
  Ok (result, Quantity.sequence head_uses point_uses)

let spi_elim_elim (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (e : Term.elim)
    ~(expected : Value.t option) : (Value.t * Quantity.usage, Error.t) result =
  let* scrut_ty, scrut_uses = infer_scrutinee ops ctx mode e in
  let* w, (vs, dclo, _u) =
    former_view ops ctx Value.as_lan "the scrutinee is not a left former" scrut_ty in
  let* q, _x, dom_v =
    as_vpi vs |> Option.to_result ~none:(Error.Mismatch wrong_pack)
  in
  let* () = check_motive ops ctx e.Term.e_motive w in
  let* scrut_v = ops.o_eval ctx e.Term.e_scrut in
  let* result = elim_result ops ctx e.Term.e_motive expected scrut_v in
  let* key, leg =
    one_of e.Term.e_branches
    |> Option.to_result
         ~none:(Error.Missing_branch "an elimination at the point shape has one branch")
  in
  let* k =
    Term.as_aleg key
    |> Option.to_result ~none:(Error.Wrong_leg "the branch takes the leg address")
  in
  let* () = if Int.equal k 0 then Ok () else Error (Error.Wrong_leg leg_msg) in
  let* (q1, x1), (q2, x2) =
    two_of leg.Term.l_binders
    |> Option.to_result
         ~none:
           (Error.Missing_branch
              "the branch binds the point and the fibre element (D-M0-3)")
  in
  let* () = binder_quantity "branch binder" "type" x1 q1 q in
  let size = ops.o_size ctx in
  let point = Value.var size in
  let fibre = Value.var (size + 1) in
  let* cod = open_closure (ops.o_ev ctx) dclo [ point ] in
  let ctx' = ops.o_bind x2 q2 cod (ops.o_bind x1 q1 dom_v ctx) in
  let self = Value.VIn (vs, Value.VAPt (q, point), [ fibre ]) in
  let* target = elim_result ops ctx e.Term.e_motive expected self in
  let* uses = ops.o_check ctx' (Quantity.runtime mode) leg.Term.l_body target in
  let* free = ops.o_close ctx' (ops.o_size ctx) mode uses in
  Ok (result, Quantity.sequence scrut_uses (Quantity.scale mode free))

(** Eta at the right former of the point shape, SPEC.md section 4 row
    one:  [f] is [Sec [x => Out (APt x) f]], applied by expansion. *)
let spi_eta_ran (ops : 'c ops) (ctx : 'c) (s : Value.t Shape.t) (dclo : Value.closure)
    (a : Value.t) (b : Value.t) : (bool, Error.t) result =
  let* q, x, dom_v =
    as_vpi s |> Option.to_result ~none:(Error.Mismatch wrong_pack)
  in
  let ev = ops.o_ev ctx in
  let v = Value.var (ops.o_size ctx) in
  let* cod = open_closure ev dclo [ v ] in
  let* fa = out_with spi_beta ev s (Value.VAPt (q, v)) a in
  let* fb = out_with spi_beta ev s (Value.VAPt (q, v)) b in
  ops.o_conv (ops.o_bind x q dom_v ctx) ~ty:cod fa fb

(** The projection branch of D-M0-3:  one branch at the leg address,
    binding the point and the fibre element, whose body is the binder
    the projection selects. *)
let proj_branch (q : Quantity.t) (which : int) : (Term.addr * Term.leg) list =
  [
    ( Term.ALeg 0,
      {
        Term.l_binders = [ (q, "x"); (Quantity.Many, "y") ];
        l_body = Term.Var (if Int.equal which 0 then 1 else 0);
      } );
  ]

(** The projection motive of D-M0-3, built here exactly as
    surface/elab.ml builds it for ".1" and ".2" (SB-D38).  A projection
    of a neutral pair freezes on the spine, and two frozen eliminations
    convert only when their motives convert, so the motive the eta rule
    writes must be the motive the surface writes.  The motive of the
    first projection is the domain and the motive of the second is the
    diagram read at the first projection of the point itself. *)
let proj_motive (ops : 'c ops) (ctx : 'c) (s : Value.t Shape.t) (dclo : Value.closure)
    (q : Quantity.t) (x : string) (dom_v : Value.t) (which : int) :
    (Term.motive option, Error.t) result =
  let ev = ops.o_ev ctx in
  let size = ops.o_size ctx in
  let* body_v =
    if Int.equal which 0 then Ok dom_v
    else
      let* point =
        elim_with spi_beta ev s q None (proj_branch q 0) (ops.o_env ctx)
          (Value.var size)
      in
      open_closure ev dclo [ point ]
  in
  let* m_body = ops.o_quote (ops.o_bind x q dom_v ctx) body_v in
  Ok (Some { Term.m_ind = None; m_idx = []; m_self = "self"; m_body })

(** Eta at the left former of the point shape, row two:  [p] is
    [In (APt p.1) [p.2]], compared projection by projection.  The
    scrutinee mark is [One] at both projections, as the surface writes
    it, so the frozen forms of the two sides agree (SB-D38). *)
let spi_eta_lan (ops : 'c ops) (ctx : 'c) (s : Value.t Shape.t) (dclo : Value.closure)
    (a : Value.t) (b : Value.t) : (bool, Error.t) result =
  let* q, x, dom_v =
    as_vpi s |> Option.to_result ~none:(Error.Mismatch wrong_pack)
  in
  let ev = ops.o_ev ctx in
  let env = ops.o_env ctx in
  let* mo_first = proj_motive ops ctx s dclo q x dom_v 0 in
  let* a1 = elim_with spi_beta ev s Quantity.One mo_first (proj_branch q 0) env a in
  let* b1 = elim_with spi_beta ev s Quantity.One mo_first (proj_branch q 0) env b in
  let* first = ops.o_conv ctx ~ty:dom_v a1 b1 in
  if first then
    let* cod = open_closure ev dclo [ a1 ] in
    let* mo_second = proj_motive ops ctx s dclo q x dom_v 1 in
    let* a2 = elim_with spi_beta ev s Quantity.One mo_second (proj_branch q 1) env a in
    let* b2 = elim_with spi_beta ev s Quantity.One mo_second (proj_branch q 1) env b in
    ops.o_conv ctx ~ty:cod a2 b2
  else Ok false

let spi_conv_diagram (ops : 'c ops) (ctx : 'c) (s : Value.t Shape.t)
    (d1 : Value.closure) (d2 : Value.closure) : (bool, Error.t) result =
  let* q, x, dom_v =
    as_vpi s |> Option.to_result ~none:(Error.Mismatch wrong_pack)
  in
  let ev = ops.o_ev ctx in
  let v = Value.var (ops.o_size ctx) in
  let* b1 = open_closure ev d1 [ v ] in
  let* b2 = open_closure ev d2 [ v ] in
  ops.o_conv_type (ops.o_bind x q dom_v ctx) b1 b2

(** Every shape but the empty collection reads its universe from its
    diagram, so the SB-D7 slot carries nothing here. *)
(** One spine step at the point shape:  the argument is at the domain
    and the head then has the diagram read at that argument. *)
let spi_spine_ty (ops : 'c ops) (ctx : 'c) (s : Value.t Shape.t) (dclo : Value.closure)
    (addr : Value.vaddr) : ((Value.t option * Value.t) option, Error.t) result =
  as_vpi s
  |> Option.fold ~none:(Ok None) ~some:(fun ((_q : Quantity.t), (_x : string), (dom : Value.t)) ->
         Value.as_pt addr
         |> Option.fold ~none:(Ok None)
              ~some:(fun ((_qa : Quantity.t), (arg : Value.t)) ->
                Result.map
                  (fun (cod : Value.t) -> Some (Some dom, cod))
                  (open_closure (ops.o_ev ctx) dclo [ arg ])))

(** The point diagram binds the point, so a reader opens one binder to
    look under it.  The collection diagram binds nothing. *)
let spi_diagram_arity (_s : Value.t Shape.t) : int = 1

let coll_diagram_arity (_s : Value.t Shape.t) : int = 0

let spi_ann_lvl_eq (_s : Value.t Shape.t) (_u1 : Level.t option) (_u2 : Level.t option) :
    bool =
  true

(** M1 Stage H, brief 3.5:  a shape with no subsingleton criterion.  The
    two M0 packs answer [Ok false], so step one of conv.ml stands down at
    every shape but the recursive one (SH-D1). *)
let no_subsingleton (_ops : 'c ops) (_ctx : 'c) (_s : Value.t Shape.t) :
    (bool, Error.t) result =
  Ok false

let spi_pack (() : unit) : 'c rule_pack =
  {
    form_lan = (fun ops ctx s d ~expected -> spi_form spi_lan_lvl ops ctx s d ~expected);
    form_ran = (fun ops ctx s d ~expected -> spi_form spi_ran_lvl ops ctx s d ~expected);
    intro_in = spi_intro_in;
    elim_elim = spi_elim_elim;
    intro_sec = spi_intro_sec;
    elim_out = spi_elim_out;
    beta = spi_beta;
    eta = { eta_ran = true; eta_lan = true };
    diagram_arity = spi_diagram_arity;
    spine_ty = spi_spine_ty;
    (* SB-M1 site *)
    expand_ran = Some spi_eta_ran;
    expand_lan = Some spi_eta_lan;
    conv_diagram = spi_conv_diagram;
    ann_lvl_eq = spi_ann_lvl_eq;
    lan_lvl = payload_lvl spi_lan_lvl;
    ran_lvl = payload_lvl spi_ran_lvl;
    subsingleton = no_subsingleton;
  }

(* ---------------------------------------------------------------- *)
(* The pack of the collection shape, plan section 5.                  *)
(* ---------------------------------------------------------------- *)

let coll_lvl (ls : Level.t list) : Level.t = max_of ls

let coll_levels (ops : 'c ops) (ctx : 'c) (s : Term.t Shape.t) (diagram : Term.t)
    ~(expected : Level.t option) : (Level.t, Error.t) result =
  let* n = as_vcoll s |> Option.to_result ~none:(Error.Mismatch wrong_pack) in
  let* ds, legs =
    as_tsec diagram |> Option.to_result ~none:(Error.Mismatch diagram_msg)
  in
  let* dn = as_vcoll ds |> Option.to_result ~none:(Error.Mismatch diagram_msg) in
  let* () =
    if Int.equal dn n && Int.equal (List.length legs) n then Ok ()
    else Error (Error.Mismatch diagram_msg)
  in
  let* () =
    if List.for_all (fun (lg : Term.leg) -> Int.equal (List.length lg.Term.l_binders) 0) legs
    then Ok ()
    else Error (Error.Mismatch "a diagram leg binds nothing")
  in
  let* ls =
    all_ok (List.map (fun (lg : Term.leg) -> ops.o_infer_univ ctx lg.Term.l_body) legs)
  in
  (* D-M0-6:  at width zero the universe comes from the annotation and
     defaults to the proposition universe. *)
  if Int.equal n 0 then Ok (Option.value expected ~default:Level.zero)
  else Ok (coll_lvl ls)

let coll_legs_of (ops : 'c ops) (ctx : 'c) (dclo : Value.closure) :
    (Value.vleg list, Error.t) result =
  let* d = open_closure (ops.o_ev ctx) dclo [] in
  Value.as_sec d
  |> Option.to_result ~none:(Error.Mismatch diagram_msg)
  |> Result.map (fun ((_s : Value.t Shape.t), (legs : Value.vleg list)) -> legs)

let coll_leg_ty (ops : 'c ops) (ctx : 'c) (legs : Value.vleg list) (k : int) :
    (Value.t, Error.t) result =
  let* lg = at k legs |> Option.to_result ~none:(Error.Wrong_leg leg_msg) in
  open_closure (ops.o_ev ctx) lg.Value.vl_clo []

let coll_beta (ev : evaluator) (r : beta_redex) : (Value.t option, Error.t) result =
  match r with
  | BOut (_s, addr, v) ->
      let@ k = Value.as_leg addr in
      let@ _vs, legs = Value.as_sec v in
      let@ lg = at k legs in
      Result.map Option.some (open_closure ev lg.Value.vl_clo [])
  | BElim (_s, branches, env, v) ->
      let@ _vs, addr, args = Value.as_in v in
      let@ k = Value.as_leg addr in
      let@ _key, leg =
        List.find_opt
          (fun ((a : Term.addr), (_l : Term.leg)) ->
            Option.equal Int.equal (Term.as_aleg a) (Some k))
          branches
      in
      Result.map Option.some (ev.ev_eval (List.rev_append args env) leg.Term.l_body)

let coll_intro_sec (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (s : Term.t Shape.t)
    (legs : Term.leg list) ~(expected : Value.t) : (Quantity.usage, Error.t) result =
  let* n = as_vcoll s |> Option.to_result ~none:(Error.Mismatch wrong_pack) in
  let* _w, (vs, dclo, _u) =
    former_view ops ctx Value.as_ran "a tuple needs a right former as its expected type" expected in
  let* dn = as_vcoll vs |> Option.to_result ~none:(Error.Mismatch wrong_pack) in
  let* () =
    if Int.equal dn n && Int.equal (List.length legs) n then Ok ()
    else Error (Error.Mismatch "the tuple width and the type width differ")
  in
  let* dlegs = coll_legs_of ops ctx dclo in
  let* pairs =
    zip legs dlegs |> Option.to_result ~none:(Error.Mismatch diagram_msg)
  in
  let* checked =
    all_ok
      (List.map
         (fun ((lg : Term.leg), (dl : Value.vleg)) ->
           let* ty = open_closure (ops.o_ev ctx) dl.Value.vl_clo [] in
           ops.o_check ctx mode lg.Term.l_body ty)
         pairs)
  in
  Ok (List.fold_left Quantity.sequence Quantity.empty checked)

let coll_intro_in (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (_s : Term.t Shape.t)
    (addr : Term.addr) (args : Term.t list) ~(expected : Value.t) :
    (Quantity.usage, Error.t) result =
  let* _w, (vs, dclo, _u) =
    former_view ops ctx Value.as_lan "an injection needs a left former as its expected type" expected in
  let* n = as_vcoll vs |> Option.to_result ~none:(Error.Mismatch wrong_pack) in
  let* k =
    Term.as_aleg addr
    |> Option.to_result ~none:(Error.Wrong_leg "an injection takes the leg address")
  in
  let* () = if k >= 0 && k < n then Ok () else Error (Error.Wrong_leg leg_msg) in
  let* dlegs = coll_legs_of ops ctx dclo in
  let* ty = coll_leg_ty ops ctx dlegs k in
  let* payload =
    one_of args
    |> Option.to_result ~none:(Error.Mismatch "an injection carries one payload")
  in
  ops.o_check ctx mode payload ty

let coll_elim_out (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (_s : Term.t Shape.t)
    (addr : Term.addr) (head : Term.t) : (Value.t * Quantity.usage, Error.t) result =
  let* k =
    Term.as_aleg addr
    |> Option.to_result ~none:(Error.Wrong_leg "a projection takes the leg address")
  in
  let* head_ty, uses = ops.o_infer ctx mode head in
  let* _w, (vs, dclo, _u) =
    former_view ops ctx Value.as_ran "a projection needs a right former" head_ty in
  let* n = as_vcoll vs |> Option.to_result ~none:(Error.Mismatch wrong_pack) in
  let* () = if k >= 0 && k < n then Ok () else Error (Error.Wrong_leg leg_msg) in
  let* dlegs = coll_legs_of ops ctx dclo in
  let* result = coll_leg_ty ops ctx dlegs k in
  Ok (result, uses)

let coll_branch (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (e : Term.elim)
    (vs : Value.t Shape.t) (dlegs : Value.vleg list) (expected : Value.t option) (k : int)
    : (Quantity.usage, Error.t) result =
  let* _key, leg =
    List.find_opt
      (fun ((a : Term.addr), (_l : Term.leg)) ->
        Option.equal Int.equal (Term.as_aleg a) (Some k))
      e.Term.e_branches
    |> Option.to_result
         ~none:(Error.Missing_branch (Printf.sprintf "no branch at leg %d" k))
  in
  let* bq, bx =
    one_of leg.Term.l_binders
    |> Option.to_result ~none:(Error.Missing_branch "each branch binds its payload once")
  in
  let* ty = coll_leg_ty ops ctx dlegs k in
  let self = Value.VIn (vs, Value.VALeg k, [ Value.var (ops.o_size ctx) ]) in
  let* target = elim_result ops ctx e.Term.e_motive expected self in
  let ctx' = ops.o_bind bx bq ty ctx in
  let* uses = ops.o_check ctx' (Quantity.runtime mode) leg.Term.l_body target in
  ops.o_close ctx' (ops.o_size ctx) mode uses

let coll_elim_elim (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (e : Term.elim)
    ~(expected : Value.t option) : (Value.t * Quantity.usage, Error.t) result =
  let* scrut_ty, scrut_uses = infer_scrutinee ops ctx mode e in
  let* w, (vs, dclo, _u) =
    former_view ops ctx Value.as_lan "the scrutinee is not a left former" scrut_ty in
  let* n = as_vcoll vs |> Option.to_result ~none:(Error.Mismatch wrong_pack) in
  let* () = check_motive ops ctx e.Term.e_motive w in
  let* scrut_v = ops.o_eval ctx e.Term.e_scrut in
  let* result = elim_result ops ctx e.Term.e_motive expected scrut_v in
  let* () =
    if Int.equal (List.length e.Term.e_branches) n then Ok ()
    else
      Error
        (Error.Missing_branch
           (Printf.sprintf "the case has %d branches and the type has %d legs"
              (List.length e.Term.e_branches) n))
  in
  let* dlegs = coll_legs_of ops ctx dclo in
  let* checked =
    all_ok (List.map (coll_branch ops ctx mode e vs dlegs expected) (List.init n Fun.id))
  in
  let branches = List.fold_left Quantity.alternative Quantity.unreachable checked in
  Ok (result, Quantity.sequence scrut_uses (Quantity.scale mode branches))

(** Eta at the right former of the collection shape, SPEC.md section 4
    row three:  [t] is the section of its own projections, and at width
    zero the row makes the unit type a subsingleton. *)
let coll_eta_ran (ops : 'c ops) (ctx : 'c) (s : Value.t Shape.t) (dclo : Value.closure)
    (a : Value.t) (b : Value.t) : (bool, Error.t) result =
  let* n = as_vcoll s |> Option.to_result ~none:(Error.Mismatch wrong_pack) in
  let* dlegs = coll_legs_of ops ctx dclo in
  let ev = ops.o_ev ctx in
  List.fold_left
    (fun (acc : (bool, Error.t) result) (k : int) ->
      let* got = acc in
      if got then
        let* ty = coll_leg_ty ops ctx dlegs k in
        let* x = out_with coll_beta ev s (Value.VALeg k) a in
        let* y = out_with coll_beta ev s (Value.VALeg k) b in
        ops.o_conv ctx ~ty x y
      else Ok false)
    (Ok true) (List.init n Fun.id)

let coll_conv_diagram (ops : 'c ops) (ctx : 'c) (_s : Value.t Shape.t)
    (d1 : Value.closure) (d2 : Value.closure) : (bool, Error.t) result =
  let ev = ops.o_ev ctx in
  let* a = open_closure ev d1 [] in
  let* b = open_closure ev d2 [] in
  ops.o_conv_type ctx a b

(** SB-D7:  at width zero the diagram holds no level, so the annotation
    slot is the carrier and the default is the proposition universe.  At
    every other width the diagram carries the level and the slot is not
    read. *)
(** One spine step at the collection shape:  a projection carries no
    argument, so only the leg type moves. *)
let coll_spine_ty (ops : 'c ops) (ctx : 'c) (_s : Value.t Shape.t)
    (dclo : Value.closure) (addr : Value.vaddr) :
    ((Value.t option * Value.t) option, Error.t) result =
  Value.as_leg addr
  |> Option.fold ~none:(Ok None) ~some:(fun (k : int) ->
         let* legs = coll_legs_of ops ctx dclo in
         at k legs
         |> Option.fold ~none:(Ok None) ~some:(fun (lg : Value.vleg) ->
                Result.map
                  (fun (ty : Value.t) -> Some (None, ty))
                  (open_closure (ops.o_ev ctx) lg.Value.vl_clo [])))

let coll_ann_lvl_eq (s : Value.t Shape.t) (u1 : Level.t option) (u2 : Level.t option) :
    bool =
  as_vcoll s
  |> Option.fold ~none:true ~some:(fun (n : int) ->
         if Int.equal n 0 then
           Level.equal
             (Option.value u1 ~default:Level.zero)
             (Option.value u2 ~default:Level.zero)
         else true)

let coll_pack (() : unit) : 'c rule_pack =
  {
    form_lan = coll_levels;
    form_ran = coll_levels;
    intro_in = coll_intro_in;
    elim_elim = coll_elim_elim;
    intro_sec = coll_intro_sec;
    elim_out = coll_elim_out;
    beta = coll_beta;
    eta = { eta_ran = true; eta_lan = false };
    diagram_arity = coll_diagram_arity;
    spine_ty = coll_spine_ty;
    expand_ran = Some coll_eta_ran;
    expand_lan = None;
    conv_diagram = coll_conv_diagram;
    ann_lvl_eq = coll_ann_lvl_eq;
    lan_lvl = payload_lvl coll_lvl;
    ran_lvl = payload_lvl coll_lvl;
    subsingleton = no_subsingleton;
  }

(* ------- The pack of the mu shape, plan section 5, brief 3.1 ------- *)

(** SG-D4:  one pack answers both formers (M1-PLAN.md:8), so the right
    former is refused INSIDE it;  a section is SNu's (SPEC.md:32). *)
let mu_ran_word : string = "a right former at a mu shape arrives at M2"

(** M1 Stage H, brief 3.3 and SH-D5:  the branch types of an indexed
    family are not recoverable from the scrutinee type alone, so the
    motive is required and the pack answers this word when it is
    missing (A7, M1-PLAN.md:80).  It stands where the Stage H word of
    SG-D9 stood. *)
let mu_motive_word : string = "an elimination at a mu shape needs a motive"

(** M1 Stage H, brief 3.4 and SH-D4:  a family that does not pass the
    criterion carries no large elimination, and a self-recursive family
    never passes it (A1, M1-PLAN.md:86). *)
let mu_large_word : string =
  "a large elimination out of a proposition needs a subsingleton family"

let as_vmu (s : 'a Shape.t) : (string * 'a list) option =
  match s with
  | Shape.SMu (n, ix) -> Some (n, ix)
  | Shape.SPi (_, _, _) | Shape.SColl _ | Shape.SPar (_, _) | Shape.SNu (_, _) -> None

(** Brief 3.4:  tot's three-part criterion, ported part for part from
    kan-lang-tot-pin/lib/check.ml:223 [zero_eliminable] and never
    restated in kanon's own words (D-M1-3, SH-D2).  Each arm carries the
    pin line it is the port of.  The port reads three fields of the
    record and adds none. *)
let mu_zero_eliminable (fam : Positivity.family) : bool =
  match fam.Positivity.f_status with
  (* pin check.ml:225 *)
  | Positivity.Provisional -> false
  (* pin check.ml:226 *)
  | Positivity.Builtin -> false
  (* part one, pin check.ml:227 *)
  | Positivity.Complete [] -> true
  (* part one, pin check.ml:228 *)
  | Positivity.Complete [ c ] ->
      Positivity.ctor_of c fam
      |> Option.fold ~none:false ~some:(fun (ct : Positivity.ctor) ->
             (* part two, pin check.ml:231 *)
             List.for_all
               (fun ((q : Quantity.t), (_x : string), (_ty : Term.t)) ->
                 Quantity.equal q Quantity.Zero)
               ct.Positivity.c_args
             (* part three, pin check.ml:232 *)
             && not ct.Positivity.c_self_rec)
  (* pin check.ml:233 *)
  | Positivity.Complete (_ :: _ :: _) -> false

(** The one accessor of brief 3.3 (SG-D2) reads the stored A4 verdict and
    never recomputes it (D-M1-2).  SG-D17:  a [Provisional] family forms,
    a field type names it as the constructors install (pin check.ml:2050). *)
let mu_family (ops : 'c ops) (ctx : 'c) (n : string) : (Positivity.family, Error.t) result =
  let* f =
    ops.o_family ctx n
    |> Option.to_result ~none:(Error.Unbound ("the family " ^ n ^ " is not declared"))
  in
  match f.Positivity.f_status with
  | Positivity.Complete (_ : string list) ->
      if f.Positivity.f_positive then Ok f
      else Error (Error.Not_yet Positivity.nonpositive_word)
  | Positivity.Builtin | Positivity.Provisional -> Ok f

(** Brief 3.5:  conversion uses the criterion only for a Prop family.
    Erased fields of a Type family may contain distinct types, so the
    large elimination criterion alone cannot make its inhabitants equal.
    The pack keeps the family lookup out of conv.ml (SH-D1).
    A family the accessor cannot answer for is not a
    subsingleton as far as the rule is concerned, so a failure here
    weakens conversion to its other steps and never strengthens it
    (conv.ml, rule 1). *)
let mu_subsingleton (ops : 'c ops) (ctx : 'c) (s : Value.t Shape.t) :
    (bool, Error.t) result =
  as_vmu s
  |> Option.fold ~none:(Ok false) ~some:(fun ((n : string), (_ix : Value.t list)) ->
         mu_family ops ctx n
         |> Result.fold
              ~ok:(fun (fam : Positivity.family) ->
                Ok
                  (Level.equal fam.Positivity.f_level Level.zero
                  && mu_zero_eliminable fam))
              ~error:(fun (_e : Error.t) -> Ok false))

(** SG-D16:  the diagram at the mu shape is the parameter section, one
    binder free leg per parameter, so [diagram_arity] is zero. *)
let mu_params_of (diagram : Term.t) : (Term.t list, Error.t) result =
  as_tsec diagram
  |> Option.to_result ~none:(Error.Mismatch diagram_msg)
  |> Result.map (fun ((_s : Term.t Shape.t), (legs : Term.leg list)) ->
         List.map (fun (lg : Term.leg) -> lg.Term.l_body) legs)

(** Check an expression list against a telescope (pin check.ml:1804-1827):
    each type opens in the values before it, innermost value first. *)
let mu_telescope_uses (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (what : string)
    (tele : Positivity.telescope) (args : Term.t list) (env : Value.t list) :
    (Value.t list * Quantity.usage, Error.t) result =
  let* pairs =
    zip tele args
    |> Option.to_result
         ~none:
           (Error.Mismatch
              (Printf.sprintf "%s takes %d arguments and the term gives %d" what
                 (List.length tele) (List.length args)))
  in
  let ev = ops.o_ev ctx in
  List.fold_left
    (fun (acc : (Value.t list * Quantity.usage, Error.t) result)
         (((q, _x, ty), arg) : (Quantity.t * string * Term.t) * Term.t) ->
      let* got, uses = acc in
      let* tyv = ev.ev_eval got ty in
      let* arg_uses = ops.o_check ctx (Quantity.mul mode q) arg tyv in
      let* v = ops.o_eval ctx arg in
      Ok (v :: got, Quantity.sequence uses arg_uses))
    (Ok (env, Quantity.empty)) pairs

let mu_telescope ops ctx mode what tele args env =
  Result.map fst (mu_telescope_uses ops ctx mode what tele args env)

(** Formation (M1-PLAN.md:78, brief 3.1):  a declared, positive family,
    parameters and indices erased;  SG-D8 takes its level (brief 3.4, A5). *)
let mu_form_lan (ops : 'c ops) (ctx : 'c) (s : Term.t Shape.t) (diagram : Term.t)
    ~(expected : Level.t option) : (Level.t, Error.t) result =
  let _ = expected in
  let z = Quantity.Zero in
  let* n, ix = as_vmu s |> Option.to_result ~none:(Error.Mismatch wrong_pack) in
  let* fam = mu_family ops ctx n in
  let* params = mu_params_of diagram in
  let* penv = mu_telescope ops ctx z n fam.Positivity.f_params params [] in
  let* _ienv =
    mu_telescope ops ctx z ("the indices of " ^ n) fam.Positivity.f_indices ix penv
  in
  Ok fam.Positivity.f_level

let mu_form_ran (_ops : 'c ops) (_ctx : 'c) (_s : Term.t Shape.t) (_diagram : Term.t)
    ~(expected : Level.t option) : (Level.t, Error.t) result =
  let _ = expected in
  Error (Error.Not_yet mu_ran_word)

(** The parameter values of the expected type, innermost first, so a
    field type and a result index open under them (SG-D16). *)
let mu_param_env (ops : 'c ops) (ctx : 'c) (dclo : Value.closure) :
    (Value.t list, Error.t) result =
  let* legs = coll_legs_of ops ctx dclo in
  let ev = ops.o_ev ctx in
  let* vs =
    all_ok (List.map (fun (lg : Value.vleg) -> open_closure ev lg.Value.vl_clo []) legs)
  in
  Ok (List.rev vs)

(** The index rule of the introduction (A14, M1-PLAN.md:79):  the result
    indices convert with those of the expected type.  SG-M3 drops it. *)
let mu_indices (ops : 'c ops) (ctx : 'c) (n : string) (ct : Positivity.ctor)
    (ixv : Value.t list) (env : Value.t list) : (unit, Error.t) result =
  let arity = List.length ct.Positivity.c_res_idx in
  let* pairs =
    zip ct.Positivity.c_res_idx ixv
    |> Option.to_result
         ~none:
           (Error.Mismatch
              (Printf.sprintf "%s gives %d result indices and %s takes %d"
                 ct.Positivity.c_name arity n (List.length ixv)))
  in
  let ev = ops.o_ev ctx in
  List.fold_left
    (fun (acc : (unit, Error.t) result) ((r, want) : Term.t * Value.t) ->
      let* () = acc in
      let* got = ev.ev_eval env r in
      let* eq = ops.o_conv_type ctx got want in
      if eq then Ok ()
      else
        Error
          (Error.Mismatch
             (Printf.sprintf
                "the constructor %s of %s gives the index %s and the type asks for %s"
                ct.Positivity.c_name n (ops.o_pp ctx got) (ops.o_pp ctx want))))
    (Ok ()) pairs

(** Introduction, M1-PLAN.md:79 and brief 3.1:  the address names the
    constructor, every argument checks and the result indices unify. *)
let mu_intro_in (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (_s : Term.t Shape.t)
    (addr : Term.addr) (args : Term.t list) ~(expected : Value.t) :
    (Quantity.usage, Error.t) result =
  let* _w, (vs, dclo, _u) =
    former_view ops ctx Value.as_lan "a constructor needs a left former" expected in
  let* n, ixv = as_vmu vs |> Option.to_result ~none:(Error.Mismatch wrong_pack) in
  let* c =
    Term.as_actor addr
    |> Option.to_result ~none:(Error.Wrong_leg "a constructor takes a constructor address")
  in
  let* fam = mu_family ops ctx n in
  let* ct =
    Positivity.ctor_of c fam
    |> Option.to_result ~none:(Error.Unbound (c ^ " is not a constructor of " ^ n))
  in
  let* penv = mu_param_env ops ctx dclo in
  let* env, uses = mu_telescope_uses ops ctx mode c ct.Positivity.c_args args penv in
  let* () = mu_indices ops ctx n ct ixv env in
  Ok uses

(** Brief 3.3, SH-D5 and SH-D6:  the motive is required, it names the
    family of the scrutinee shape, and it binds one index binder per
    index of that family (A7, M1-PLAN.md:80). *)
let mu_motive_of (n : string) (fam : Positivity.family) (ixv : Value.t list)
    (e : Term.elim) : (Term.motive, Error.t) result =
  let* mo =
    e.Term.e_motive |> Option.to_result ~none:(Error.Cannot_infer mu_motive_word)
  in
  let* mn =
    mo.Term.m_ind
    |> Option.to_result
         ~none:(Error.Mismatch ("the motive of an elimination at " ^ n ^ " names no family"))
  in
  let want : int = List.length fam.Positivity.f_indices in
  let got : int = List.length mo.Term.m_idx in
  match () with
  | () when not (String.equal mn n) ->
      Error
        (Error.Mismatch
           (Printf.sprintf "the motive is built for %s and the scrutinee is at %s" mn n))
  | () when not (Int.equal got want) ->
      Error
        (Error.Mismatch
           (Printf.sprintf "the motive of %s binds %d indices and the family has %d" n got
              want))
  | () when not (Int.equal (List.length ixv) want) ->
      Error
        (Error.Mismatch
           (Printf.sprintf "%s is applied to %d indices and the family has %d" n
              (List.length ixv) want))
  | () -> Ok mo

(** SH-D7:  the motive read at index values and at a term of the family,
    in the scoping convention of lib/term.ml:10-14.  [m_body] is under
    [m_idx] and then under [m_self], so the environment carries the self
    value first and the indices innermost first. *)
let mu_result (ops : 'c ops) (ctx : 'c) (mo : Term.motive) (idx : Value.t list)
    (self : Value.t) : (Value.t, Error.t) result =
  (ops.o_ev ctx).ev_eval (self :: List.rev_append idx (ops.o_env ctx)) mo.Term.m_body

(** The motive is a type under its index binders and its scrutinee
    binder, so a bad motive fails here and not at the first branch, as
    [check_motive] does at the M0 shapes.  The index binders are erased
    (A2), and the answer is the universe of the motive, which brief 3.4
    reads to tell a large elimination from a small one. *)
let mu_motive_lvl (ops : 'c ops) (ctx : 'c) (n : string) (fam : Positivity.family)
    (mo : Term.motive) (dclo : Value.closure) (u : Level.t option) (penv : Value.t list) :
    (Level.t, Error.t) result =
  let* pairs =
    zip fam.Positivity.f_indices mo.Term.m_idx
    |> Option.to_result
         ~none:(Error.Mismatch ("the motive of " ^ n ^ " does not bind the indices"))
  in
  let ev = ops.o_ev ctx in
  let* ctx', _env, vals =
    List.fold_left
      (fun (acc : ('c * Value.t list * Value.t list, Error.t) result)
           ((((_q : Quantity.t), (_x : string), (ty : Term.t)), (x : string)) :
             (Quantity.t * string * Term.t) * string) ->
        let* c_acc, env_acc, vals_acc = acc in
        let* tyv = ev.ev_eval env_acc ty in
        let v = Value.var (ops.o_size c_acc) in
        Ok (ops.o_bind x Quantity.Zero tyv c_acc, v :: env_acc, v :: vals_acc))
      (Ok (ctx, penv, []))
      pairs
  in
  let self_ty = Value.VLan (Shape.SMu (n, List.rev vals), dclo, u) in
  ops.o_infer_univ (ops.o_bind mo.Term.m_self Quantity.Zero self_ty ctx') mo.Term.m_body

(** Brief 3.4 and M1-PLAN.md:86:  an elimination out of a proposition
    into a motive above the proposition universe is admitted only when
    the family passes the criterion (SH-D3, SH-D4).  A family above the
    proposition universe and a motive at it are both small, so neither
    asks the criterion. *)
let mu_large (n : string) (fam : Positivity.family) (mlvl : Level.t) :
    (unit, Error.t) result =
  match () with
  | () when not (Level.equal fam.Positivity.f_level Level.zero) -> Ok ()
  | () when Level.equal mlvl Level.zero -> Ok ()
  | () when mu_zero_eliminable fam -> Ok ()
  | () -> Error (Error.Universe (Printf.sprintf "%s at %s" mu_large_word n))

(** SH-D8:  the constructor names in declaration order, off the status
    the record carries.  A family under declaration and a kernel family
    have no branch list, so neither is eliminated here. *)
let mu_ctor_names (n : string) (fam : Positivity.family) : (string list, Error.t) result =
  match fam.Positivity.f_status with
  | Positivity.Complete (names : string list) -> Ok names
  | Positivity.Provisional ->
      Error (Error.Unbound ("the family " ^ n ^ " is still under declaration"))
  | Positivity.Builtin ->
      Error (Error.Mismatch ("the family " ^ n ^ " is a kernel family and has no branches"))

let mu_count (x : string) (xs : string list) : int =
  List.length (List.filter (String.equal x) xs)

(** SH-D8:  a missing branch and a repeated branch are both errors, and
    a branch at a name the family does not declare is one too
    (M1-PLAN.md:80, A15).  The list is read in declaration order. *)
let mu_cover (n : string) (names : string list) (branches : (Term.addr * Term.leg) list) :
    (unit, Error.t) result =
  let keys : string list =
    List.filter_map (fun ((a : Term.addr), (_l : Term.leg)) -> Term.as_actor a) branches
  in
  let* () =
    if Int.equal (List.length keys) (List.length branches) then Ok ()
    else
      Error (Error.Wrong_leg ("a branch of " ^ n ^ " takes the constructor address"))
  in
  let* () =
    List.fold_left
      (fun (acc : (unit, Error.t) result) (c : string) ->
        let* () = acc in
        let k : int = mu_count c keys in
        match () with
        | () when Int.equal k 1 -> Ok ()
        | () when Int.equal k 0 ->
            Error
              (Error.Missing_branch
                 (Printf.sprintf "the elimination of %s has no branch at %s" n c))
        | () ->
            Error
              (Error.Wrong_leg
                 (Printf.sprintf "the elimination of %s repeats the branch at %s" n c)))
      (Ok ()) names
  in
  List.fold_left
    (fun (acc : (unit, Error.t) result) (k : string) ->
      let* () = acc in
      if List.exists (String.equal k) names then Ok ()
      else Error (Error.Unbound (k ^ " is not a constructor of " ^ n)))
    (Ok ()) keys

(** Brief 3.2 and SH-D9:  the leg binds the constructor arguments in
    order, one binder per field, at the field quantities the record
    carries (M1-PLAN.md:61).  The body is checked at [m_body]
    instantiated at that constructor's result index expressions and at
    its own [In] term (SH-D7). *)
let mu_branch (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (n : string)
    (fam : Positivity.family) (mo : Term.motive) (penv : Value.t list)
    (branches : (Term.addr * Term.leg) list) (c : string) : (Quantity.usage, Error.t) result =
  let* ct =
    Positivity.ctor_of c fam
    |> Option.to_result ~none:(Error.Unbound (c ^ " is not a constructor of " ^ n))
  in
  let* _key, leg =
    List.find_opt
      (fun ((a : Term.addr), (_l : Term.leg)) ->
        Option.equal String.equal (Term.as_actor a) (Some c))
      branches
    |> Option.to_result
         ~none:
           (Error.Missing_branch
              (Printf.sprintf "the elimination of %s has no branch at %s" n c))
  in
  let* pairs =
    zip ct.Positivity.c_args leg.Term.l_binders
    |> Option.to_result
         ~none:
           (Error.Missing_branch
              (Printf.sprintf "the branch at %s binds %d fields and %s takes %d" c
                 (List.length leg.Term.l_binders) c (List.length ct.Positivity.c_args)))
  in
  let ev = ops.o_ev ctx in
  let* ctx', env, vals =
    List.fold_left
      (fun (acc : ('c * Value.t list * Value.t list, Error.t) result)
           ((((q : Quantity.t), (_x : string), (ty : Term.t)), ((bq : Quantity.t), (bx : string))) :
             (Quantity.t * string * Term.t) * (Quantity.t * string)) ->
        let* c_acc, env_acc, vals_acc = acc in
        let* tyv = ev.ev_eval env_acc ty in
        let v = Value.var (ops.o_size c_acc) in
        let* () = binder_quantity "branch binder" "field" bx bq q in
        Ok (ops.o_bind bx q tyv c_acc, v :: env_acc, v :: vals_acc))
      (Ok (ctx, penv, []))
      pairs
  in
  let* idx =
    all_ok (List.map (fun (r : Term.t) -> ev.ev_eval env r) ct.Positivity.c_res_idx)
  in
  let self = Value.VIn (Shape.SMu (n, idx), Value.VACtor c, List.rev vals) in
  let* target = mu_result ops ctx mo idx self in
  let* uses = ops.o_check ctx' (Quantity.runtime mode) leg.Term.l_body target in
  ops.o_close ctx' (ops.o_size ctx) mode uses

(** Elimination, M1-PLAN.md:80 and brief 3.1 to 3.4.  The expected type
    never stands in as the constant cocone here, because the motive is
    required (SH-D5). *)
let mu_elim_elim (ops : 'c ops) (ctx : 'c) (mode : Quantity.t) (e : Term.elim)
    ~(expected : Value.t option) : (Value.t * Quantity.usage, Error.t) result =
  let _ = expected in
  let* scrut_ty, scrut_uses = infer_scrutinee ops ctx mode e in
  let* _w, (vs, dclo, u) =
    former_view ops ctx Value.as_lan "the scrutinee is not a left former" scrut_ty in
  let* n, ixv = as_vmu vs |> Option.to_result ~none:(Error.Mismatch wrong_pack) in
  let* fam = mu_family ops ctx n in
  let* mo = mu_motive_of n fam ixv e in
  let* penv = mu_param_env ops ctx dclo in
  let* mlvl = mu_motive_lvl ops ctx n fam mo dclo u penv in
  let* () = mu_large n fam mlvl in
  let* names = mu_ctor_names n fam in
  let* () = mu_cover n names e.Term.e_branches in
  let* checked =
    all_ok (List.map (mu_branch ops ctx mode n fam mo penv e.Term.e_branches) names)
  in
  let* scrut_v = ops.o_eval ctx e.Term.e_scrut in
  let* result = mu_result ops ctx mo ixv scrut_v in
  let branches = List.fold_left Quantity.alternative Quantity.unreachable checked in
  Ok (result, Quantity.sequence scrut_uses (Quantity.scale mode branches))

(** Reduction, M1-PLAN.md:81 and brief 3.1:  an [Elim] at
    [In (SMu .., ACtor c, args)] reduces to the branch at [c] with the
    arguments substituted.  A recursive argument carries the recursive
    result when the translation of Stage I built the [Elim];  this stage
    lands the reduction that translation feeds.  A section at the mu
    shape is still SNu's, so [BOut] keeps the M2 word (SG-D4). *)
let mu_beta (ev : evaluator) (r : beta_redex) : (Value.t option, Error.t) result =
  match r with
  | BOut (_, _, _) -> Error (Error.Not_yet mu_ran_word)
  | BElim (_s, branches, env, v) ->
      let@ _vs, addr, args = Value.as_in v in
      let@ c = Value.as_ctor addr in
      let@ _key, leg =
        List.find_opt
          (fun ((a : Term.addr), (_l : Term.leg)) ->
            Option.equal String.equal (Term.as_actor a) (Some c))
          branches
      in
      Result.map Option.some (ev.ev_eval (List.rev_append args env) leg.Term.l_body)

(** Brief 3.5:  [lan_lvl] is the level the record carries (SG-D8, SG-D15). *)
let mu_lan_lvl (ops : 'c ops) (ctx : 'c) (s : Value.t Shape.t) (_ls : Level.t list) :
    (Level.t, Error.t) result =
  let* n, _ix = as_vmu s |> Option.to_result ~none:(Error.Mismatch wrong_pack) in
  let* fam = mu_family ops ctx n in
  Ok fam.Positivity.f_level

(** The pack.  Each refusal sits at the field that answers for it
    (SG-D4, SG-D9). *)
let mu_pack (() : unit) : 'c rule_pack =
  {
    form_lan = mu_form_lan;
    form_ran = (fun _ops _ctx _s _d ~expected:_ -> Error (Error.Not_yet mu_ran_word));
    intro_in = mu_intro_in;
    (* M1 Stage H, brief 3.1:  the two elimination sites of the Stage H
       word are this field and the [BElim] arm of [mu_beta].  Nothing
       moves at the dispatch, which keys on the shape alone. *)
    elim_elim = mu_elim_elim;
    intro_sec =
      (fun _ops _ctx _mode _s _legs ~expected:_ -> Error (Error.Not_yet mu_ran_word));
    elim_out = (fun _ops _ctx _mode _s _addr _head -> Error (Error.Not_yet mu_ran_word));
    beta = mu_beta;
    (* SG-D5:  one introduction address per constructor, so neither former
       gets an eta row and [no eta] grows from 1 to 3 (M1-PLAN.md:82). *)
    eta = { eta_ran = false; eta_lan = false };
    (* SG-D16:  the parameter section is binder free, so these two fields
       are the collection's own. *)
    diagram_arity = coll_diagram_arity;
    (* [Ok None] falls conversion back to a structural compare (SB-D25). *)
    spine_ty = (fun _ops _ctx _s _d _addr -> Ok None);
    expand_ran = None;
    expand_lan = None;
    conv_diagram = coll_conv_diagram;
    (* The record carries the level, so SB-D7's slot is not the carrier. *)
    ann_lvl_eq = spi_ann_lvl_eq;
    lan_lvl = mu_lan_lvl;
    (* A coinductive section is SNu's job (SPEC.md:32, SG-D4). *)
    ran_lvl = (fun _ops _ctx _s _ls -> Error (Error.Not_yet mu_ran_word));
    (* M1 Stage H, brief 3.5:  conv.ml reads the criterion here. *)
    subsingleton = mu_subsingleton;
  }

(** The dispatch of plan section 5.  Three shapes have a pack;  the
    other two carry their milestone word, so a term that reaches the
    checker at one of them fails with the name of the milestone that
    admits it (D-M0-2). *)
let rules (s : 'a Shape.t) : ('c rule_pack, Error.t) result =
  match s with
  | Shape.SPi (_, _, _) -> Ok (spi_pack ())
  | Shape.SColl _ -> Ok (coll_pack ())
  | Shape.SPar (_, _) -> Error (Error.Not_yet spar_word)
  (* SB-M4 site;  M1 Stage G installs the pack the refusal stood for. *)
  | Shape.SMu (_, _) -> Ok (mu_pack ())
  | Shape.SNu (_, _) -> Error (Error.Not_yet snu_word)

(** The two eliminations, with the pack found from the shape.  eval.ml
    calls these, so no shape name reaches it. *)

let out_value (ev : evaluator) (s : Value.t Shape.t) (addr : Value.vaddr) (v : Value.t) :
    (Value.t, Error.t) result =
  let* (pack : unit rule_pack) = rules s in
  out_with pack.beta ev s addr v

let elim_value (ev : evaluator) (s : Value.t Shape.t) (q : Quantity.t)
    (mo : Term.motive option) (branches : (Term.addr * Term.leg) list)
    (env : Value.t list) (v : Value.t) : (Value.t, Error.t) result =
  let* (pack : unit rule_pack) = rules s in
  elim_with pack.beta ev s q mo branches env v

(** One sample per declared shape, in the order shape.ml declares them.
    [admitted] and [eta_table] are read off [rules] itself, so a shape
    that gains or loses a pack moves the R0 counts with no edit in
    spec_count.ml (brief 3.6). *)
let samples : Term.t Shape.t list =
  [
    Shape.SPi (Quantity.Many, "x", Term.Univ Level.zero);
    Shape.SColl 0;
    Shape.SPar (Term.Univ Level.zero, Term.Univ Level.zero);
    Shape.SMu ("x", []);
    Shape.SNu ("x", []);
  ]

let packs : (string * unit rule_pack) list =
  List.filter_map
    (fun (s : Term.t Shape.t) ->
      rules s |> Result.to_option
      |> Option.map (fun (p : unit rule_pack) -> (Shape.name s, p)))
    samples

let admitted : string list = List.map fst packs

let eta_table : (string * eta_row) list =
  List.map (fun ((n : string), (p : unit rule_pack)) -> (n, p.eta)) packs

(** The named non-schema conversion rules of SPEC.md section 5.  Three
    are declared, two are present at M0 and the third arrives with the
    criterion of brief 3.4, in the order the declared row uses (R-Q2,
    SH-D10, M1-PLAN.md:8). *)
let named_declared : string list =
  [ "proof-irrelevance"; "subsingleton-large-elimination"; "literal-fast-path" ]

let named_present : string list =
  [ "proof-irrelevance"; "subsingleton-large-elimination"; "literal-fast-path" ]
