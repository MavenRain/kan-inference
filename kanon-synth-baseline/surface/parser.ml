(** Recursive-descent parser for the M0 surface, SPEC.md section 9.
    [parse] returns a result and never leaves the result track:  no
    OCaml failure is thrown and none is caught.

    Mirrors kan-lang-tot-pin/surface/parser.ml:1-430 arm by arm:  the
    [let*] walk over an immutable token list, the speculative binder
    group of parser.ml:316-352 that commits only when the closing
    parenthesis is followed by the operator, the [parse_arrow] fold of
    parser.ml:354-360, the left-associative application loop of
    parser.ml:380-390 and the atom table of parser.ml:392-427.  tot's
    hole record and its "end"-terminated match are left out.  Stage L
    uses "end" only to close an explicitly mutual family group.

    Precedence, loosest first (SPEC.md section 9):  the arrow and the
    star, which are right associative;  then application, which is left
    associative (SA-D1);  then the postfix projections.  The four
    binding forms fun, let, case and match sit at the loosest level and reach
    as far right as they can. *)

open Kanon_kernel

let ( let* ) = Result.bind

let parse_err (loc : Token.loc) (msg : string) : ('a, Error.t) result =
  Error (Error.Parse (msg, loc.Token.line, loc.Token.col))

let eof_err : ('a, Error.t) result =
  (* unreachable:  the lexer always materialises an [Eof] token *)
  parse_err Token.start "unexpected end of input"

(** One error shape for every "wanted X, read Y" arm, so a new arm adds
    a name and no format.  mirrors the error arms of
    kan-lang-tot-pin/surface/parser.ml, which spell this inline. *)
let expected (what : string) (ts : Token.t list) : ('a, Error.t) result =
  match ts with
  | { Token.kind; loc } :: _rest ->
      parse_err loc (Printf.sprintf "expected %s, found %s" what (Token.describe kind))
  | [] -> eof_err

(* mirrors kan-lang-tot-pin/surface/parser.ml:51-69 *)
let kind_starts_atom (k : Token.kind) : bool =
  match k with
  | Token.Ident _ | Token.Nat _ | Token.LParen | Token.Unit | Token.KProp | Token.KType
  | Token.KAuto | Token.KTuple | Token.KSum | Token.KProd | Token.KNatAdd
  | Token.KNatSub | Token.KNatMul | Token.KNatEq | Token.KNatLt | Token.KNu ->
      true
  (* M1 Stage G, correction C7:  'mu' opens a declaration and 'and' joins
     two of them, so neither starts an atom.  Were 'mu' to start one, the
     body of a 'def' would swallow the mu group written after it. *)
  | Token.RParen | Token.Colon | Token.ColonEq | Token.Arrow | Token.DArrow | Token.Star
  | Token.Comma | Token.Dot | Token.Dot1 | Token.Dot2 | Token.Pipe | Token.KDef
  | Token.KAxiom | Token.KFun | Token.KInj | Token.KOf | Token.KCase | Token.KAs
  (* M1 Stage I, SI-D8:  'rec' stands inside a declaration header and
     never inside a term, so it starts no atom either. *)
  | Token.KReturn | Token.KWith | Token.KAbsurd | Token.KLet | Token.KIn | Token.KMu
  | Token.KAnd | Token.KRec | Token.KMatch | Token.KMutual | Token.KEnd | Token.Eof ->
      false

let starts_atom (ts : Token.t list) : bool =
  match ts with
  | { Token.kind; loc = _ } :: _rest -> kind_starts_atom kind
  | [] -> false

(** The binder's mark, SPEC.md section 9 and SB-D3.  "0" is the erased
    mark, "1" is the linear mark and an absent mark is the runtime one.
    Total:  a token that is neither leaves the list where it was. *)
let mark_prefix (ts : Token.t list) : Quantity.t * Token.t list =
  match ts with
  | { Token.kind = Token.Nat n; loc = _ } :: rest when Bignum.equal n Bignum.zero ->
      (Quantity.Zero, rest)
  | { Token.kind = Token.Nat n; loc = _ } :: rest when Bignum.equal n Bignum.one ->
      (Quantity.One, rest)
  | ({ Token.kind = _; loc = _ } :: _ | []) as same -> (Quantity.Many, same)

(** SK-D3 keeps the old eighteen-digit range for levels and leg numbers.
    Natural literals alone become unbounded; checked narrowing never wraps. *)
let bounded_nat (loc : Token.loc) (n : Bignum.t) : (int, Error.t) result =
  if Bignum.sign n < 0 || String.length (Bignum.to_string n) > 18 then
    parse_err loc "numeric literal too long"
  else Bignum.to_int n
    |> Option.to_result ~none:(Error.Parse ("numeric literal too long", loc.Token.line, loc.Token.col))

(** SL-D3: legacy case also admits the constructor keys of Stage H.
    Match admits only constructor keys and retains its identity in the
    tree, including when no branches occur. *)
type elimination = LegacyCase | FiberedMatch

let elimination_node (form : elimination) (scrut : Syntax.t)
    (mo : Syntax.motive option) (branches : Syntax.branch list) : Syntax.t =
  match form with
  | LegacyCase -> Syntax.SCase (scrut, mo, branches)
  | FiberedMatch -> Syntax.SMatch (scrut, mo, branches)

let numeric_key (form : elimination) (loc : Token.loc) : (unit, Error.t) result =
  match form with
  | LegacyCase -> Ok ()
  | FiberedMatch -> parse_err loc "a match branch keys a constructor, not a leg number"

let rec parse_term (ts : Token.t list) : (Syntax.t * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.KFun; loc = _ } :: rest -> parse_fun rest
  | { Token.kind = Token.KLet; loc = _ } :: rest -> parse_let rest
  | { Token.kind = Token.KCase; loc = _ } :: rest -> parse_case LegacyCase rest
  | { Token.kind = Token.KMatch; loc = _ } :: rest -> parse_case FiberedMatch rest
  | ({ Token.kind = _; loc = _ } :: _ | []) -> parse_arrow ts

(** "fun binder+ => body".  One binder at least;  the body reaches as
    far right as it can. *)
and parse_fun (ts : Token.t list) : (Syntax.t * Token.t list, Error.t) result =
  let* first, rest = parse_binder ts in
  let* binders, rest2 = parse_binders rest [ first ] in
  match rest2 with
  | { Token.kind = Token.DArrow; loc = _ } :: rest3 ->
      let* body, rest4 = parse_term rest3 in
      Ok (Syntax.SFun (binders, body), rest4)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "'=>'" rest2

(** Zero or more binders, oldest first.  Total over a list that starts
    with no parenthesis. *)
and parse_binders (ts : Token.t list) (acc : Syntax.binder list) :
    (Syntax.binder list * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.LParen; loc = _ } :: _rest ->
      let* b, rest = parse_binder ts in
      parse_binders rest (b :: acc)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> Ok (List.rev acc, ts)

(** binder ::= '(' ('0' | '1')? name ':' term ')' *)
and parse_binder (ts : Token.t list) : (Syntax.binder * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.LParen; loc = _ } :: rest -> (
      let q, rest_q = mark_prefix rest in
      match rest_q with
      | { Token.kind = Token.Ident x; loc = _ }
        :: { Token.kind = Token.Colon; loc = _ }
        :: rest2 -> (
          let* ty, rest3 = parse_term rest2 in
          match rest3 with
          | { Token.kind = Token.RParen; loc = _ } :: rest4 ->
              Ok ({ Syntax.b_q = q; b_name = x; b_ty = ty }, rest4)
          | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "')'" rest3)
      | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "a binder name and ':'" rest_q)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "'('" ts

(** "let x : A := d in b" *)
and parse_let (ts : Token.t list) : (Syntax.t * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.Ident x; loc = _ } :: { Token.kind = Token.Colon; loc = _ } :: rest
    -> (
      let* ty, rest2 = parse_term rest in
      match rest2 with
      | { Token.kind = Token.ColonEq; loc = _ } :: rest3 -> (
          let* def, rest4 = parse_term rest3 in
          match rest4 with
          | { Token.kind = Token.KIn; loc = _ } :: rest5 ->
              let* body, rest6 = parse_term rest5 in
              Ok (Syntax.SLet (x, ty, def, body), rest6)
          | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "'in'" rest4)
      | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "':='" rest2)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "a name and ':' after 'let'" ts

(** "case t ['as' x ['in' FAMILY idx*] 'return' M] 'with'
    ('|' k binder* '=>' b | '|' c field* '=>' b)*".  M1 Stage H, brief
    3.8:  the index clause and the constructor keyed branch are the
    minimum a fibered elimination needs, and both mirror
    kan-lang-tot-pin/surface/parser.ml:227-236 and :288-299.  The clause
    sits after "as x", so it cannot collide with a "let .. in .."
    scrutinee, which [parse_term] has already read whole. *)
and parse_case (form : elimination) (ts : Token.t list) :
    (Syntax.t * Token.t list, Error.t) result =
  let* scrut, rest = parse_term ts in
  match rest with
  | { Token.kind = Token.KAs; loc = _ } :: { Token.kind = Token.Ident x; loc = _ } :: rest2
    -> (
      let ind, idx, rest3 = parse_index_clause rest2 in
      match rest3 with
      | { Token.kind = Token.KReturn; loc = _ } :: rest4 -> (
          let* body, rest5 = parse_term rest4 in
          match rest5 with
          | { Token.kind = Token.KWith; loc = _ } :: rest6 ->
              let* branches, rest7 = parse_branches form rest6 [] in
              let mo : Syntax.motive =
                { Syntax.mo_self = x; mo_ind = ind; mo_idx = idx; mo_body = body }
              in
              Ok (elimination_node form scrut (Some mo) branches, rest7)
          | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "'with'" rest5)
      | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "'return'" rest3)
  | { Token.kind = Token.KAs; loc } :: _rest ->
      parse_err loc "expected 'NAME [in FAMILY IDX..] return TYPE' after 'as'"
  | { Token.kind = Token.KWith; loc = _ } :: rest2 ->
      let* branches, rest3 = parse_branches form rest2 [] in
      Ok (elimination_node form scrut None branches, rest3)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "'as' or 'with'" rest

(** M1 Stage H, brief 3.8:  the optional "'in' FAMILY idx*" clause of a
    motive.  A token list that does not open with "in" is given back
    unread, so the M0 motive form parses as it did at M0. *)
and parse_index_clause (ts : Token.t list) : string option * string list * Token.t list =
  match ts with
  | { Token.kind = Token.KIn; loc = _ } :: { Token.kind = Token.Ident n; loc = _ } :: rest
    ->
      let names, rest2 = parse_names rest [] in
      (Some n, names, rest2)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> (None, [], ts)

(** Zero or more names, oldest first.  Total:  the list ends at the
    first token that is not a name. *)
and parse_names (ts : Token.t list) (acc : string list) : string list * Token.t list =
  match ts with
  | { Token.kind = Token.Ident x; loc = _ } :: rest -> parse_names rest (x :: acc)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> (List.rev acc, ts)

(** Zero or more branches.  The list ends at the first token that is not
    a bar, so the enclosing form reads on.  mirrors
    kan-lang-tot-pin/surface/parser.ml:283-314 for the leg keyed row and
    :288-299 for the constructor keyed row of M1 Stage H. *)
and parse_branches (form : elimination) (ts : Token.t list) (acc : Syntax.branch list) :
    (Syntax.branch list * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.Pipe; loc = _ } :: { Token.kind = Token.Nat k; loc } :: rest
    -> (
      let* () = numeric_key form loc in
      let* k = bounded_nat loc k in
      let* binders, rest2 = parse_binders rest [] in
      match rest2 with
      | { Token.kind = Token.DArrow; loc = _ } :: rest3 ->
          let* body, rest4 = parse_term rest3 in
          parse_branches form rest4 (Syntax.BrLeg (k, binders, body) :: acc)
      | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "'=>'" rest2)
  | { Token.kind = Token.Pipe; loc = _ } :: { Token.kind = Token.Ident c; loc = _ } :: rest
    -> (
      let* fields, rest2 = parse_fields rest [] in
      match rest2 with
      | { Token.kind = Token.DArrow; loc = _ } :: rest3 ->
          let* body, rest4 = parse_term rest3 in
          parse_branches form rest4 (Syntax.BrCtor (c, fields, body) :: acc)
      | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "'=>'" rest2)
  | { Token.kind = Token.Pipe; loc } :: _rest ->
      parse_err loc "expected a leg number or a constructor name after '|'"
  | ({ Token.kind = _; loc = _ } :: _ | []) -> Ok (List.rev acc, ts)

(** M1 Stage H, brief 3.8:  zero or more field binders of a constructor
    keyed branch, each a mark and a name.  A field takes its type from
    the family record.  SL-D4 additionally accepts a typed binder and
    preserves its annotation for checking under preceding fields.
    The list ends when no binder, mark or name opens the next field. *)
and parse_fields (ts : Token.t list) (acc : Syntax.field list) :
    (Syntax.field list * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.LParen; loc = _ } :: _rest ->
      let* b, rest = parse_binder ts in
      parse_fields rest
        ({ Syntax.fd_q = b.Syntax.b_q; fd_name = b.Syntax.b_name;
           fd_ty = Some b.Syntax.b_ty } :: acc)
  | ({ Token.kind = _; loc = _ } :: _ | []) ->
      let q, rest = mark_prefix ts in
      match rest with
      | { Token.kind = Token.Ident x; loc = _ } :: rest2 ->
          parse_fields rest2 ({ Syntax.fd_q = q; fd_name = x; fd_ty = None } :: acc)
      | ({ Token.kind = _; loc = _ } :: _ | []) -> Ok (List.rev acc, ts)

(** The arrow and the star.  The speculative binder group runs first and
    commits only when the operator follows it, so "(t : A)" stays an
    annotation when no operator follows.  mirrors
    kan-lang-tot-pin/surface/parser.ml:354-360. *)
and parse_arrow (ts : Token.t list) : (Syntax.t * Token.t list, Error.t) result =
  binder_group_attempt ts
  |> Option.fold ~none:parse_arrow_plain ~some:(fun ((b : Syntax.binder), rest) ->
         fun (_ts : Token.t list) -> parse_group_op b rest)
  |> fun k -> k ts

(** Speculative "(mark? x : T)".  Any inner failure, and any group that
    no operator follows, is [None] and the caller re-reads the same
    tokens as an ordinary term.  mirrors
    kan-lang-tot-pin/surface/parser.ml:316-352. *)
and binder_group_attempt (ts : Token.t list) : (Syntax.binder * Token.t list) option =
  match ts with
  | { Token.kind = Token.LParen; loc = _ } :: _rest ->
      parse_binder ts
      |> Result.fold
           ~ok:(fun ((b : Syntax.binder), rest) ->
             match rest with
             | { Token.kind = Token.Arrow; loc = _ } :: _r -> Some (b, rest)
             | { Token.kind = Token.Star; loc = _ } :: _r -> Some (b, rest)
             | ({ Token.kind = _; loc = _ } :: _ | []) -> None)
           ~error:(fun (_e : Error.t) -> None)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> None

and parse_group_op (b : Syntax.binder) (ts : Token.t list) :
    (Syntax.t * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.Arrow; loc = _ } :: rest ->
      let* cod, rest2 = parse_term rest in
      Ok (Syntax.SArrow (b, cod), rest2)
  | { Token.kind = Token.Star; loc = _ } :: rest ->
      let* cod, rest2 = parse_term rest in
      Ok (Syntax.SStar (b, cod), rest2)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "'->' or '*'" ts

(** "A -> B" and "A * B", the binder-free forms.  Both are right
    associative and both name the binder "_", the name the printer
    writes back.  mirrors kan-lang-tot-pin/surface/parser.ml:372-378. *)
and parse_arrow_plain (ts : Token.t list) : (Syntax.t * Token.t list, Error.t) result =
  let* lhs, rest = parse_app ts in
  match rest with
  | { Token.kind = Token.Arrow; loc = _ } :: rest2 ->
      let* rhs, rest3 = parse_term rest2 in
      Ok (Syntax.SArrow ({ Syntax.b_q = Quantity.Many; b_name = "_"; b_ty = lhs }, rhs), rest3)
  | { Token.kind = Token.Star; loc = _ } :: rest2 ->
      let* rhs, rest3 = parse_term rest2 in
      Ok (Syntax.SStar ({ Syntax.b_q = Quantity.Many; b_name = "_"; b_ty = lhs }, rhs), rest3)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> Ok (lhs, rest)

(** Application by juxtaposition (SA-D1), and the two saturated prefix
    forms that read one application each.  mirrors
    kan-lang-tot-pin/surface/parser.ml:380-390. *)
and parse_app (ts : Token.t list) : (Syntax.t * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.KInj; loc = _ } :: rest -> parse_inj rest
  | { Token.kind = Token.KAbsurd; loc = _ } :: rest ->
      let* a, rest2 = parse_app rest in
      Ok (Syntax.SAbsurd a, rest2)
  | ({ Token.kind = _; loc = _ } :: _ | []) ->
      let* head, rest = parse_atom ts in
      parse_app_rest head rest

and parse_inj (ts : Token.t list) : (Syntax.t * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.Nat k; loc = kloc }
    :: { Token.kind = Token.KOf; loc = _ }
    :: { Token.kind = Token.Nat n; loc = nloc }
    :: rest ->
      let* k = bounded_nat kloc k in
      let* n = bounded_nat nloc n in
      let* a, rest2 = parse_app rest in
      Ok (Syntax.SInj (k, n, a), rest2)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "'K of N' after 'inj'" ts

and parse_app_rest (head : Syntax.t) (ts : Token.t list) :
    (Syntax.t * Token.t list, Error.t) result =
  match () with
  | () when starts_atom ts ->
      let* arg, rest = parse_atom ts in
      parse_app_rest (Syntax.SApp (head, arg)) rest
  | () -> Ok (head, ts)

(** An atom with its postfix projections, which bind tighter than
    application. *)
and parse_atom (ts : Token.t list) : (Syntax.t * Token.t list, Error.t) result =
  let* a, rest = parse_atom_head ts in
  parse_postfix a rest

and parse_postfix (a : Syntax.t) (ts : Token.t list) :
    (Syntax.t * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.Dot1; loc = _ } :: rest -> parse_postfix (Syntax.SProj (a, 1)) rest
  | { Token.kind = Token.Dot2; loc = _ } :: rest -> parse_postfix (Syntax.SProj (a, 2)) rest
  | { Token.kind = Token.Dot; loc = _ } :: { Token.kind = Token.Nat k; loc } :: rest ->
      let* k = bounded_nat loc k in
      parse_postfix (Syntax.SProj (a, k)) rest
  | { Token.kind = Token.Dot; loc } :: _rest ->
      parse_err loc "expected a leg number after '.'"
  | ({ Token.kind = _; loc = _ } :: _ | []) -> Ok (a, ts)

(* mirrors kan-lang-tot-pin/surface/parser.ml:392-427 *)
and parse_atom_head (ts : Token.t list) : (Syntax.t * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.Ident x; loc = _ } :: rest -> Ok (Syntax.SVar x, rest)
  | { Token.kind = Token.Nat n; loc = _ } :: rest -> Ok (Syntax.SNat n, rest)
  | { Token.kind = Token.KProp; loc = _ } :: rest -> Ok (Syntax.SProp, rest)
  | { Token.kind = Token.KType; loc = _ } :: { Token.kind = Token.Nat n; loc } :: rest ->
      let* n = bounded_nat loc n in
      Ok (Syntax.SType n, rest)
  | { Token.kind = Token.KType; loc = _ } :: rest -> Ok (Syntax.SType 0, rest)
  | { Token.kind = Token.KAuto; loc = _ } :: rest -> Ok (Syntax.SAuto, rest)
  | { Token.kind = Token.Unit; loc = _ } :: rest -> Ok (Syntax.SUnit, rest)
  | { Token.kind = Token.KNatAdd; loc = _ } :: rest -> Ok (Syntax.SPrim Syntax.PAdd, rest)
  | { Token.kind = Token.KNatSub; loc = _ } :: rest -> Ok (Syntax.SPrim Syntax.PSub, rest)
  | { Token.kind = Token.KNatMul; loc = _ } :: rest -> Ok (Syntax.SPrim Syntax.PMul, rest)
  | { Token.kind = Token.KNatEq; loc = _ } :: rest -> Ok (Syntax.SPrim Syntax.PEq, rest)
  | { Token.kind = Token.KNatLt; loc = _ } :: rest -> Ok (Syntax.SPrim Syntax.PLt, rest)
  | { Token.kind = Token.KTuple; loc = _ } :: rest ->
      parse_items "tuple" (fun (xs : Syntax.t list) -> Syntax.STuple xs) rest
  | { Token.kind = Token.KSum; loc = _ } :: rest ->
      parse_items "sum" (fun (xs : Syntax.t list) -> Syntax.SSum xs) rest
  | { Token.kind = Token.KProd; loc = _ } :: rest ->
      parse_items "prod" (fun (xs : Syntax.t list) -> Syntax.SProd xs) rest
  (* M1 Stage G, correction C7:  'mu' is a declaration word from this
     stage, so in a term position it names its own production instead of
     a milestone.  'nu' keeps the SA-D3 refusal with its milestone. *)
  | { Token.kind = Token.KMu; loc } :: _rest ->
      parse_err loc "a mu group is a declaration and not a term"
  | { Token.kind = Token.KAnd; loc } :: _rest ->
      parse_err loc "'and' joins two members of a mu group and is not a term"
  | { Token.kind = Token.KNu; loc } :: _rest -> parse_err loc "nu arrives at M2"
  | { Token.kind = Token.LParen; loc = _ } :: rest -> parse_paren rest
  | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "a term" ts

(** After "(":  a term and then ")", "," or ":".  mirrors
    kan-lang-tot-pin/surface/parser.ml:404-424. *)
and parse_paren (ts : Token.t list) : (Syntax.t * Token.t list, Error.t) result =
  let* inner, rest = parse_term ts in
  match rest with
  | { Token.kind = Token.RParen; loc = _ } :: rest2 -> Ok (inner, rest2)
  | { Token.kind = Token.Comma; loc = _ } :: rest2 -> (
      let* second, rest3 = parse_term rest2 in
      match rest3 with
      | { Token.kind = Token.RParen; loc = _ } :: rest4 ->
          Ok (Syntax.SPair (inner, second), rest4)
      | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "')'" rest3)
  | { Token.kind = Token.Colon; loc = _ } :: rest2 -> (
      let* ty, rest3 = parse_term rest2 in
      match rest3 with
      | { Token.kind = Token.RParen; loc = _ } :: rest4 ->
          Ok (Syntax.SAnn (inner, ty), rest4)
      | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "')'" rest3)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "')', ',' or ':'" rest

(** "WORD (t1, .., tn)", the one bracketed item list of the grammar.
    Three words read it:  "tuple", the section at the collection shape,
    and the two type words "sum" and "prod" of SB-D1.  The empty list is
    the one token "()", which the lexer reads whole, so both "sum ()"
    and "sum ( )" are the width zero form. *)
and parse_items (word : string) (build : Syntax.t list -> Syntax.t)
    (ts : Token.t list) : (Syntax.t * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.Unit; loc = _ } :: rest -> Ok (build [], rest)
  | { Token.kind = Token.LParen; loc = _ } :: rest -> parse_items_body word build rest
  | ({ Token.kind = _; loc = _ } :: _ | []) ->
      expected (Printf.sprintf "'(' after '%s'" word) ts

and parse_items_body (word : string) (build : Syntax.t list -> Syntax.t)
    (ts : Token.t list) : (Syntax.t * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.RParen; loc = _ } :: rest -> Ok (build [], rest)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> parse_items_rest word build ts []

and parse_items_rest (word : string) (build : Syntax.t list -> Syntax.t)
    (ts : Token.t list) (acc : Syntax.t list) :
    (Syntax.t * Token.t list, Error.t) result =
  let* item, rest = parse_term ts in
  match rest with
  | { Token.kind = Token.Comma; loc = _ } :: rest2 ->
      parse_items_rest word build rest2 (item :: acc)
  | { Token.kind = Token.RParen; loc = _ } :: rest2 ->
      Ok (build (List.rev (item :: acc)), rest2)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "',' or ')'" rest

(** Items, oldest first, up to the [Eof] token. *)
let rec parse_decls (ts : Token.t list) (acc : Syntax.decl list) :
    (Syntax.decl list, Error.t) result =
  match ts with
  | { Token.kind = Token.Eof; loc = _ } :: _rest -> Ok (List.rev acc)
  | ({ Token.kind = _; loc = _ } :: _ | []) ->
      let* d, rest = parse_decl ts in
      parse_decls rest (d :: acc)

and parse_decl (ts : Token.t list) : (Syntax.decl * Token.t list, Error.t) result =
  match ts with
  (* M1 Stage I, SI-D8:  "def rec" opens a recursive group and the
     plain "def" row below keeps its M0 reading, because the two arms
     differ at the token after "def". *)
  | { Token.kind = Token.KDef; loc = _ } :: { Token.kind = Token.KRec; loc = _ } :: rest
    ->
      let* ms, rest2 = parse_rec_group rest [] in
      Ok (Syntax.DRec ms, rest2)
  | { Token.kind = Token.KDef; loc = _ }
    :: { Token.kind = Token.Ident name; loc = _ }
    :: { Token.kind = Token.Colon; loc = _ }
    :: rest -> (
      let* ty, rest2 = parse_term rest in
      match rest2 with
      | { Token.kind = Token.ColonEq; loc = _ } :: rest3 ->
          let* def, rest4 = parse_term rest3 in
          Ok (Syntax.DDef (name, ty, def), rest4)
      | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "':='" rest2)
  | { Token.kind = Token.KAxiom; loc = _ }
    :: { Token.kind = Token.Ident name; loc = _ }
    :: { Token.kind = Token.Colon; loc = _ }
    :: rest ->
      let* ty, rest2 = parse_term rest in
      Ok (Syntax.DAxiom (name, ty), rest2)
  | { Token.kind = Token.KMu; loc = _ } :: rest ->
      let* fams, rest2 = parse_fam_group rest [] in
      Ok (Syntax.DMu fams, rest2)
  | { Token.kind = Token.KMutual; loc = _ } :: rest ->
      let* fams, rest2 = parse_mutual_group rest [] in
      Ok (Syntax.DMu fams, rest2)
  | { Token.kind = Token.KNu; loc } :: _rest -> parse_err loc "nu arrives at M2"
  | ({ Token.kind = _; loc = _ } :: _ | []) ->
      expected "'def NAME :', 'def rec NAME :', 'axiom NAME :', 'mu NAME' or 'mutual'" ts

(** M1 Stage I, SI-D8:  the minimal recursive definition production.

    group   ::= 'def' 'rec' member ('and' member)*
    member  ::= NAME ':' term ':=' term

    The member row is the M0 definition row word for word, so a group of
    one is a definition that may call itself and nothing else of the
    surface moves.  'and' does not start an atom, so the term parser
    stops at the end of every member without a terminator word, exactly
    as it does at a mu group (correction C7). *)
and parse_rec_group (ts : Token.t list) (acc : Syntax.rec_def list) :
    (Syntax.rec_def list * Token.t list, Error.t) result =
  let* m, rest = parse_rec_member ts in
  match rest with
  | { Token.kind = Token.KAnd; loc = _ } :: rest2 -> parse_rec_group rest2 (m :: acc)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> Ok (List.rev (m :: acc), rest)

and parse_rec_member (ts : Token.t list) :
    (Syntax.rec_def * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.Ident name; loc = _ }
    :: { Token.kind = Token.Colon; loc = _ }
    :: rest -> (
      let* ty, rest2 = parse_term rest in
      match rest2 with
      | { Token.kind = Token.ColonEq; loc = _ } :: rest3 ->
          let* body, rest4 = parse_term rest3 in
          Ok ({ Syntax.rd_name = name; rd_ty = ty; rd_body = body }, rest4)
      | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "':='" rest2)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "a definition name and ':'" ts

(** M1 Stage G, correction C7:  the minimal mu production.

    group   ::= 'mu' member ('and' member)*
    member  ::= NAME binder* ':' term 'with' ctor*
    ctor    ::= '|' NAME ':' term

    The binders after the name are the parameter telescope.  The term
    after the colon is an arrow chain whose binders are the index
    telescope and whose result is the declared universe;  the elaborator
    splits it (brief 3.9).  A constructor type is an arrow chain whose
    binders are the argument telescope, one quantity per field, and
    whose result names the family at its result index expressions.
    Stage L also accepts ':=' and constructor binder sugar (SL-D1).

    Neither 'and' nor '|' starts an atom, so the term parser stops at
    the end of every header and of every constructor without a
    terminator word. *)
and parse_fam_group (ts : Token.t list) (acc : Syntax.fam list) :
    (Syntax.fam list * Token.t list, Error.t) result =
  let* fm, rest = parse_fam ts in
  match rest with
  | { Token.kind = Token.KAnd; loc = _ } :: rest2 -> parse_fam_group rest2 (fm :: acc)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> Ok (List.rev (fm :: acc), rest)

(** SL-D2: an explicit mutual group is a sequence of mu declarations,
    closed by end.  Requiring two members rejects accidental singleton
    and empty groups before any family enters the global table. *)
and parse_mutual_group (ts : Token.t list) (acc : Syntax.fam list) :
    (Syntax.fam list * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.KMu; loc = _ } :: rest ->
      let* fm, rest2 = parse_fam rest in
      parse_mutual_group rest2 (fm :: acc)
  | { Token.kind = Token.KEnd; loc } :: rest -> (
      match acc with
      | [] -> parse_err loc "a mutual group needs at least two mu declarations"
      | [ _one ] -> parse_err loc "a mutual group needs at least two mu declarations"
      | _first :: _second :: _remaining -> Ok (List.rev acc, rest))
  | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "'mu' or 'end' in a mutual group" ts

and parse_fam (ts : Token.t list) : (Syntax.fam * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.Ident name; loc = _ } :: rest -> (
      let* params, rest2 = parse_binders rest [] in
      match rest2 with
      | { Token.kind = Token.Colon; loc = _ } :: rest3 -> (
          let* ty, rest4 = parse_term rest3 in
          match rest4 with
          | { Token.kind = Token.KWith | Token.ColonEq; loc = _ } :: rest5 ->
              let* ctors, rest6 = parse_fam_ctors rest5 [] in
              Ok
                ( {
                    Syntax.fm_name = name;
                    fm_params = params;
                    fm_ty = ty;
                    fm_ctors = ctors;
                  },
                  rest6 )
          | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "':=' or 'with'" rest4)
      | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "':'" rest2)
  | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "a family name" ts

(** SL-D1: constructor binder sugar folds to the existing arrow chain,
    preserving field names, dependent types and quantities.  Zero
    binders is the Stage G production. *)
and parse_fam_ctors (ts : Token.t list) (acc : Syntax.fam_ctor list) :
    (Syntax.fam_ctor list * Token.t list, Error.t) result =
  match ts with
  | { Token.kind = Token.Pipe; loc = _ }
    :: { Token.kind = Token.Ident name; loc = _ }
    :: rest -> (
      let* binders, rest2 = parse_binders rest [] in
      match rest2 with
      | { Token.kind = Token.Colon; loc = _ } :: rest3 ->
          let* result, rest4 = parse_term rest3 in
          let ty = List.fold_right
              (fun (b : Syntax.binder) (body : Syntax.t) -> Syntax.SArrow (b, body))
              binders result in
          parse_fam_ctors rest4 ({ Syntax.fc_name = name; fc_ty = ty } :: acc)
      | ({ Token.kind = _; loc = _ } :: _ | []) -> expected "':' after constructor binders" rest2)
  | { Token.kind = Token.Pipe; loc } :: _rest ->
      parse_err loc "expected a constructor name and ':' after '|'"
  | ({ Token.kind = _; loc = _ } :: _ | []) -> Ok (List.rev acc, ts)

(** The whole surface pass:  text to items, on the result track. *)
let parse (src : string) : (Syntax.decl list, Error.t) result =
  let* ts = Lexer.lex src in
  parse_decls ts []
