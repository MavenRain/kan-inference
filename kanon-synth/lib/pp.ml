(** Display-only printer for the kernel term.  Free variables print as
    [#n].  Nothing gates this printer at Stage A;  Stage B's goldens do.

    This file and shape.ml are the two files in lib/ that spell a shape
    name, so the R0-AUDIT gate leg excludes both. *)

(* mirrors kan-lang-tot-pin/lib/pp.ml:31, which reads the display name
   list with the partial-indexing combinator that plan section 11 bans,
   so the same total lookup is written here by structural recursion. *)
let rec nth_name (n : int) (names : string list) : string option =
  match names with
  | [] -> None
  | x :: rest -> if Int.equal n 0 then Some x else nth_name (n - 1) rest

(* mirrors kan-lang-tot-pin/lib/pp.ml:24-27 *)
let literal (l : Literal.t) : string =
  match l with
  | Literal.LString s -> "\"" ^ String.escaped s ^ "\""
  | Literal.LInt n -> Bignum.to_string n

let binder_names (bs : (Quantity.t * string) list) : string list =
  List.map (fun ((_q : Quantity.t), (x : string)) -> x) bs

let push (names : string list) (added : string list) : string list =
  List.fold_left (fun acc x -> x :: acc) names added

(* mirrors kan-lang-tot-pin/lib/pp.ml:29-78, arm by arm.  tot's Pi, Lam,
   App and Match arms become the two formers and the four schema
   constructors;  Var, Univ, Let, Ann, Global, Lit and Auto are tot's
   own arms, kept in tot's layout. *)
let rec shape (names : string list) (s : Term.t Shape.t) : string =
  match s with
  | Shape.SPi (q, x, dom) ->
      Printf.sprintf "SPi %s %s %s" (Quantity.to_string q) x (term names dom)
  | Shape.SColl n -> Printf.sprintf "SColl %d" n
  | Shape.SPar (a, b) -> Printf.sprintf "SPar %s %s" (term names a) (term names b)
  | Shape.SMu (n, ts) ->
      Printf.sprintf "SMu %s [%s]" n (String.concat "; " (List.map (term names) ts))
  | Shape.SNu (n, ts) ->
      Printf.sprintf "SNu %s [%s]" n (String.concat "; " (List.map (term names) ts))

(* the diagram of a point shape is scoped under that shape's binder;  the
   other four shapes bind nothing (plan section 4, diagram conventions). *)
and under (s : Term.t Shape.t) (names : string list) : string list =
  match s with
  | Shape.SPi (_, x, _) -> x :: names
  | Shape.SColl _ -> names
  | Shape.SPar (_, _) -> names
  | Shape.SMu (_, _) -> names
  | Shape.SNu (_, _) -> names

and term (names : string list) (tm : Term.t) : string =
  match tm with
  | Term.Var ix -> nth_name ix names |> Option.value ~default:(Printf.sprintf "#%d" ix)
  | Term.Univ l -> "Type " ^ Level.to_string l
  | Term.Lan (s, d) -> Printf.sprintf "(Lan %s %s)" (shape names s) (term (under s names) d)
  | Term.Ran (s, d) -> Printf.sprintf "(Ran %s %s)" (shape names s) (term (under s names) d)
  | Term.In (s, a, args) ->
      Printf.sprintf "(In %s %s [%s])" (shape names s) (addr names a)
        (String.concat "; " (List.map (term names) args))
  | Term.Elim e -> elim names e
  | Term.Sec (s, legs) ->
      Printf.sprintf "(Sec %s [%s])" (shape names s)
        (String.concat "; " (List.map (leg names) legs))
  | Term.Out (s, a, scrut) ->
      Printf.sprintf "(Out %s %s %s)" (shape names s) (addr names a) (term names scrut)
  | Term.Let (x, ty, def, body) ->
      Printf.sprintf "let %s : %s := %s in %s" x (term names ty) (term names def)
        (term (x :: names) body)
  | Term.Ann (tm', ty) -> Printf.sprintf "(%s : %s)" (term names tm') (term names ty)
  | Term.Global n -> n
  | Term.Lit l -> literal l
  | Term.Auto -> "auto"

and addr (names : string list) (a : Term.addr) : string =
  match a with
  | Term.APt (q, arg) -> Printf.sprintf "(APt %s %s)" (Quantity.to_string q) (term names arg)
  | Term.ALeg k -> Printf.sprintf "(ALeg %d)" k
  | Term.ACtor c -> Printf.sprintf "(ACtor %s)" c

and leg (names : string list) (lg : Term.leg) : string =
  let bnames = binder_names lg.Term.l_binders in
  Printf.sprintf "%s => %s" (String.concat " " bnames) (term (push names bnames) lg.Term.l_body)

(* mirrors kan-lang-tot-pin/lib/pp.ml:45-78, the Match arm.  The motive
   convention is tot's, stated at kan-lang-tot-pin/lib/term.ml:88-102:
   [m_body] is scoped under [m_idx] in declaration order and then under
   [m_self], and the display list runs the other way, so it is extended
   self first and then the indices reversed. *)
and elim (names : string list) (e : Term.elim) : string =
  let motive_s =
    e.Term.e_motive
    |> Option.fold ~none:"" ~some:(fun (mo : Term.motive) ->
           let names' = (mo.Term.m_self :: List.rev mo.Term.m_idx) @ names in
           Printf.sprintf " as %s return %s" mo.Term.m_self (term names' mo.Term.m_body))
  in
  let branch_s ((a : Term.addr), (lg : Term.leg)) : string =
    Printf.sprintf " | %s %s" (addr names a) (leg names lg)
  in
  Printf.sprintf "(Elim %s %s%s with%s)" (shape names e.Term.e_shape)
    (term names e.Term.e_scrut) motive_s
    (String.concat "" (List.map branch_s e.Term.e_branches))
