(** The structural order and the totality certificate, M1 Stage I, brief
    3.1 and 3.2 (M1-PLAN.md:110-113).  The order is subterm only,
    syntactic and checked, never inferred:  D-M1-4
    (kanon-m0/RATIFICATIONS.md:62) excludes a sized order and a
    lexicographic order, and no part of this file infers one.

    This file is a new kernel file and not a carried one, so each
    function cites the pin line it mirrors (M1-PLAN.md:49, SI-D2).  The
    pin is kan-lang-tot-pin at 8cf0b8b and its line numbers are fixed.
    The arm mirrored here is kan-lang-tot-pin/lib/totality.ml:20-196.

    Lambda, application and match become Sec, Out and Elim respectively;
    application shapes travel beside spine arguments.  Shape access uses
    Shape.payload, Shape.point_dom and Rules.as_vpi (SA-D5).  Family
    access stays in Rules.mu_family.  Rules.at gives total indexing.
    This file counts toward TRUSTED-LINES (SI-D15). *)

let ( let* ) = Result.bind

(** The rule, a single-constructor type on purpose
    (kan-lang-tot-pin/lib/totality.ml:20).  Ruling R1 ships one rule at
    M1, so an M2 admission rule re-enters by a compile error at every
    exhaustive match on this type and never by a driver flag. *)
type rule = Structural

(** The status of one binder, newest first beside de Bruijn use
    (kan-lang-tot-pin/lib/totality.ml:23-26). *)
type status =
  | Principal  (** the candidate formal itself *)
  | Smaller  (** bound by a branch leg over a Principal or Smaller variable *)
  | Other

(** One step of the chain the certificate carries (M1-PLAN.md:111):  the
    de Bruijn index of the eliminated scrutinee, read in the scope of
    that elimination, and the constructor address of the branch the step
    entered.  [st_ctor] is [None] at a leg address, which is the
    collection elimination and not a constructor
    (term.ml:79-84). *)
type step = {
  st_scrut : int;
  st_ctor : string option;
}

(** One guarded call:  the member it calls and the chain of eliminations
    that reaches it, innermost step first. *)
type call = {
  cl_callee : string;
  cl_chain : step list;
}

(** The certificate rows of one member of the definition group. *)
type row = {
  rw_member : string;
  rw_calls : call list;
}

(** The certificate, the record M1-PLAN.md:111 names:  the recursive
    argument index, and for every call the chain of eliminated
    scrutinees with the constructor address at each step.  It is a value
    the order returns and [Totality.guard] reads (SI-D3);  it is never a
    flag on a driver and never an assignable cell.

    [o_group] is the definition group of brief 3.2:  one order over the
    sum of the arguments, one argument position for every member, and
    the direct case is the group of one (SI-D7). *)
type t = {
  o_group : string list;
  o_arg : int;
  o_rows : row list;
}

let member (group : string list) (n : string) : bool =
  List.exists (String.equal n) group

(** The lambda view.  The pin matches [Term.Lam]
    (kan-lang-tot-pin/lib/totality.ml:31);  kanon writes a lambda as a
    section at the point shape with one leg and one binder
    (surface/elab.ml:515-517, rules.ml:446-475), so the view asks
    [Rules.as_vpi] for the point shape and names no shape. *)
let as_lam (t : Term.t) : (Term.t Shape.t * Term.leg) option =
  match t with
  | Term.Sec (s, legs) ->
      Option.bind
        (Option.bind (Rules.as_vpi s)
           (fun ((_q : Quantity.t), (_x : string), (_dom : Term.t)) ->
             Rules.one_of legs))
        (fun (lg : Term.leg) ->
          Rules.one_of lg.Term.l_binders
          |> Option.map (fun ((_bq : Quantity.t), (_bx : string)) -> (s, lg)))
  | Term.Var _ | Term.Univ _ | Term.Lit _ | Term.Auto | Term.Global _
  | Term.Lan (_, _)
  | Term.Ran (_, _)
  | Term.In (_, _, _)
  | Term.Elim _
  | Term.Out (_, _, _)
  | Term.Let (_, _, _, _)
  | Term.Ann (_, _) ->
      None

(** The elimination view, used by the translation of brief 3.4. *)
let as_elim (t : Term.t) : Term.elim option =
  match t with
  | Term.Elim e -> Some e
  | Term.Var _ | Term.Univ _ | Term.Lit _ | Term.Auto | Term.Global _
  | Term.Lan (_, _)
  | Term.Ran (_, _)
  | Term.In (_, _, _)
  | Term.Sec (_, _)
  | Term.Out (_, _, _)
  | Term.Let (_, _, _, _)
  | Term.Ann (_, _) ->
      None

