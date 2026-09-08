(** The M0 surface tree and its printer (SA-D2).  One constructor per
    production of SPEC.md section 9, plus application (SA-D1) and auto
    (SA-D3).  No node holds a position, so two trees compare with
    structural equality and the round-trip test needs no position
    normalisation.

    Mirrors kan-lang-tot-pin/surface/syntax.ml:1-105 for the layout of
    the tree and for [Loc]-free reading of a branch as a triple.  tot's
    positions, its data and class items and its IO sugar have no M0
    production and are left out.

    No constructor here spells a shape name, and no production is a
    former:  every form below maps to one kernel constructor through the
    sugar table of SPEC.md section 7. *)

(** The five nat primitives of plan section 8, one constructor each, so
    a match over them is exhaustive and no name is a bare string. *)
type prim =
  | PAdd
  | PSub
  | PMul
  | PEq
  | PLt

(** A binder, SPEC.md section 9:  "(" mark? name ":" term ")".  SA-D17:
    the mark "0" is [Quantity.Zero] and an absent mark is
    [Kanon_kernel.Quantity.Many].  SB-D3:  Stage B gives the mark "1"
    its own reading, [Kanon_kernel.Quantity.One], which the M0 checker
    counts as [Many] and the printer writes back as "1 ". *)
type binder = {
  b_q : Kanon_kernel.Quantity.t;
  b_name : string;
  b_ty : t;
}

(** A case motive, "as x [in FAMILY i1 .. im] return P".  M1 Stage H,
    brief 3.8:  the index clause is the minimum a fibered elimination
    needs, and it mirrors kan-lang-tot-pin/surface/parser.ml:227-236.
    [mo_ind] is the family the motive is built for, which the kernel
    checks against the family of the scrutinee (SH-D6), and [mo_idx]
    binds the index arguments beside the scrutinee binder (SH-D7).  An
    M0 motive writes neither, so [mo_ind] is [None] and [mo_idx] is
    empty and every M0 fixture keeps its text. *)
and motive = {
  mo_self : string;
  mo_ind : string option;
  mo_idx : string list;
  mo_body : t;
}

(** One field binder of a constructor keyed branch, "0 x" or "x".  A
    field takes its type from the family record (M1 Stage H, SH-D9).
    SL-D4 adds an optional annotation, checked against that type. *)
and field = {
  fd_q : Kanon_kernel.Quantity.t;
  fd_name : string;
  fd_ty : t option;
}

(** A case branch.  The M0 key is the leg number, which the elaborator
    reads as the leg address at Stage B.  M1 Stage H adds the
    constructor keyed branch of brief 3.8:  the key is a constructor
    name and the branch binds one field binder per constructor field,
    mirroring kan-lang-tot-pin/surface/parser.ml:288-299. *)
and branch =
  | BrLeg of int * binder list * t
  | BrCtor of string * field list * t

(** M1 Stage G, correction C7.  One constructor of a family, "| NAME :
    TYPE".  The type is an arrow chain:  its binders are the argument
    telescope, one quantity per field, and its result names the family at
    the result index expressions (brief 3.9). *)
and fam_ctor = {
  fc_name : string;
  fc_ty : t;
}

(** M1 Stage G, correction C7.  One member of a mu group:  the header
    with its parameter binders, then an arrow chain of index binders that
    ends in the declared universe, then the constructor list.  Stage L
    binder sugar translates directly into this same record (SL-D1). *)
and fam = {
  fm_name : string;
  fm_params : binder list;
  fm_ty : t;
  fm_ctors : fam_ctor list;
}

(** M1 Stage I, SI-D8.  One member of a recursive definition group:
    the name, the declared type and the body, which is the same triple
    the M0 [DDef] row carries.  A group of one is the direct case and a
    group of two or more is the mutual case, which is the reading the
    order of lib/order.ml takes (brief 3.2). *)
and rec_def = {
  rd_name : string;
  rd_ty : t;
  rd_body : t;
}

