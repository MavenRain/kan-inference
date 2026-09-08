open Kanon_kernel

let ( let* ) = Result.bind
let nat = Prim.nat_ty
let zero = Term.Lit (Literal.LInt Bignum.zero)
let unit_ty = Rules.unit_ty Level.one
let both = Rules.sum_ty [ nat; nat ]
let void = Rules.sum_ty []

let lambda q name dom body =
  Term.Sec (Shape.SPi (q, name, dom), [ { Term.l_binders = [ q, name ]; l_body = body } ])

let app stamp name argument =
  Term.Out (Shape.SPi (stamp, "arg", nat), Term.APt (stamp, argument), Term.Global name)

let check globals term ty =
  let* expected = Eval.eval globals [] ty in
  Check.check_term globals term expected

let linear globals dom cod body =
  check globals (lambda Quantity.One "x" dom body) (Rules.arrow Quantity.One "x" dom cod)

let postulate globals name ty =
  let* entry = Check.check_decl globals Budget.unlimited
    { Check.d_name = name; d_kind = Check.Postulate; d_ty = ty; d_body = None } in
  Ok (Global.add name entry globals)

let branch index body =
  Term.ALeg index, { Term.l_binders = [ Quantity.Many, "payload" ]; l_body = body }

let elimination shape scrut quantity branches =
  Term.Elim { Term.e_shape = shape; e_scrut = scrut; e_scrut_q = quantity;
    e_motive = None; e_branches = branches }

let case scrut quantity body0 body1 =
  elimination (Shape.SColl 2) scrut quantity [ branch 0 body0; branch 1 body1 ]

let absurd scrut = elimination (Shape.SColl 0) scrut Quantity.One []

type expectation = Accept | Quantity_error | Negative_literal

let observed expected result =
  match expected, result with
  | Accept, Ok () -> true
  | Accept, Error _error -> false
  | Quantity_error, Ok () | Negative_literal, Ok () -> false
  | Quantity_error, Error error ->
      String.starts_with ~prefix:"quantity: " (Error.to_string error)
  | Negative_literal, Error error ->
      String.equal (Error.to_string error) "mismatch: a Nat literal must be nonnegative"

let cases globals =
  let li = linear globals nat nat in
  let choose a b =
    linear globals nat (Rules.arrow Quantity.Many "tag" both nat)
      (lambda Quantity.Many "tag" both (case (Term.Var 0) Quantity.One a b)) in
  let tuple a b = Term.Sec (Shape.SColl 2, [ Rules.leg_of a; Rules.leg_of b ]) in
  let fn_ty = Rules.arrow Quantity.Many "ignored" nat nat in
  let captured = lambda Quantity.Many "ignored" nat (Term.Var 1) in
  let call_local index = Term.Out (Shape.SPi (Quantity.Many, "arg", nat),
    Term.APt (Quantity.Many, zero), Term.Var index) in
  [
    "kernel-linear-identity", Accept, li (Term.Var 0);
    "kernel-unused", Quantity_error, li zero;
    "kernel-zero-only", Quantity_error, li (app Quantity.One "ghost" (Term.Var 0));
    "kernel-apt-zero-stamp-many-type", Quantity_error, li (app Quantity.Zero "consume" (Term.Var 0));
    "kernel-apt-one-stamp-many-type", Quantity_error, li (app Quantity.One "consume" (Term.Var 0));
    "kernel-apt-many-stamp-one-type", Accept, li (app Quantity.Many "identity" (Term.Var 0));
    "kernel-apt-zero-stamp-one-type", Accept, li (app Quantity.Zero "identity" (Term.Var 0));
    "kernel-once-per-branch", Accept, choose (Term.Var 2) (Term.Var 2);
    "kernel-asymmetric-branches", Quantity_error, choose (Term.Var 2) zero;
    "kernel-scrutinee-once", Accept,
      linear globals both nat (case (Term.Var 0) Quantity.One (Term.Var 0) (Term.Var 0));
    "kernel-scrutinee-many", Quantity_error,
      linear globals both nat (case (Term.Var 0) Quantity.Many (Term.Var 0) (Term.Var 0));
    "kernel-scrutinee-zero", Quantity_error,
      linear globals both nat (case (Term.Var 0) Quantity.Zero (Term.Var 0) (Term.Var 0));
    "kernel-scrutinee-plus-branch", Quantity_error,
      linear globals both both (case (Term.Var 0) Quantity.One (Term.Var 1) (Term.Var 1));
    "kernel-sequential-tuple", Quantity_error,
      linear globals nat (Rules.prod_ty [ nat; nat ]) (tuple (Term.Var 0) (Term.Var 0));
    "kernel-let-once", Accept, li (Term.Let ("alias", nat, Term.Var 0, Term.Var 0));
    "kernel-let-unused", Accept, li (Term.Let ("alias", nat, Term.Var 0, zero));
    "kernel-let-eager-duplicate", Quantity_error, li (Term.Let ("alias", nat, Term.Var 0, Term.Var 1));
    "kernel-let-twice", Quantity_error,
      linear globals nat (Rules.prod_ty [ nat; nat ])
        (Term.Let ("alias", nat, Term.Var 0, tuple (Term.Var 0) (Term.Var 0)));
    "kernel-shadowed-name-unused", Quantity_error, li (Term.Let ("x", nat, zero, Term.Var 0));
    "kernel-capture-once", Accept, li (Term.Let ("closure", fn_ty, captured, call_local 0));
    "kernel-capture-twice", Quantity_error,
      linear globals nat (Rules.prod_ty [ nat; nat ])
        (Term.Let ("closure", fn_ty, captured, tuple (call_local 0) (call_local 0)));
    "kernel-empty-elimination", Accept, linear globals void nat (absurd (Term.Var 0));
    "kernel-unreachable-body", Accept, li (absurd (Term.Global "impossible"));
    "kernel-unreachable-unused-let", Accept,
      li (Term.Let ("dead", nat, absurd (Term.Global "impossible"), zero));
    "kernel-unreachable-alternative", Accept, choose (absurd (Term.Global "impossible")) (Term.Var 2);
    "kernel-nested-branches", Accept,
      choose (case (Term.Var 1) Quantity.One (Term.Var 3) (Term.Var 3)) (Term.Var 2);
    "kernel-negative-literal", Negative_literal,
      Result.map (fun _ty -> ()) (Check.infer_term globals (Term.Lit (Literal.LInt (Bignum.of_int (-1)))));
  ]

let run () =
  let* globals = postulate Global.initial "consume" (Rules.arrow Quantity.Many "arg" nat nat) in
  let* globals = postulate globals "identity" (Rules.arrow Quantity.One "arg" nat nat) in
  let* globals = postulate globals "ghost" (Rules.arrow Quantity.Zero "arg" nat nat) in
  let* globals = postulate globals "impossible" void in
  let rows = cases globals in
  let passed = List.fold_left (fun count (name, expected, result) ->
    let good = observed expected result in
    let detail = Result.fold ~ok:(fun () -> "accepted") ~error:Error.to_string result in
    Printf.printf "ONE-DIRECT %s %s %s\n" name (if good then "OK" else "FAIL") detail;
    count + if good then 1 else 0) 0 rows in
  Printf.printf "ONE-DIRECT %d/%d\n" passed (List.length rows);
  Ok (Int.equal passed (List.length rows))

let () =
  Result.fold ~ok:(fun success -> if success then exit 0 else exit 1)
    ~error:(fun error -> prerr_endline (Error.to_string error); exit 1) (run ())