(** The variable view, so the walk reads a scrutinee once. *)
let as_var (t : Term.t) : int option =
  match t with
  | Term.Var ix -> Some ix
  | Term.Univ _ | Term.Lit _ | Term.Auto | Term.Global _
  | Term.Lan (_, _)
  | Term.Ran (_, _)
  | Term.In (_, _, _)
  | Term.Elim _
  | Term.Sec (_, _)
  | Term.Out (_, _, _)
  | Term.Let (_, _, _, _)
  | Term.Ann (_, _) ->
      None

(** Count the leading lambdas and answer the inner body
    (kan-lang-tot-pin/lib/totality.ml:29). *)
let rec peel (n : int) (t : Term.t) : int * Term.t =
  as_lam t
  |> Option.fold ~none:(n, t) ~some:(fun ((_s : Term.t Shape.t), (lg : Term.leg)) ->
         peel (n + 1) lg.Term.l_body)

(** The same walk, keeping the shape and the binders of every formal so
    that the translation of brief 3.4 rebuilds the definition it
    peeled.  The answer is outermost formal first. *)
let rec unwrap (acc : (Term.t Shape.t * Term.leg) list) (t : Term.t) :
    (Term.t Shape.t * Term.leg) list * Term.t =
  as_lam t
  |> Option.fold ~none:(List.rev acc, t)
       ~some:(fun ((s : Term.t Shape.t), (lg : Term.leg)) ->
         unwrap ((s, lg) :: acc) lg.Term.l_body)

(** The inverse of [unwrap]:  the formals go back on, outermost last, so
    the rebuilt term holds the binders the body was peeled from. *)
let rewrap (ws : (Term.t Shape.t * Term.leg) list) (inner : Term.t) : Term.t =
  List.fold_left
    (fun (b : Term.t) (((s : Term.t Shape.t), (lg : Term.leg)) : Term.t Shape.t * Term.leg) ->
      Term.Sec (s, [ { lg with Term.l_body = b } ]))
    inner (List.rev ws)

(** Collect an application spine:  the head, the arguments oldest first,
    and the point shapes the chain carries
    (kan-lang-tot-pin/lib/totality.ml:41).  kanon writes an application
    as [Out] at the point address (surface/elab.ml:469, rules.ml:506),
    so an [Out] at any other address is a section projection, is not an
    application, and stops the walk at itself. *)
let rec spine (t : Term.t) (args : Term.t list) (shapes : Term.t Shape.t list) :
    Term.t * Term.t list * Term.t Shape.t list =
  match t with
  | Term.Out (s, a, head) ->
      Term.as_apt a
      |> Option.fold ~none:(t, args, shapes)
           ~some:(fun ((_q : Quantity.t), (arg : Term.t)) ->
             spine head (arg :: args) (s :: shapes))
  | Term.Var _ | Term.Univ _ | Term.Lit _ | Term.Auto | Term.Global _
  | Term.Lan (_, _)
  | Term.Ran (_, _)
  | Term.In (_, _, _)
  | Term.Elim _
  | Term.Sec (_, _)
  | Term.Let (_, _, _, _)
  | Term.Ann (_, _) ->
      (t, args, shapes)

(** Does any member of [group] occur in [t] as a [Term.Global]
    (kan-lang-tot-pin/lib/totality.ml:57)?  Structural, total and
    exhaustive over the thirteen arms of term.ml:46-59, so a body that
    only carries the keyword is told from one that calls itself, and the
    guard answers [Ok None] for the first (brief 3.3). *)
let mentions (group : string list) (t : Term.t) : bool =
  Term.exists_name ~include_families:false group t

(** Read one binder status through a total combinator
    (kan-lang-tot-pin/lib/totality.ml:77).  The spelling the pin uses is
    the one dev/house.sh:23 refuses, so the same total read is
    [Rules.at] (rules.ml:181). *)
let status_at (st : status list) (ix : int) : status option = Rules.at ix st

(** The two answers of the walk, which carries the certificate rows of
    the calls it admits and answers [None] for a call it refuses. *)
let ok_both (a : call list option) (b : call list option) : call list option =
  Option.bind a (fun (xs : call list) ->
      Option.map (fun (ys : call list) -> xs @ ys) b)

let ok_all (xs : call list option list) : call list option =
  List.fold_left ok_both (Some []) xs

(** Push one binder status per binder of a leg, newest first. *)
let under (s : status) (bs : (Quantity.t * string) list) (st : status list) : status list =
  List.fold_left
    (fun (acc : status list) ((_b : Quantity.t * string)) -> s :: acc)
    st bs

