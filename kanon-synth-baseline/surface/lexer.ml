(** Lexer for the M0 surface, SPEC.md section 9.  The source is exploded
    to a char list once and everything after that is recursion over that
    list.

    Mirrors kan-lang-tot-pin/surface/lexer.ml:1-144 arm by arm: the
    keyword table, [span], [nat_of_digits], the [go] walk and the "--"
    comment form are tot's, and the token set is the M0 one.  tot's
    string literals, its shebang strip and its "let*" prefixes have no
    M0 production and are left out.  A lexical failure is
    [Error.Parse], the same error the parser returns, so the surface has
    one error type and no second one to translate (SA-D18). *)

open Kanon_kernel

let lex_err (loc : Token.loc) (msg : string) : ('a, Error.t) result =
  Error (Error.Parse (msg, loc.Token.line, loc.Token.col))

(* mirrors kan-lang-tot-pin/surface/lexer.ml:7-12 *)
let is_digit (c : char) : bool = c >= '0' && c <= '9'

let is_ident_start (c : char) : bool =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || Char.equal c '_'

let is_ident_char (c : char) : bool = is_ident_start c || is_digit c || Char.equal c '\''

(** The twenty-three keywords of plan section 8, plus the three words of
    SA-D3.  mirrors kan-lang-tot-pin/surface/lexer.ml:14-41. *)
let keywords : (string * Token.kind) list =
  [
    ("def", Token.KDef);
    ("axiom", Token.KAxiom);
    ("fun", Token.KFun);
    ("inj", Token.KInj);
    ("of", Token.KOf);
    ("case", Token.KCase);
    ("match", Token.KMatch);
    ("as", Token.KAs);
    ("return", Token.KReturn);
    ("with", Token.KWith);
    ("tuple", Token.KTuple);
    ("sum", Token.KSum);
    ("prod", Token.KProd);
    ("absurd", Token.KAbsurd);
    ("Prop", Token.KProp);
    ("Type", Token.KType);
    ("let", Token.KLet);
    ("in", Token.KIn);
    ("natAdd", Token.KNatAdd);
    ("natSub", Token.KNatSub);
    ("natMul", Token.KNatMul);
    ("natEq", Token.KNatEq);
    ("natLt", Token.KNatLt);
    ("auto", Token.KAuto);
    ("mu", Token.KMu);
    ("mutual", Token.KMutual);
    ("end", Token.KEnd);
    ("nu", Token.KNu);
    (* M1 Stage G, correction C7:  the mutual group word. *)
    ("and", Token.KAnd);
    (* M1 Stage I, SI-D8:  the one word the minimal recursive
       definition production adds, which stands after "def". *)
    ("rec", Token.KRec);
  ]

let ident_kind (s : string) : Token.kind =
  List.assoc_opt s keywords |> Option.value ~default:(Token.Ident s)

(** Take the longest prefix that satisfies [p];  return it with the
    position just past it and the rest.  mirrors
    kan-lang-tot-pin/surface/lexer.ml:45-51. *)
let rec span (p : char -> bool) (loc : Token.loc) (cs : char list) :
    char list * Token.loc * char list =
  match cs with
  | c :: rest when p c ->
      let taken, loc', rest' = span p (Token.next_col loc) rest in
      (c :: taken, loc', rest')
  | ([] | _ :: _) as rest -> ([], loc, rest)

(* SK-D3 replaces the bounded fold of kan-lang-tot-pin/surface/lexer.ml:53-54. *)
let nat_of_digits (loc : Token.loc) (digits : char list) : (Bignum.t, Error.t) result =
  List.to_seq digits |> String.of_seq |> Bignum.of_decimal
  |> Option.to_result ~none:(Error.Parse ("invalid natural literal", loc.Token.line, loc.Token.col))

(** SA-D16.  A dot with a digit run after it.  The run "1" is the first
    pair projection and the run "2" is the second;  any other run is the
    collection projection, which the parser reads as [Dot] and a number,
    so ".10" is leg ten and never leg one followed by zero. *)
let dot_tokens (loc : Token.loc) (digits : char list) : (Token.t list, Error.t) result =
  match digits with
  | [] -> Ok [ { Token.kind = Token.Dot; loc } ]
  | [ '1' ] -> Ok [ { Token.kind = Token.Dot1; loc } ]
  | [ '2' ] -> Ok [ { Token.kind = Token.Dot2; loc } ]
  | _first :: _rest ->
      nat_of_digits loc digits |> Result.map (fun n ->
        [ { Token.kind = Token.Dot; loc }; { Token.kind = Token.Nat n; loc = Token.next_col loc } ])

(* mirrors kan-lang-tot-pin/surface/lexer.ml:85-135, arm by arm *)
let rec go (loc : Token.loc) (cs : char list) (acc : Token.t list) :
    (Token.t list, Error.t) result =
  match cs with
  | [] -> Ok (List.rev ({ Token.kind = Token.Eof; loc } :: acc))
  | ' ' :: rest | '\t' :: rest | '\r' :: rest -> go (Token.next_col loc) rest acc
  | '\n' :: rest -> go (Token.next_line loc) rest acc
  | '-' :: '-' :: rest -> skip_comment (Token.advance loc 2) rest acc
  | '-' :: '>' :: rest ->
      go (Token.advance loc 2) rest ({ Token.kind = Token.Arrow; loc } :: acc)
  | '=' :: '>' :: rest ->
      go (Token.advance loc 2) rest ({ Token.kind = Token.DArrow; loc } :: acc)
  | ':' :: '=' :: rest ->
      go (Token.advance loc 2) rest ({ Token.kind = Token.ColonEq; loc } :: acc)
  | ':' :: rest -> go (Token.next_col loc) rest ({ Token.kind = Token.Colon; loc } :: acc)
  | '(' :: ')' :: rest ->
      go (Token.advance loc 2) rest ({ Token.kind = Token.Unit; loc } :: acc)
  | '(' :: rest -> go (Token.next_col loc) rest ({ Token.kind = Token.LParen; loc } :: acc)
  | ')' :: rest -> go (Token.next_col loc) rest ({ Token.kind = Token.RParen; loc } :: acc)
  | '*' :: rest -> go (Token.next_col loc) rest ({ Token.kind = Token.Star; loc } :: acc)
  | ',' :: rest -> go (Token.next_col loc) rest ({ Token.kind = Token.Comma; loc } :: acc)
  | '|' :: rest -> go (Token.next_col loc) rest ({ Token.kind = Token.Pipe; loc } :: acc)
  | '.' :: rest ->
      let digits, loc', rest' = span is_digit (Token.next_col loc) rest in
      Result.bind (dot_tokens loc digits) (fun tokens ->
        go loc' rest' (List.rev_append tokens acc))
  | c :: rest when is_digit c ->
      let taken, loc', rest' = span is_digit (Token.next_col loc) rest in
      let digits = c :: taken in
      Result.bind (nat_of_digits loc digits) (fun n ->
        go loc' rest' ({ Token.kind = Token.Nat n; loc } :: acc))
  | c :: rest when is_ident_start c ->
      let taken, loc', rest' = span is_ident_char (Token.next_col loc) rest in
      let s = List.to_seq (c :: taken) |> String.of_seq in
      go loc' rest' ({ Token.kind = ident_kind s; loc } :: acc)
  | c :: _rest ->
      (* a lone '-', neither "--" nor "->", lands here too *)
      lex_err loc (Printf.sprintf "unexpected character %C" c)

(** Run to the end of the line, advancing the column over the comment
    characters so the [Eof] position stays honest.  mirrors
    kan-lang-tot-pin/surface/lexer.ml:139-144. *)
and skip_comment (loc : Token.loc) (cs : char list) (acc : Token.t list) :
    (Token.t list, Error.t) result =
  match cs with
  | [] -> go loc [] acc
  | '\n' :: rest -> go (Token.next_line loc) rest acc
  | _other :: rest -> skip_comment (Token.next_col loc) rest acc

let lex (src : string) : (Token.t list, Error.t) result =
  go Token.start (String.to_seq src |> List.of_seq) []
