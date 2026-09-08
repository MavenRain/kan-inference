(** Normalization by evaluation, plan section 5.  The evaluator is tot's
    (kan-lang-tot-pin/lib/eval.ml:46) rewritten arm by arm over the
    thirteen constructors of term.ml, and the readback is tot's
    [quote] (kan-lang-tot-pin/lib/eval.ml:183).

    Two rules of the domain, both tot's.  Syntax uses de Bruijn indices
    and values use de Bruijn levels, so a value is stable under a context
    that grows.  A closure keeps the environment it was built under, so
    no substitution ever walks a term.

    The evaluator is call by value, so every value it returns is already
    in weak head normal form.  [whnf] handles literal primitives and
    recursive globals whose guarded argument is a constructor.

    No shape name appears in this file (gate leg R0-AUDIT).  Elimination
    goes through [Rules.out_value] and [Rules.elim_value], which read the
    pack of the shape they are given, and readback asks the pack how many
    binders a diagram opens. *)

let ( let* ) = Result.bind

let rec eval (globals : Global.t) (env : Value.t list) (tm : Term.t) :
    (Value.t, Error.t) result =
  match tm with
  | Term.Var ix ->
      Rules.at ix env
      |> Option.to_result
           ~none:
             (Error.Unbound
                (Printf.sprintf "de Bruijn index %d is outside the environment" ix))
  | Term.Univ l -> Ok (Value.VUniv l)
  | Term.Lit l -> Ok (Value.VLit l)
  | Term.Lan (s, diagram) ->
      let* vs = Rules.map_shape (eval globals env) s in
      Ok (Value.VLan (vs, Value.close env diagram, None))
  | Term.Ran (s, diagram) ->
      let* vs = Rules.map_shape (eval globals env) s in
      Ok (Value.VRan (vs, Value.close env diagram, None))
  | Term.In (s, addr, args) ->
      let* vs = Rules.map_shape (eval globals env) s in
      let* va = eval_addr globals env addr in
      let* vargs = Rules.all_ok (List.map (eval globals env) args) in
      Ok (Value.VIn (vs, va, vargs))
  | Term.Sec (s, legs) ->
      let* vs = Rules.map_shape (eval globals env) s in
      Ok (Value.VSec (vs, List.map (leg_closure env) legs))
  | Term.Out (s, addr, scrut) ->
      let* vs = Rules.map_shape (eval globals env) s in
      let* va = eval_addr globals env addr in
      let* v = eval globals env scrut in
      let* applied = Rules.out_value (ev globals) vs va v in
      whnf globals applied
  | Term.Elim e ->
      let* vs = Rules.map_shape (eval globals env) e.Term.e_shape in
      let* v = eval globals env e.Term.e_scrut in
      Rules.elim_value (ev globals) vs e.Term.e_scrut_q e.Term.e_motive e.Term.e_branches
        env v
  | Term.Let (_x, _ty, def, body) ->
      let* d = eval globals env def in
      eval globals (d :: env) body
  | Term.Ann (tm', ty) ->
      let* v = eval globals env tm' in
      Ok (annotate globals env v ty)
  | Term.Global n -> eval_global globals n
  | Term.Auto -> Error (Error.Not_yet Rules.auto_word)

and ev (globals : Global.t) : Rules.evaluator =
  { Rules.ev_eval = (fun (env : Value.t list) (t : Term.t) -> eval globals env t) }

and leg_closure (env : Value.t list) (lg : Term.leg) : Value.vleg =
  { Value.vl_binders = lg.Term.l_binders; vl_clo = Value.close env lg.Term.l_body }

and eval_addr (globals : Global.t) (env : Value.t list) (a : Term.addr) :
    (Value.vaddr, Error.t) result =
  match a with
  | Term.APt (q, arg) ->
      Result.map (fun (v : Value.t) -> Value.VAPt (q, v)) (eval globals env arg)
  | Term.ALeg k -> Ok (Value.VALeg k)
  | Term.ACtor c -> Ok (Value.VACtor c)

(** A [Def] unfolds only when it is reducible, as tot does
    (kan-lang-tot-pin/lib/eval.ml:46, the Global arm).  An [Axiom] and a
    [Prim] have no body, so both stand as a neutral head. *)
and eval_global (globals : Global.t) (n : string) : (Value.t, Error.t) result =
  let opaque : Value.t = Value.VNeutral (Value.HGlobal n, []) in
  Global.find n globals
  |> Option.to_result ~none:(Error.Unbound n)
  |> Fun.flip Result.bind (fun (e : Global.entry) ->
         Global.def_of e
         |> Option.fold ~none:(Ok opaque) ~some:(fun (d : Global.def_entry) ->
                if d.Global.reducible && Option.is_none d.Global.rec_arg then
                  eval globals [] d.Global.def
                else Ok opaque))

(** SB-D7:  an annotation whose type is a universe fills the level slot
    of a former, so the width zero collection at [Univ zero] and the same
    former at [Univ one] are two values that never convert.  A slot that
    is already filled stays, and every other value passes through. *)
and annotate (globals : Global.t) (env : Value.t list) (v : Value.t) (ty : Term.t) :
    Value.t =
  let fill (u : Level.t option) : Level.t option =
    u |> Option.fold ~none:(level_of_ann globals env ty) ~some:Option.some
  in
  Value.as_lan v
  |> Option.map
       (fun ((s : Value.t Shape.t), (d : Value.closure), (u : Level.t option)) ->
         Value.VLan (s, d, fill u))
  |> Option.fold
       ~none:
         (Value.as_ran v
         |> Option.map
              (fun ((s : Value.t Shape.t), (d : Value.closure), (u : Level.t option)) ->
                Value.VRan (s, d, fill u))
         |> Option.value ~default:v)
       ~some:(fun (x : Value.t) -> x)

(** The level of an annotation, when the annotation is a universe.  An
    annotation that does not evaluate is not this function's business:
    the checker reports it, and here it reads as no level. *)
and level_of_ann (globals : Global.t) (env : Value.t list) (ty : Term.t) : Level.t option
    =
  eval globals env ty |> Result.to_option |> Fun.flip Option.bind Value.as_univ

(** The literal fast path (SB-D4, SB-D8).  A neutral headed by a
    primitive whose spine is exactly its arity of literal arguments
    answers;  every other neutral stands. *)
and prim_step (globals : Global.t) (v : Value.t) : (Value.t, Error.t) result =
  Value.as_neutral v
  |> Option.fold ~none:(Ok v)
       ~some:(fun ((h : Value.head), (sp : Value.spine list)) ->
         head_prim globals h
         |> Option.fold ~none:(Ok v) ~some:(fun (p : Prim.t) ->
                spine_literals sp
                |> Option.fold ~none:(Ok v) ~some:(fun (lits : Literal.t list) ->
                       if Int.equal (List.length lits) (Prim.arity p) then
                         Result.map (Option.value ~default:v) (Prim.apply p lits)
                       else Ok v)))

and head_prim (globals : Global.t) (h : Value.head) : Prim.t option =
  match h with
  | Value.HGlobal n ->
      Option.map
        (fun (e : Global.prim_entry) -> e.Global.prim)
        (Global.find_prim n globals)
  | Value.HLocal _ -> None

(** The spine is newest first, so folding from the left and consing gives
    the arguments oldest first.  Any frame that is not a point address on
    a literal ends the walk. *)
and spine_literals (sp : Value.spine list) : Literal.t list option =
  List.fold_left
    (fun (acc : Literal.t list option) (fr : Value.spine) ->
      Option.bind acc (fun (xs : Literal.t list) ->
          match fr with
          | Value.SOut (_s, addr) ->
              Value.as_pt addr
              |> Fun.flip Option.bind
                   (fun ((_q : Quantity.t), (v : Value.t)) ->
                     Option.map (fun (l : Literal.t) -> l :: xs) (Value.as_lit v))
          | Value.SElim _ -> None))
    (Some []) sp

(** Guarded unfolding mirrors tot's apply/replay (lib/eval.ml:139-177).
    Only leading point applications count toward the formal position.
    A bare, partial or neutral recursive argument leaves the head frozen. *)
and whnf (globals : Global.t) (v : Value.t) : (Value.t, Error.t) result =
  let* v = prim_step globals v in
  let candidate =
    Value.as_neutral v |> Fun.flip Option.bind (fun (h, sp) ->
        match h with
        | Value.HLocal _ -> None
        | Value.HGlobal n ->
            Global.find n globals |> Fun.flip Option.bind Global.def_of
            |> Fun.flip Option.bind (fun (d : Global.def_entry) ->
                if d.Global.reducible then
                  Option.map (fun (k : int) -> (d.Global.def, k, List.rev sp)) d.Global.rec_arg
                else None))
  in
  candidate |> Option.fold ~none:(Ok v) ~some:(fun (body, k, frames) ->
      if guarded_frame k frames then
        let* head = eval globals [] body in
        replay globals head frames
      else Ok v)

and guarded_frame (k : int) (frames : Value.spine list) : bool =
  match frames with
  | [] | Value.SElim _ :: _ -> false
  | Value.SOut (_s, a) :: rest ->
      Value.as_pt a |> Option.fold ~none:false ~some:(fun (_q, v) ->
          if k > 0 then guarded_frame (k - 1) rest
          else if k < 0 then false
          else
            Value.as_in v |> Fun.flip Option.bind (fun (_s, addr, _args) -> Value.as_ctor addr)
            |> Option.is_some)

and replay (globals : Global.t) (head : Value.t) (frames : Value.spine list) :
    (Value.t, Error.t) result =
  List.fold_left
    (fun acc fr ->
      let* v = acc in
      match fr with
      | Value.SOut (s, a) ->
          let* applied = Rules.out_value (ev globals) s a v in
          whnf globals applied
      | Value.SElim se ->
          Rules.elim_value (ev globals) se.Value.s_shape se.Value.s_scrut_q
            se.Value.s_motive se.Value.s_branches se.Value.s_env v)
    (Ok head) frames

(** Readback, tot's [quote] with the diagram opened at the arity the pack
    reports.  [size] is the number of binders in scope, so a level [lvl]
    reads back as the index [size - lvl - 1].

    A frozen elimination reads back with the branch terms it froze.  They
    are scoped in the environment the elimination captured, so the
    readback of a frozen elimination is faithful only under that
    environment.  Conversion never uses it:  it compares two frozen
    eliminations by evaluating both branch bodies under fresh variables,
    as tot does. *)
and quote (globals : Global.t) (size : int) (v : Value.t) : (Term.t, Error.t) result =
  match v with
  | Value.VUniv l -> Ok (Term.Univ l)
  | Value.VLit l -> Ok (Term.Lit l)
  | Value.VLan (s, d, u) ->
      quote_former globals size s d u (fun ((s' : Term.t Shape.t), (d' : Term.t)) ->
          Term.Lan (s', d'))
  | Value.VRan (s, d, u) ->
      quote_former globals size s d u (fun ((s' : Term.t Shape.t), (d' : Term.t)) ->
          Term.Ran (s', d'))
  | Value.VIn (s, addr, args) ->
      let* s' = Rules.map_shape (quote globals size) s in
      let* a' = quote_addr globals size addr in
      let* args' = Rules.all_ok (List.map (quote globals size) args) in
      Ok (Term.In (s', a', args'))
  | Value.VSec (s, legs) ->
      let* s' = Rules.map_shape (quote globals size) s in
      let* legs' = Rules.all_ok (List.map (quote_leg globals size) legs) in
      Ok (Term.Sec (s', legs'))
  | Value.VNeutral (h, sp) -> quote_neutral globals size h sp

and quote_former (globals : Global.t) (size : int) (s : Value.t Shape.t)
    (dclo : Value.closure) (u : Level.t option)
    (build : Term.t Shape.t * Term.t -> Term.t) : (Term.t, Error.t) result =
  let* s' = Rules.map_shape (quote globals size) s in
  let* (pack : unit Rules.rule_pack) = Rules.rules s in
  let arity : int = pack.Rules.diagram_arity s in
  let vars : Value.t list = List.init arity (fun (i : int) -> Value.var (size + i)) in
  let* body = Rules.open_closure (ev globals) dclo vars in
  let* d' = quote globals (size + arity) body in
  let core : Term.t = build (s', d') in
  Ok
    (u
    |> Option.fold ~none:core ~some:(fun (l : Level.t) -> Term.Ann (core, Term.Univ l)))

and quote_leg (globals : Global.t) (size : int) (lg : Value.vleg) :
    (Term.leg, Error.t) result =
  let arity : int = List.length lg.Value.vl_binders in
  let vars : Value.t list = List.init arity (fun (i : int) -> Value.var (size + i)) in
  let* body = Rules.open_closure (ev globals) lg.Value.vl_clo vars in
  let* b = quote globals (size + arity) body in
  Ok { Term.l_binders = lg.Value.vl_binders; l_body = b }

and quote_addr (globals : Global.t) (size : int) (a : Value.vaddr) :
    (Term.addr, Error.t) result =
  match a with
  | Value.VAPt (q, v) ->
      Result.map (fun (t : Term.t) -> Term.APt (q, t)) (quote globals size v)
  | Value.VALeg k -> Ok (Term.ALeg k)
  | Value.VACtor c -> Ok (Term.ACtor c)

and quote_neutral (globals : Global.t) (size : int) (h : Value.head)
    (sp : Value.spine list) : (Term.t, Error.t) result =
  let head : Term.t =
    match h with
    | Value.HLocal lvl -> Term.Var (size - lvl - 1)
    | Value.HGlobal n -> Term.Global n
  in
  List.fold_left
    (fun (acc : (Term.t, Error.t) result) (fr : Value.spine) ->
      let* t = acc in
      match fr with
      | Value.SOut (s, addr) ->
          let* s' = Rules.map_shape (quote globals size) s in
          let* a' = quote_addr globals size addr in
          Ok (Term.Out (s', a', t))
      | Value.SElim se ->
          let* s' = Rules.map_shape (quote globals size) se.Value.s_shape in
          Ok
            (Term.Elim
               {
                 Term.e_shape = s';
                 e_scrut = t;
                 e_scrut_q = se.Value.s_scrut_q;
                 e_motive = se.Value.s_motive;
                 e_branches = se.Value.s_branches;
               }))
    (Ok head) (List.rev sp)