(** The diagram of a former at the point shape stands under the binder
    the shape declares (surface/elab.ml:520-526);  at every other shape
    it stands under none, so the depth is read from [Shape.point_dom]
    (shape.ml:34) and no shape name is spelled. *)
let under_point (s : Term.t Shape.t) (st : status list) : status list =
  Shape.point_dom s
  |> Option.fold ~none:st ~some:(fun (_dom : Term.t) -> Other :: st)

(** Does the candidate position [k] guard every call into the group
    (kan-lang-tot-pin/lib/totality.ml:80)?  The answer carries the
    certificate rows of the calls it admits, so the one walk that checks
    the order also computes the record of M1-PLAN.md:111. *)
let passes ~(rule : rule) ~(group : string list) (k : int) (formals : int)
    (body : Term.t) : call list option =
  let smaller_at (st : status list) (ix : int) : bool =
    status_at st ix
    |> Option.fold ~none:false ~some:(fun (s : status) ->
           match s with
           | Smaller -> true
           | Principal | Other -> false)
  in
  let principal_or_smaller_at (st : status list) (ix : int) : bool =
    status_at st ix
    |> Option.fold ~none:false ~some:(fun (s : status) ->
           match s with
           | Principal | Smaller -> true
           | Other -> false)
  in
  (* The argument at [k] of a call into the group must be a variable of
     status [Smaller] (kan-lang-tot-pin/lib/totality.ml:96-116). *)
  let guarded_call (st : status list) (args : Term.t list) : bool =
    Rules.at k args
    |> Option.fold ~none:false ~some:(fun (a : Term.t) ->
           match a with
           | Term.Var ix -> smaller_at st ix
           | Term.Out (_, _, _) ->
               (* Ruling R1 and SI-D5, byte for byte the pin rule at
                  kan-lang-tot-pin/lib/totality.ml:102-109:  a call whose
                  argument [k] is an application is never guarded, so no
                  accessibility clause enters at M1.  The match on the
                  rule stays, so an M2 admission rule re-enters here by a
                  compile error. *)
               (match rule with
               | Structural -> false)
           | Term.Univ _ | Term.Lit _ | Term.Auto | Term.Global _
           | Term.Lan (_, _)
           | Term.Ran (_, _)
           | Term.In (_, _, _)
           | Term.Elim _
           | Term.Sec (_, _)
           | Term.Let (_, _, _, _)
           | Term.Ann (_, _) ->
               false)
  in
  let rec ok (st : status list) (chain : step list) (t : Term.t) : call list option =
    match t with
    | Term.Var _ -> Some []
    | Term.Univ _ -> Some []
    | Term.Lit _ -> Some []
    | Term.Auto -> Some []
    (* A bare occurrence of a member of the group always fails
       (kan-lang-tot-pin/lib/totality.ml:124-125). *)
    | Term.Global g -> if member group g then None else Some []
    | Term.Lan (s, d) -> ok_all [ shape_ok st chain s; ok (under_point s st) chain d ]
    | Term.Ran (s, d) -> ok_all [ shape_ok st chain s; ok (under_point s st) chain d ]
    | Term.In (s, a, args) ->
        ok_all
          (shape_ok st chain s :: addr_ok st chain a :: List.map (ok st chain) args)
    | Term.Sec (s, legs) ->
        ok_all (shape_ok st chain s :: List.map (leg_ok st chain) legs)
    | Term.Out (_, _, _) -> spine_ok st chain t
    | Term.Elim e -> elim_ok st chain e
    | Term.Let (_x, ty, def, b) ->
        ok_all [ ok st chain ty; ok st chain def; ok (Other :: st) chain b ]
    | Term.Ann (tm, ty) -> ok_all [ ok st chain tm; ok st chain ty ]
  and shape_ok (st : status list) (chain : step list) (s : Term.t Shape.t) :
      call list option =
    ok_all (List.map (ok st chain) (Shape.payload s))
  and addr_ok (st : status list) (chain : step list) (a : Term.addr) : call list option =
    Term.as_apt a
    |> Option.fold ~none:(Some [])
         ~some:(fun ((_q : Quantity.t), (arg : Term.t)) -> ok st chain arg)
  and leg_ok (st : status list) (chain : step list) (lg : Term.leg) : call list option =
    ok (under Other lg.Term.l_binders st) chain lg.Term.l_body
  and spine_ok (st : status list) (chain : step list) (t : Term.t) : call list option =
    let hd, args, shapes = spine t [] [] in
    let head_ok : call list option =
      match hd with
      | Term.Global g -> (
          (* The head of the spine is a call into the group, a call out
             of it, or the group name unguarded at [k]
             (kan-lang-tot-pin/lib/totality.ml:128-131). *)
          match () with
          | () when member group g && guarded_call st args ->
              Some [ { cl_callee = g; cl_chain = chain } ]
          | () when member group g -> None
          | () -> Some [])
      | Term.Var _ | Term.Univ _ | Term.Lit _ | Term.Auto -> Some []
      | Term.Out (s2, a2, h2) ->
          (* The spine stopped at an [Out] whose address is not a point,
             which is a section projection (rules.ml:506) and not an
             application, so its three parts are read here and the walk
             never re-enters this node. *)
          ok_all [ shape_ok st chain s2; addr_ok st chain a2; ok st chain h2 ]
      | Term.Lan (_, _)
      | Term.Ran (_, _)
      | Term.In (_, _, _)
      | Term.Elim _
      | Term.Sec (_, _)
      | Term.Let (_, _, _, _)
      | Term.Ann (_, _) ->
          ok st chain hd
    in
    ok_all
      (head_ok :: (List.map (shape_ok st chain) shapes @ List.map (ok st chain) args))
  and elim_ok (st : status list) (chain : step list) (e : Term.elim) : call list option =
    (* The Elim arm, which is the pin Match arm at
       kan-lang-tot-pin/lib/totality.ml:146-176 read at kanon's
       elimination (term.ml:31-37, brief 3.1). *)
    let sv = as_var e.Term.e_scrut in
    let scrut_special =
      sv
      |> Option.fold ~none:false ~some:(fun (ix : int) -> principal_or_smaller_at st ix)
    in
    let binder_status = if scrut_special then Smaller else Other in
    let chain_at (a : Term.addr) : step list =
      sv
      |> Option.fold ~none:chain ~some:(fun (ix : int) ->
             match () with
             | () when scrut_special -> { st_scrut = ix; st_ctor = Term.as_actor a } :: chain
             | () -> chain)
    in
    let motive_ok : call list option =
      e.Term.e_motive
      |> Option.fold ~none:(Some []) ~some:(fun (mo : Term.motive) ->
             let st_m =
               List.fold_left
                 (fun (acc : status list) (_y : string) -> Other :: acc)
                 (Other :: st) mo.Term.m_idx
             in
             ok st_m chain mo.Term.m_body)
    in
    let branch_ok (((a : Term.addr), (lg : Term.leg)) : Term.addr * Term.leg) :
        call list option =
      ok_all
        [
          addr_ok st chain a;
          ok (under binder_status lg.Term.l_binders st) (chain_at a) lg.Term.l_body;
        ]
    in
    ok_all
      (ok st chain e.Term.e_scrut
      :: shape_ok st chain e.Term.e_shape
      :: motive_ok
      :: List.map branch_ok e.Term.e_branches)
  in
  (* The seed marks the candidate formal [Principal] and every other
     formal [Other] (kan-lang-tot-pin/lib/totality.ml:178-180). *)
  let seed : status list =
    List.init formals (fun (ix : int) ->
        if Int.equal ix (formals - 1 - k) then Principal else Other)
  in
  ok seed [] body

