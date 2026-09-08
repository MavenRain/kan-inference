(** Typed conversion, plan section 5.  Three steps in one fixed order.

    Step one is proof irrelevance:  when the type of the type is the
    proposition universe, any two inhabitants convert.  A universe is
    never a proposition, because the type of [Univ l] is [Univ (l + 1)]
    and a successor is not zero, so this step cannot swallow a type
    comparison.

    Step two is eta by the type.  The type decides the rule, not the two
    values, so an eta rule fires on a neutral as readily as on a
    canonical value.  The rule itself comes from the pack of the shape,
    so this file names no shape.

    Step three is structural.  Both sides are already in weak head normal
    form, so the comparison reads the head:  a universe by level, a
    former by shape and diagram, an injection by address and arguments, a
    section by legs, and a neutral by head and spine.  A spine argument
    is compared at the type the head's type gives it, which is what
    carries proof irrelevance into an argument position.

    Conversion holds no state.  It reads the checker through the [ops]
    record of rules.ml, so lib/ holds no cell of state (SB-D12). *)

let ( let* ) = Result.bind

(** [Option.fold] is eager in [~none], so a branch that must not run
    until the option is known empty rides a thunk (one tail call). *)
let opt_else (o : 'a option) (dflt : unit -> 'b) (f : 'a -> 'b) : 'b =
  Option.fold ~none:dflt ~some:(fun (x : 'a) () -> f x) o ()

(** The first attempt that applies decides;  an attempt that does not
    apply answers [None] and costs nothing. *)
let first_of (xs : (unit -> (bool, Error.t) result option) list) : (bool, Error.t) result
    =
  List.fold_left
    (fun (acc : (bool, Error.t) result option)
         (f : unit -> (bool, Error.t) result option) ->
      opt_else acc (fun () -> f ()) (fun (r : (bool, Error.t) result) -> Some r))
    None xs
  |> Option.value ~default:(Ok false)

(** Which former an eta rule is read from. *)
type side =
  | Right
  | Left

(** A local bound only so a comparison can go under a binder carries this
    type (SB-D26).  It is a universe, so a neutral headed by such a local
    never opens a typed spine walk:  the comparison there weakens to the
    structural one, and never to a stronger one. *)
let placeholder : Value.t = Value.VUniv Level.zero

let expansion_of (pack : 'c Rules.rule_pack) (sd : side) : 'c Rules.expansion option =
  match sd with
  | Right -> if pack.Rules.eta.Rules.eta_ran then pack.Rules.expand_ran else None
  | Left -> if pack.Rules.eta.Rules.eta_lan then pack.Rules.expand_lan else None

let rec conv (ops : 'c Rules.ops) (ctx : 'c) ~(ty : Value.t) (a : Value.t) (b : Value.t)
    : (bool, Error.t) result =
  (* SB-M2 site *)
  match () with
  | () when is_prop ops ctx ty -> Ok true
  | () ->
      let* w = ops.Rules.o_whnf ctx ty in
      let* sub = subsingleton_step ops ctx w in
      if sub then Ok true
      else
        let* expanded = eta_step ops ctx w a b in
        opt_else expanded
          (fun () -> structural ops ctx a b)
          (fun (r : bool) -> Ok r)

(** Rule 1, proof irrelevance.  The probe reads back the type and asks
    the checker for its universe.  A type that does not read back is not
    a proposition as far as this rule is concerned, so a failure here
    weakens conversion to the other two steps and never strengthens
    it. *)
and is_prop (ops : 'c Rules.ops) (ctx : 'c) (ty : Value.t) : bool =
  ops.Rules.o_quote ctx ty
  |> Fun.flip Result.bind (fun (t : Term.t) -> ops.Rules.o_infer_univ ctx t)
  |> Result.to_option
  |> Option.fold ~none:false ~some:(fun (l : Level.t) -> Level.equal l Level.zero)

(** M1 Stage H, brief 3.5:  the second half of step one, named rule 2 of
    SPEC.md section 5.  The pack restricts this comparison to Prop
    families that pass the criterion of brief 3.4.  Erased fields alone
    do not make inhabitants of a Type family definitionally equal.  The
    criterion is read through the pack, so this file holds no shape name
    and no family lookup of its own (SH-D1).  A shape whose pack cannot
    answer weakens the comparison to the other steps and never
    strengthens it, exactly as the probe of rule 1 does. *)
and subsingleton_step (ops : 'c Rules.ops) (ctx : 'c) (w : Value.t) :
    (bool, Error.t) result =
  opt_else (Value.as_lan w)
    (fun () -> Ok false)
    (fun ((s : Value.t Shape.t), (_d : Value.closure), (_u : Level.t option)) ->
      let* (pack : 'c Rules.rule_pack) = Rules.rules s in
      pack.Rules.subsingleton ops ctx s)

(** Rule 2, eta by the type.  [None] means the type carries no eta rule
    and the comparison goes on to step three.  The type arrives in weak
    head normal form, because step one already forced it. *)
and eta_step (ops : 'c Rules.ops) (ctx : 'c) (w : Value.t) (a : Value.t) (b : Value.t) :
    (bool option, Error.t) result =
  let former : (side * Value.t Shape.t * Value.closure) option =
    Value.as_ran w
    |> Option.map
         (fun ((s : Value.t Shape.t), (d : Value.closure), (_u : Level.t option)) ->
           (Right, s, d))
    |> Option.fold
         ~none:
           (Value.as_lan w
           |> Option.map
                (fun
                  ((s : Value.t Shape.t), (d : Value.closure), (_u : Level.t option)) ->
                  (Left, s, d)))
         ~some:Option.some
  in
  opt_else former
    (fun () -> Ok None)
    (fun ((sd : side), (s : Value.t Shape.t), (d : Value.closure)) ->
      let* (pack : 'c Rules.rule_pack) = Rules.rules s in
      opt_else (expansion_of pack sd)
        (fun () -> Ok None)
        (fun (f : 'c Rules.expansion) ->
          Result.map Option.some (f ops ctx s d a b)))

(** A comparison with no type to guide it.  The proposition universe is
    not a proposition and is not a former, so both earlier steps stand
    down and only the structural one runs. *)
and conv_type (ops : 'c Rules.ops) (ctx : 'c) (a : Value.t) (b : Value.t) :
    (bool, Error.t) result =
  conv ops ctx ~ty:placeholder a b

(** Rule 3.  Both sides are in weak head normal form here. *)
and structural (ops : 'c Rules.ops) (ctx : 'c) (a : Value.t) (b : Value.t) :
    (bool, Error.t) result =
  let* wa = ops.Rules.o_whnf ctx a in
  let* wb = ops.Rules.o_whnf ctx b in
  first_of
    [
      (fun () -> univ_case wa wb);
      (fun () -> lit_case wa wb);
      (fun () -> former_case ops ctx Right wa wb);
      (fun () -> former_case ops ctx Left wa wb);
      (fun () -> in_case ops ctx wa wb);
      (fun () -> sec_case ops ctx wa wb);
      (fun () -> neutral_case ops ctx wa wb);
    ]

and univ_case (a : Value.t) (b : Value.t) : (bool, Error.t) result option =
  Option.bind (Value.as_univ a) (fun (l1 : Level.t) ->
      Option.map (fun (l2 : Level.t) -> Ok (Level.equal l1 l2)) (Value.as_univ b))

and lit_case (a : Value.t) (b : Value.t) : (bool, Error.t) result option =
  Option.bind (Value.as_lit a) (fun (x : Literal.t) ->
      Option.map (fun (y : Literal.t) -> Ok (Literal.equal x y)) (Value.as_lit b))

(** Two formers convert when they are the same former of the same shape,
    their carried universes agree by the pack (SB-D7) and their diagrams
    convert. *)
and former_case (ops : 'c Rules.ops) (ctx : 'c) (sd : side) (a : Value.t) (b : Value.t) :
    (bool, Error.t) result option =
  let view : Value.t -> (Value.t Shape.t * Value.closure * Level.t option) option =
    match sd with
    | Right -> Value.as_ran
    | Left -> Value.as_lan
  in
  Option.bind (view a)
    (fun
      ((s1 : Value.t Shape.t), (d1 : Value.closure), (u1 : Level.t option)) ->
      Option.map
        (fun ((s2 : Value.t Shape.t), (d2 : Value.closure), (u2 : Level.t option)) ->
          let* (pack : 'c Rules.rule_pack) = Rules.rules s1 in
          let* same = Rules.shape_eq (conv_type ops ctx) s1 s2 in
          match () with
          | () when not same -> Ok false
          | () when not (pack.Rules.ann_lvl_eq s1 u1 u2) -> Ok false
          | () -> pack.Rules.conv_diagram ops ctx s1 d1 d2)
        (view b))

and in_case (ops : 'c Rules.ops) (ctx : 'c) (a : Value.t) (b : Value.t) :
    (bool, Error.t) result option =
  Option.bind (Value.as_in a)
    (fun
      ((s1 : Value.t Shape.t), (a1 : Value.vaddr), (args1 : Value.t list)) ->
      Option.map
        (fun ((s2 : Value.t Shape.t), (a2 : Value.vaddr), (args2 : Value.t list)) ->
          let* same = Rules.shape_eq (conv_type ops ctx) s1 s2 in
          let* addr = conv_addr ops ctx None a1 a2 in
          match () with
          | () when not same -> Ok false
          | () when not addr -> Ok false
          | () -> conv_list ops ctx args1 args2)
        (Value.as_in b))

and sec_case (ops : 'c Rules.ops) (ctx : 'c) (a : Value.t) (b : Value.t) :
    (bool, Error.t) result option =
  Option.bind (Value.as_sec a)
    (fun ((s1 : Value.t Shape.t), (legs1 : Value.vleg list)) ->
      Option.map
        (fun ((s2 : Value.t Shape.t), (legs2 : Value.vleg list)) ->
          let* same = Rules.shape_eq (conv_type ops ctx) s1 s2 in
          match () with
          | () when not same -> Ok false
          | () -> conv_legs ops ctx legs1 legs2)
        (Value.as_sec b))

and neutral_case (ops : 'c Rules.ops) (ctx : 'c) (a : Value.t) (b : Value.t) :
    (bool, Error.t) result option =
  Option.bind (Value.as_neutral a)
    (fun ((h1 : Value.head), (sp1 : Value.spine list)) ->
      Option.map
        (fun ((h2 : Value.head), (sp2 : Value.spine list)) ->
          match () with
          | () when not (Value.head_equal h1 h2) -> Ok false
          | () ->
              let* hty = ops.Rules.o_head_ty ctx h1 in
              conv_spine ops ctx hty (List.rev sp1) (List.rev sp2))
        (Value.as_neutral b))

(** The spine, oldest frame first, walked at the type the head carries.
    An address argument is compared at the type the pack gives it;  when
    the pack cannot say, the argument is compared without a type and the
    walk goes on at the placeholder, so the rest of the spine is compared
    structurally. *)
and conv_spine (ops : 'c Rules.ops) (ctx : 'c) (hty : Value.t) (sp1 : Value.spine list)
    (sp2 : Value.spine list) : (bool, Error.t) result =
  match (sp1, sp2) with
  | [], [] -> Ok true
  | Value.SOut (s1, a1) :: r1, Value.SOut (s2, a2) :: r2 ->
      let* same = Rules.shape_eq (conv_type ops ctx) s1 s2 in
      let* step = spine_step ops ctx hty s1 a1 in
      let arg_ty : Value.t option = Option.bind step fst in
      let next : Value.t =
        step |> Option.fold ~none:placeholder ~some:snd
      in
      let* addr = conv_addr ops ctx arg_ty a1 a2 in
      (match () with
      | () when not same -> Ok false
      | () when not addr -> Ok false
      | () -> conv_spine ops ctx next r1 r2)
  | Value.SElim m1 :: r1, Value.SElim m2 :: r2 ->
      let* eq = conv_stuck ops ctx m1 m2 in
      if eq then conv_spine ops ctx placeholder r1 r2 else Ok false
  | Value.SOut (_, _) :: _, Value.SElim _ :: _ -> Ok false
  | Value.SElim _ :: _, Value.SOut (_, _) :: _ -> Ok false
  | [], _f :: _ -> Ok false
  | _f :: _, [] -> Ok false

(** One typed step of the walk.  [None] means the head's type is not a
    right former of this shape, so no type is available. *)
and spine_step (ops : 'c Rules.ops) (ctx : 'c) (hty : Value.t) (s : Value.t Shape.t)
    (addr : Value.vaddr) : ((Value.t option * Value.t) option, Error.t) result =
  let* w = ops.Rules.o_whnf ctx hty in
  opt_else (Value.as_ran w)
    (fun () -> Ok None)
    (fun
      ((_s : Value.t Shape.t), (d : Value.closure), (_u : Level.t option)) ->
      let* (pack : 'c Rules.rule_pack) = Rules.rules s in
      pack.Rules.spine_ty ops ctx s d addr)

and conv_addr (ops : 'c Rules.ops) (ctx : 'c) (arg_ty : Value.t option)
    (a1 : Value.vaddr) (a2 : Value.vaddr) : (bool, Error.t) result =
  first_of
    [
      (fun () ->
        Option.bind (Value.as_pt a1) (fun ((_q1 : Quantity.t), (v1 : Value.t)) ->
            Option.map
              (fun ((_q2 : Quantity.t), (v2 : Value.t)) ->
                opt_else arg_ty
                  (fun () -> conv_type ops ctx v1 v2)
                  (fun (t : Value.t) -> conv ops ctx ~ty:t v1 v2))
              (Value.as_pt a2)));
      (fun () ->
        Option.bind (Value.as_leg a1) (fun (k1 : int) ->
            Option.map (fun (k2 : int) -> Ok (Int.equal k1 k2)) (Value.as_leg a2)));
      (fun () ->
        Option.bind (Value.as_ctor a1) (fun (c1 : string) ->
            Option.map (fun (c2 : string) -> Ok (String.equal c1 c2)) (Value.as_ctor a2)));
    ]

and conv_list (ops : 'c Rules.ops) (ctx : 'c) (xs : Value.t list) (ys : Value.t list) :
    (bool, Error.t) result =
  Rules.payload_eq (conv_type ops ctx) xs ys

and conv_legs (ops : 'c Rules.ops) (ctx : 'c) (xs : Value.vleg list)
    (ys : Value.vleg list) : (bool, Error.t) result =
  Rules.payload_eq
    (fun (x : Value.vleg) (y : Value.vleg) ->
      conv_closures ops ctx (List.length x.Value.vl_binders) x.Value.vl_clo
        (List.length y.Value.vl_binders) y.Value.vl_clo)
    xs ys

(** Both semantic legs and frozen branches open in declaration order
    under the same fresh variables and compare in the grown context. *)
and conv_closures (ops : 'c Rules.ops) (ctx : 'c) (arity : int) (x : Value.closure)
    (other_arity : int) (y : Value.closure) : (bool, Error.t) result =
  if not (Int.equal arity other_arity) then Ok false
  else
    let size = ops.Rules.o_size ctx in
    let fresh = List.init arity (fun i -> Value.var (size + arity - 1 - i)) in
    let ev = ops.Rules.o_ev ctx in
    let* v1 = ev.Rules.ev_eval (fresh @ x.Value.env) x.Value.body in
    let* v2 = ev.Rules.ev_eval (fresh @ y.Value.env) y.Value.body in
    conv_type ops (grow ops ctx arity) v1 v2

(** Two frozen eliminations, tot's [conv_stuck_match]
    (kan-lang-tot-pin/lib/eval.ml:401) with the address of a branch in
    place of a constructor name.  [m_ind] is ignored, exactly as tot
    ignores it:  a materialized constant motive writes [None] where an
    explicit one writes a name, and those two still convert. *)
and conv_stuck (ops : 'c Rules.ops) (ctx : 'c) (m1 : Value.stuck_elim)
    (m2 : Value.stuck_elim) : (bool, Error.t) result =
  let* same = Rules.shape_eq (conv_type ops ctx) m1.Value.s_shape m2.Value.s_shape in
  let* mot = conv_motive ops ctx m1 m2 in
  match () with
  | () when not same -> Ok false
  | () when not (Quantity.equal m1.Value.s_scrut_q m2.Value.s_scrut_q) -> Ok false
  | () when not mot -> Ok false
  | () ->
      conv_branches ops ctx m1.Value.s_env m2.Value.s_env m1.Value.s_branches
        m2.Value.s_branches

and conv_motive (ops : 'c Rules.ops) (ctx : 'c) (m1 : Value.stuck_elim)
    (m2 : Value.stuck_elim) : (bool, Error.t) result =
  m1.Value.s_motive
  |> Option.fold
       ~none:(Ok (Option.is_none m2.Value.s_motive))
       ~some:(fun (mo1 : Term.motive) ->
         m2.Value.s_motive
         |> Option.fold ~none:(Ok false) ~some:(fun (mo2 : Term.motive) ->
                let n1 : int = List.length mo1.Term.m_idx in
                let n2 : int = List.length mo2.Term.m_idx in
                match () with
                | () when not (Int.equal n1 n2) -> Ok false
                | () ->
                    let size : int = ops.Rules.o_size ctx in
                    let idx : Value.t list =
                      List.init n1 (fun (i : int) -> Value.var (size + n1 - 1 - i))
                    in
                    let self : Value.t = Value.var (size + n1) in
                    let ev : Rules.evaluator = ops.Rules.o_ev ctx in
                    let* v1 =
                      ev.Rules.ev_eval (self :: (idx @ m1.Value.s_env)) mo1.Term.m_body
                    in
                    let* v2 =
                      ev.Rules.ev_eval (self :: (idx @ m2.Value.s_env)) mo2.Term.m_body
                    in
                    conv_type ops (grow ops ctx (n1 + 1)) v1 v2))

and conv_branches (ops : 'c Rules.ops) (ctx : 'c) (env1 : Value.t list)
    (env2 : Value.t list) (bs1 : (Term.addr * Term.leg) list)
    (bs2 : (Term.addr * Term.leg) list) : (bool, Error.t) result =
  Rules.payload_eq
    (fun (a1, l1) (a2, l2) ->
      let* addr = branch_addr ops ctx env1 env2 a1 a2 in
      if not addr then Ok false
      else
        conv_closures ops ctx (List.length l1.Term.l_binders)
          { Value.env = env1; body = l1.Term.l_body }
          (List.length l2.Term.l_binders) { Value.env = env2; body = l2.Term.l_body })
    bs1 bs2

(** A branch address is a term, so it is compared under the environment
    the elimination froze. *)
and branch_addr (ops : 'c Rules.ops) (ctx : 'c) (env1 : Value.t list)
    (env2 : Value.t list) (a1 : Term.addr) (a2 : Term.addr) : (bool, Error.t) result =
  let ev : Rules.evaluator = ops.Rules.o_ev ctx in
  first_of
    [
      (fun () ->
        Option.bind (Term.as_apt a1) (fun ((_q1 : Quantity.t), (t1 : Term.t)) ->
            Option.map
              (fun ((_q2 : Quantity.t), (t2 : Term.t)) ->
                let* v1 = ev.Rules.ev_eval env1 t1 in
                let* v2 = ev.Rules.ev_eval env2 t2 in
                conv_type ops ctx v1 v2)
              (Term.as_apt a2)));
      (fun () ->
        Option.bind (Term.as_aleg a1) (fun (k1 : int) ->
            Option.map (fun (k2 : int) -> Ok (Int.equal k1 k2)) (Term.as_aleg a2)));
      (* M1 Stage H, brief 3.5:  a branch of the recursive shape is keyed
         by a constructor address, so two frozen eliminations compare
         their branch bodies under the binders of the same constructor. *)
      (fun () ->
        Option.bind (Term.as_actor a1) (fun (c1 : string) ->
            Option.map (fun (c2 : string) -> Ok (String.equal c1 c2)) (Term.as_actor a2)));
    ]

(** Grow the context by binders a comparison opens (SB-D26). *)
and grow (ops : 'c Rules.ops) (ctx : 'c) (n : int) : 'c =
  List.fold_left
    (fun (c : 'c) (_i : int) -> ops.Rules.o_bind "_" Quantity.Many placeholder c)
    ctx
    (List.init n (fun (i : int) -> i))