and t =
  | SVar of string
  | SNat of Kanon_kernel.Bignum.t
  | SProp
  | SType of int
  | SPrim of prim
  | SUnit
  | SAuto
  | SPair of t * t
  | STuple of t list
  | SSum of t list
      (** SB-D1.  [sum (A1, .., An)] is the left former at the
          collection shape over the diagram of its items, and the empty
          form [sum ()] takes its universe from an annotation. *)
  | SProd of t list  (** SB-D1.  The right former at the same shape. *)
  | SProj of t * int
      (** SA-D16.  One projection node for ".1", ".2" and ".k":  the
          three spell the same text for the same leg and the sugar
          table's two rows differ by the type of the scrutinee, which
          Stage B's elaborator reads and Stage A does not have. *)
  | SInj of int * int * t
  | SAbsurd of t
  | SApp of t * t
  | SFun of binder list * t
  | SArrow of binder * t
  | SStar of binder * t
  | SLet of string * t * t * t
  | SAnn of t * t
  | SCase of t * motive option * branch list
  | SMatch of t * motive option * branch list
      (** SL-D3: constructor elimination has its own surface node, so
          even an empty match must eliminate a family. *)

type decl =
  | DDef of string * t * t
  | DAxiom of string * t
  | DMu of fam list
      (** M1 Stage G:  a mutual group, one member per "mu" or "and"
          header.  Every member is declared before the first constructor
          of the group is installed (A4). *)
  | DRec of rec_def list
      (** M1 Stage I, SI-D8:  a recursive definition group, one member
          per "def rec" or "and" header.  The elaborator guards the
          whole group before it translates any member (SI-D9). *)

let prim_name (p : prim) : string =
  match p with
  | PAdd -> "natAdd"
  | PSub -> "natSub"
  | PMul -> "natMul"
  | PEq -> "natEq"
  | PLt -> "natLt"

(** Printing levels, loosest first, SPEC.md section 9.  Level 0 is a
    whole term, level 1 an application and level 2 an atom.  A node
    printed where a tighter level is wanted takes parentheses, which is
    the whole of the round-trip discipline:  [print] never emits text
    that re-parses to another tree. *)
let level_of (s : t) : int =
  match s with
  | SVar _ -> 2
  | SNat _ -> 2
  | SProp -> 2
  | SType _ -> 2
  | SPrim _ -> 2
  | SUnit -> 2
  | SAuto -> 2
  | SPair (_, _) -> 2
  | STuple _ -> 2
  | SSum _ -> 2
  | SProd _ -> 2
  | SProj (_, _) -> 2
  | SAnn (_, _) -> 2
  | SInj (_, _, _) -> 1
  | SAbsurd _ -> 1
  | SApp (_, _) -> 1
  | SFun (_, _) -> 0
  | SArrow (_, _) -> 0
  | SStar (_, _) -> 0
  | SLet (_, _, _, _) -> 0
  | SCase (_, _, _) -> 0
  | SMatch (_, _, _) -> 0

let mark (q : Kanon_kernel.Quantity.t) : string =
  match q with
  | Kanon_kernel.Quantity.Zero -> "0 "
  | Kanon_kernel.Quantity.One -> "1 "
  | Kanon_kernel.Quantity.Many -> ""

let rec at (lvl : int) (s : t) : string =
  let text = raw s in
  if level_of s >= lvl then text else "(" ^ text ^ ")"

and binder_text (b : binder) : string =
  Printf.sprintf "(%s%s : %s)" (mark b.b_q) b.b_name (at 0 b.b_ty)

(** A branch body and a motive body print at level 1, so a term that
    reaches to the right (a case, a fun, a let, an arrow or a star)
    takes parentheses and cannot swallow the branch bar that follows
    it. *)
and branch_text (br : branch) : string =
  match br with
  | BrLeg (k, bs, body) ->
      Printf.sprintf " | %d%s => %s" k
        (String.concat "" (List.map (fun (b : binder) -> " " ^ binder_text b) bs))
        (at 1 body)
  | BrCtor (c, fs, body) ->
      Printf.sprintf " | %s%s => %s" c
        (String.concat "" (List.map field_text fs))
        (at 1 body)

(** M1 Stage H:  a field binder prints its mark and its name, so the
    printed branch re-parses to the same field list. *)
and field_text (f : field) : string =
  f.fd_ty
  |> Option.fold ~none:(" " ^ mark f.fd_q ^ f.fd_name)
       ~some:(fun (ty : t) ->
         " " ^ binder_text { b_q = f.fd_q; b_name = f.fd_name; b_ty = ty })

(** M1 Stage H:  the index clause prints only when the motive names a
    family, so an M0 motive prints the text it printed at M0. *)
and motive_text (mo : motive) : string =
  Printf.sprintf " as %s%s return %s" mo.mo_self (ind_text mo) (at 1 mo.mo_body)

and ind_text (mo : motive) : string =
  mo.mo_ind
  |> Option.fold ~none:"" ~some:(fun (n : string) ->
         " in " ^ n ^ String.concat "" (List.map (fun (x : string) -> " " ^ x) mo.mo_idx))

and raw (s : t) : string =
  match s with
  | SVar x -> x
  | SNat n -> Kanon_kernel.Bignum.to_string n
  | SProp -> "Prop"
  | SType n -> "Type " ^ string_of_int n
  | SPrim p -> prim_name p
  | SUnit -> "()"
  | SAuto -> "auto"
  | SPair (a, b) -> Printf.sprintf "(%s, %s)" (at 0 a) (at 0 b)
  | STuple items ->
      Printf.sprintf "tuple (%s)" (String.concat ", " (List.map (at 0) items))
  | SSum items ->
      Printf.sprintf "sum (%s)" (String.concat ", " (List.map (at 0) items))
  | SProd items ->
      Printf.sprintf "prod (%s)" (String.concat ", " (List.map (at 0) items))
  | SProj (a, k) -> Printf.sprintf "%s.%d" (at 2 a) k
  | SInj (k, n, a) -> Printf.sprintf "inj %d of %d %s" k n (at 1 a)
  | SAbsurd a -> "absurd " ^ at 1 a
  | SApp (f, a) -> at 1 f ^ " " ^ at 2 a
  | SFun (bs, body) ->
      Printf.sprintf "fun %s => %s"
        (String.concat " " (List.map binder_text bs))
        (at 0 body)
  | SArrow (b, cod) -> binder_text b ^ " -> " ^ at 0 cod
  | SStar (b, cod) -> binder_text b ^ " * " ^ at 0 cod
  | SLet (x, ty, def, body) ->
      Printf.sprintf "let %s : %s := %s in %s" x (at 1 ty) (at 1 def) (at 0 body)
  | SAnn (a, ty) -> Printf.sprintf "(%s : %s)" (at 0 a) (at 0 ty)
  | SCase (scrut, mo, brs) ->
      Printf.sprintf "case %s%s with%s" (at 1 scrut)
        (mo |> Option.fold ~none:"" ~some:motive_text)
        (String.concat "" (List.map branch_text brs))
  | SMatch (scrut, mo, brs) ->
      Printf.sprintf "match %s%s with%s" (at 1 scrut)
        (mo |> Option.fold ~none:"" ~some:motive_text)
        (String.concat "" (List.map branch_text brs))

(** One constructor row of a mu group.  The row starts at the bar, so the
    printed text re-parses to the same list. *)
let fam_ctor_text (fc : fam_ctor) : string =
  Printf.sprintf "| %s : %s\n" fc.fc_name (at 0 fc.fc_ty)

(** SL-D5: every family prints with :=.  A mutual group prints one mu
    declaration per member and one closing end.  Constructor types
    remain expanded arrow chains, so binder sugar needs no extra node. *)
let fam_text (word : string) (fm : fam) : string =
  Printf.sprintf "%s %s%s : %s :=\n%s" word fm.fm_name
    (String.concat "" (List.map (fun (b : binder) -> " " ^ binder_text b) fm.fm_params))
    (at 0 fm.fm_ty)
    (String.concat "" (List.map fam_ctor_text fm.fm_ctors))

let decl_text (d : decl) : string =
  match d with
  | DDef (name, ty, def) ->
      Printf.sprintf "def %s : %s := %s\n" name (at 0 ty) (at 0 def)
  | DAxiom (name, ty) -> Printf.sprintf "axiom %s : %s\n" name (at 0 ty)
  | DMu [] -> ""
  | DMu [ fm ] -> fam_text "mu" fm
  | DMu ((_first :: _second :: _rest) as fams) ->
      "mutual\n" ^ String.concat "" (List.map (fam_text "mu") fams) ^ "end\n"
  | DRec ms ->
      String.concat ""
        (List.mapi
           (fun (i : int) (m : rec_def) ->
             Printf.sprintf "%s %s : %s := %s\n"
               (if Int.equal i 0 then "def rec" else "and")
               m.rd_name (at 0 m.rd_ty) (at 0 m.rd_body))
           ms)

(** The printer of SA-D2:  its output re-parses to an equal tree.  An
    empty tree prints as the empty text, which parses back to the empty
    tree. *)
let print (ds : decl list) : string = String.concat "" (List.map decl_text ds)