(** The refusal of SI-D6:  the arm is [Error.Termination] (error.ml:36)
    and the message is the pin's at
    kan-lang-tot-pin/lib/error.ml:185.  It names the first member of the
    group, which for the direct case is the definition itself, exactly
    as the pin names [recname]
    (kan-lang-tot-pin/lib/totality.ml:192).  An empty group never
    reaches here, because no term mentions it. *)
let refusal (members : (string * Term.t) list) : Error.t =
  List.fold_left
    (fun (acc : string option) (((n : string), (_b : Term.t)) : string * Term.t) ->
      Option.fold ~none:(Some n) ~some:Option.some acc)
    None members
  |> Option.value ~default:""
  |> fun (n : string) -> Error.Termination n

(** One order over the sum of the arguments of the whole definition
    group, brief 3.2 and SI-D7 (M1-PLAN.md:113):  one argument position
    answers for every member, so a call into a sibling must decrease at
    the same position as a call into the member itself, and a sibling
    call at another position is refused.  The direct case is the group
    of one, so there is one order here and not two.

    The answer is [Ok None] for a group that no member calls, which is
    the pin test at kan-lang-tot-pin/lib/totality.ml:57;  the
    certificate of the first fitting position for a guarded group, which
    is the first-fit search of
    kan-lang-tot-pin/lib/totality.ml:188-196;  and the termination error
    of SI-D6 otherwise. *)
