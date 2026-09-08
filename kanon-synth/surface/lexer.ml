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
    ("synth", Token.KSynth);
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

(** A finite byte lookup makes decimal escape decoding total, without
    relying on a character conversion that raises outside its domain. *)
let bytes : char list =
  "\000\001\002\003\004\005\006\007\008\009\010\011\012\013\014\015\
   \016\017\018\019\020\021\022\023\024\025\026\027\028\029\030\031\
   \032\033\034\035\036\037\038\039\040\041\042\043\044\045\046\047\
   \048\049\050\051\052\053\054\055\056\057\058\059\060\061\062\063\
   \064\065\066\067\068\069\070\071\072\073\074\075\076\077\078\079\
   \080\081\082\083\084\085\086\087\088\089\090\091\092\093\094\095\
   \096\097\098\099\100\101\102\103\104\105\106\107\108\109\110\111\
   \112\113\114\115\116\117\118\119\120\121\122\123\124\125\126\127\
   \128\129\130\131\132\133\134\135\136\137\138\139\140\141\142\143\
   \144\145\146\147\148\149\150\151\152\153\154\155\156\157\158\159\
   \160\161\162\163\164\165\166\167\168\169\170\171\172\173\174\175\
   \176\177\178\179\180\181\182\183\184\185\186\187\188\189\190\191\
   \192\193\194\195\196\197\198\199\200\201\202\203\204\205\206\207\
   \208\209\210\211\212\213\214\215\216\217\218\219\220\221\222\223\
   \224\225\226\227\228\229\230\231\232\233\234\235\236\237\238\239\
   \240\241\242\243\244\245\246\247\248\249\250\251\252\253\254\255"
  |> String.to_seq |> List.of_seq

(** Hint strings accept every escape emitted by [%S]. Unknown escapes and
    literal control characters fail before the parser sees a token. *)
let rec string_literal (start : Token.loc) (loc : Token.loc) (cs : char list)
    (acc : char list) : (string * Token.loc * char list, Error.t) result =
  match cs with
  | [] -> lex_err start "unterminated synthesis hint string"
  | '"' :: rest ->
      Ok (String.of_seq (List.to_seq (List.rev acc)), Token.next_col loc, rest)
  | '\\' :: ('\\' | '"' as c) :: rest ->
      string_literal start (Token.advance loc 2) rest (c :: acc)
  | '\\' :: 'n' :: rest ->
      string_literal start (Token.advance loc 2) rest ('\n' :: acc)
  | '\\' :: 'r' :: rest ->
      string_literal start (Token.advance loc 2) rest ('\r' :: acc)
  | '\\' :: 't' :: rest ->
      string_literal start (Token.advance loc 2) rest ('\t' :: acc)
  | '\\' :: 'b' :: rest ->
      string_literal start (Token.advance loc 2) rest ('\b' :: acc)
  | '\\' :: a :: b :: c :: rest when is_digit a && is_digit b && is_digit c ->
      let digit (d : char) : int = Char.code d - Char.code '0' in
      let code = (100 * digit a) + (10 * digit b) + digit c in
      List.find_opt (fun (byte : char) -> Int.equal (Char.code byte) code) bytes
      |> Option.fold ~none:(lex_err loc "string byte escape exceeds 255")
           ~some:(fun (byte : char) ->
             string_literal start (Token.advance loc 4) rest (byte :: acc))
  | '\\' :: _rest -> lex_err loc "invalid synthesis hint escape"
  | c :: _rest when Char.code c < 32 || Char.code c = 127 ->
      lex_err loc "control characters in synthesis hints must be escaped"
  | c :: rest -> string_literal start (Token.next_col loc) rest (c :: acc)

(* mirrors kan-lang-tot-pin/surface/lexer.ml:85-135, arm by arm *)
let rec go (loc : Token.loc) (cs : char list) (acc : Token.t list) :
    (Token.t list, Error.t) result =
  match cs with
  | [] -> Ok (List.rev ({ Token.kind = Token.Eof; loc } :: acc))
  | ' ' :: rest | '\t' :: rest | '\r' :: rest -> go (Token.next_col loc) rest acc
  | '\n' :: rest -> go (Token.next_line loc) rest acc
  | '"' :: rest ->
      Result.bind (string_literal loc (Token.next_col loc) rest [])
        (fun (hint, loc', rest') ->
          go loc' rest' ({ Token.kind = Token.Str hint; loc } :: acc))
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