let certify ?(rule : rule = Structural) (members : (string * Term.t) list) :
    (t option, Error.t) result =
  let group : string list = List.map fst members in
  let peeled : (string * int * Term.t) list =
    List.map
      (fun (((n : string), (b : Term.t)) : string * Term.t) ->
        let formals, inner = peel 0 b in
        (n, formals, inner))
      members
  in
  (* A position must stand in every caller; a helper with no group
     calls does not constrain the search. *)
  let bound : int =
    List.fold_left
      (fun (acc : int option)
           (((_n : string), (formals : int), (inner : Term.t)) : string * int * Term.t) ->
        if not (mentions group inner) then acc else acc
        |> Option.fold ~none:(Some formals) ~some:(fun (a : int) ->
               Some (Int.min a formals)))
      None peeled
    |> Option.value ~default:0
  in
  let rows_at (k : int) : row list option =
    List.fold_left
      (fun (acc : row list option)
           (((n : string), (formals : int), (inner : Term.t)) : string * int * Term.t) ->
        Option.bind acc (fun (rs : row list) ->
            passes ~rule ~group k formals inner
            |> Option.map (fun (cs : call list) ->
                   rs @ [ { rw_member = n; rw_calls = cs } ])))
      (Some []) peeled
  in
  let rec first_fit (k : int) : (t, Error.t) result =
    match () with
    | () when k >= bound -> Error (refusal members)
    | () ->
        rows_at k
        |> Option.fold
             ~none:(fun (_u : unit) -> first_fit (k + 1))
             ~some:(fun (rows : row list) (_u : unit) ->
               Ok { o_group = group; o_arg = k; o_rows = rows })
        |> fun (f : unit -> (t, Error.t) result) -> f ()
  in
  match () with
  | () when List.exists (fun ((_n : string), (b : Term.t)) -> mentions group b) members
    ->
      Result.map Option.some (first_fit 0)
  | () -> Ok None

let one_elim_msg : string =
  "a structurally recursive definition eliminates its recursive argument at the head of its body"

let motive_msg : string =
  "the elimination of a structurally recursive definition carries its motive"

let ctor_key_msg : string =
  "every branch of the elimination of a structurally recursive definition keys a constructor"

(** Validate the source Elim after certification (SI-D27).  Its legs
    bind constructor fields only, as Rules.mu_branch and Rules.mu_beta
    require.  Recursive calls stay in the body and compute through
    Eval.whnf's guarded unfolding, not through extra result binders.
    Helpers with no group calls need no elimination.  This preserves
    the disclosed deviation from brief 3.4 rather than extending Elim. *)
let rec translate (cert : t) (body : Term.t) : (Term.t, Error.t) result =
  if not (mentions cert.o_group body) then Ok body
  else translate_recursive cert body

and translate_recursive (cert : t) (body : Term.t) : (Term.t, Error.t) result =
  let ws, inner = unwrap [] body in
  let formals = List.length ws in
  let* e = as_elim inner |> Option.to_result ~none:(Error.Mismatch one_elim_msg) in
  let* ix =
    as_var e.Term.e_scrut |> Option.to_result ~none:(Error.Mismatch one_elim_msg)
  in
  let* () =
    match () with
    | () when Int.equal ix (formals - 1 - cert.o_arg) -> Ok ()
    | () -> Error (Error.Mismatch one_elim_msg)
  in
  let* _mo =
    e.Term.e_motive |> Option.to_result ~none:(Error.Missing_branch motive_msg)
  in
  let* () =
    List.fold_left
      (fun (acc : (unit, Error.t) result)
           (((a : Term.addr), (_lg : Term.leg)) : Term.addr * Term.leg) ->
        let* () = acc in
        Term.as_actor a
        |> Option.fold ~none:(Error (Error.Wrong_leg ctor_key_msg))
             ~some:(fun (_c : string) -> Ok ()))
      (Ok ()) e.Term.e_branches
  in
  let* () =
    List.fold_left
      (fun (acc : (unit, Error.t) result) (r : row) ->
        let* () = acc in
        List.fold_left
          (fun (acc2 : (unit, Error.t) result) (cl : call) ->
            let* () = acc2 in
            Rules.at 0 cl.cl_chain
            |> Option.fold
                 ~none:(Error (Error.Termination r.rw_member))
                 ~some:(fun (s : step) ->
                   s.st_ctor
                   |> Option.fold
                        ~none:(Error (Error.Termination r.rw_member))
                        ~some:(fun (_c : string) -> Ok ())))
          (Ok ()) r.rw_calls)
      (Ok ()) cert.o_rows
  in
  Ok (rewrap ws (Term.Elim e))
