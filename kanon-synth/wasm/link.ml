(** One pass from the erased rows to indices.  link.ml parses the tid
    texts of the erased form, dedups them by text, orders the composite
    types and the functions, and answers an index for every name emit.ml
    needs.  The emitter never computes an index (eterm.ml, repair one).

    The repr of a term is inferred here too (SD-D20):  the type table
    needs the repr of every capture and of every let, so inference and
    index assignment are the same walk over the program.

    No shape name appears in this file. *)

module E = Kanon_kernel.Eterm
module Err = Kanon_kernel.Error
module P = Kanon_kernel.Prim
module G = Gc_encode

let ( let* ) = Result.bind

let rec seq (xs : ('a, Err.t) result list) : ('a list, Err.t) result =
  match xs with
  | [] -> Ok []
  | x :: rest ->
      let* v = x in
      let* vs = seq rest in
      Ok (v :: vs)

(** The total reader of a list position (SD-D22).  A position outside the
    list answers [None], and a negative position walks the list down to
    the empty case, so the reader is total and terminates. *)
let rec nth_at (xs : 'a list) (i : int) : 'a option =
  match (xs, i) with
  | [], _k -> None
  | x :: _rest, 0 -> Some x
  | _x :: rest, k -> nth_at rest (k - 1)

let first_some (fs : (unit -> 'a option) list) : 'a option =
  List.fold_left
    (fun (acc : 'a option) (f : unit -> 'a option) ->
      if Option.is_some acc then acc else f ())
    None fs

(* ---------- the tid grammar ---------- *)

let slice (s : string) (start : int) (len : int) : string =
  if start >= 0 && len >= 0 && start + len <= String.length s then
    String.sub s start len (* @total-accessor *)
  else ""

(** The text between a prefix and the closing angle bracket. *)
let inside (prefix : string) (s : string) : string option =
  if String.starts_with ~prefix s && String.ends_with ~suffix:">" s then
    Some (slice s (String.length prefix) (String.length s - String.length prefix - 1))
  else None

(** Split on a separator at bracket depth zero, so a nested tid text
    keeps its own separators. *)
let split_top (sep : char) (s : string) : string list =
  let one (c : char) : string = String.make 1 c in
  let _depth, cur, acc =
    String.fold_left
      (fun ((d : int), (cur : string), (acc : string list)) (c : char) ->
        match () with
        | () when Char.equal c '<' -> (d + 1, cur ^ one c, acc)
        | () when Char.equal c '>' -> (d - 1, cur ^ one c, acc)
        | () when Char.equal c sep && Int.equal d 0 -> (d, "", acc @ [ cur ])
        | () -> (d, cur ^ one c, acc))
      (0, "", []) s
  in
  acc @ [ cur ]

let repr_of_text (s : string) : (E.repr, Err.t) result =
  let tail (p : string) : string =
    slice s (String.length p) (String.length s - String.length p)
  in
  match () with
  | () when String.equal s "i31" -> Ok E.RI31
  | () when String.starts_with ~prefix:"struct " s ->
      Ok (E.RStruct (E.Tid (tail "struct ")))
  | () when String.starts_with ~prefix:"union " s ->
      Ok (E.RUnion (E.Tid (tail "union ")))
  | () when String.starts_with ~prefix:"func " s -> Ok (E.RFunc (E.Tid (tail "func ")))
  | () when String.starts_with ~prefix:"thunk " s ->
      Ok (E.RThunk (E.Tid (tail "thunk ")))
  | () -> Error (Err.Mismatch ("a repr does not parse:  " ^ s))

type leg =
  | LUnit  (** a payload free leg *)
  | LRepr of E.repr  (** the one field of an M0 sum leg (SD-D21) *)
  | LMu of string * E.repr list
      (** a leg of a mu family:  the tid the erasure publishes and one
          repr per runtime field, in declaration order (SJ-D21) *)

type form =
  | FI31
  | FUnit
  | FAny
  | FFields of E.repr list  (** pair and tuple *)
  | FSum of leg list
  | FFn of int

let parse_fields (body : string) : (E.repr list, Err.t) result =
  if String.equal body "" then Ok [] else seq (List.map repr_of_text (split_top ',' body))

let parse_legs (body : string) : (leg list, Err.t) result =
  if String.equal body "" then Ok []
  else
    seq
      (List.map
         (fun (t : string) ->
           if String.equal t "unit" then Ok LUnit
           else Result.map (fun (r : E.repr) -> LRepr r) (repr_of_text t))
         (split_top '|' body))

let parse_tid (t : string) : (form, Err.t) result =
  let wrapped (pfx : string) (k : string -> (form, Err.t) result) :
      unit -> (form, Err.t) result option =
   fun () -> Option.map k (inside pfx t)
  in
  let word (w : string) (f : form) : unit -> (form, Err.t) result option =
   fun () -> if String.equal t w then Some (Ok f) else None
  in
  first_some
    [
      word "i31" FI31;
      word "unit" FUnit;
      word "any" FAny;
      wrapped "fn<" (fun (b : string) ->
          Option.fold
            ~none:(Error (Err.Mismatch ("an arity does not parse:  " ^ t)))
            ~some:(fun (n : int) -> Ok (FFn n))
            (int_of_string_opt b));
      wrapped "pair<" (fun (b : string) ->
          Result.map (fun (rs : E.repr list) -> FFields rs) (parse_fields b));
      wrapped "tuple<" (fun (b : string) ->
          Result.map (fun (rs : E.repr list) -> FFields rs) (parse_fields b));
      wrapped "sum<" (fun (b : string) ->
          Result.map (fun (ls : leg list) -> FSum ls) (parse_legs b));
    ]
  |> Option.fold
       ~none:(Error (Err.Mismatch ("a tid does not parse:  " ^ t)))
       ~some:Fun.id

(** A leg tid of a mu family reads [leg<mu<NAME>,K,R1,...,Rn>]:  the
    family tid, the constructor index and one repr per runtime field
    (SJ-D21).  The answer carries the tid text itself, because the text
    is the type key and the erasure alone writes it.  Any other leg text
    belongs to an M0 sum and answers [None]. *)
let parse_mu_leg (t : string) : (string * string * int * E.repr list) option =
  let fields (fam : string) (k : int) (rest : string list) :
      (string * string * int * E.repr list) option =
    Result.fold
      ~ok:(fun (rs : E.repr list) -> Some (t, fam, k, rs))
      ~error:(fun (_e : Err.t) -> None)
      (seq (List.map repr_of_text rest))
  in
  let parts (ps : string list) : (string * string * int * E.repr list) option =
    match ps with
    | [] -> None
    | [ _one ] -> None
    | fam :: idx :: rest ->
        if String.starts_with ~prefix:"mu<" fam then
          Option.fold ~none:None ~some:(fun (k : int) -> fields fam k rest)
            (int_of_string_opt idx)
        else None
  in
  Option.fold ~none:None ~some:parts (Option.map (split_top ',') (inside "leg<" t))

let tid_text (r : E.repr) : string option =
  match r with
  | E.RI31 -> None
  | E.RStruct (E.Tid t) -> Some t
  | E.RUnion (E.Tid t) -> Some t
  | E.RFunc (E.Tid t) -> Some t
  | E.RThunk (E.Tid t) -> Some t

(* ---------- the program table ---------- *)

type fn = {
  params : E.repr list;
  result : E.repr;
  body : E.ktm;
}

type prog = {
  funs : (string * fn) list;  (** every KFun of every entry, in order *)
  posts : (string * E.repr) list;  (** the axioms with a runtime type *)
  mus : (string * leg list) list;
      (** the legs of every mu family, by family tid and in constructor
          order.  A mu family is nominal, so its legs come from the rec
          groups the erasure publishes and never from its tid text
          (SJ-D22, SJ-D23) *)
}

let clos_key : string = "clos"
let fn_key (n : int) : string = Printf.sprintf "fn<%d>" n
let apply_ty_key (k : int) : string = Printf.sprintf "applyfn<%d>" k
let pap_key (m : int) (k : int) : string = Printf.sprintf "pap<%d,%d>" m k
let entry_ty_key : string = "entryfn"
let nat_repr : E.repr = E.RUnion (E.Tid "nat")
let limb_key : string = "nat-limbs"
let big_key : string = "nat-big"
let runtime_ty_key (n : string) : string = "nat-sig:" ^ n
let runtime_fkey (n : string) : string = "nat-runtime:" ^ n

(** Private helper signatures: n is an eq reference, a is a limb array,
    and i is i32. The linker owns both signature and function indices. *)
let runtime_sigs : (string * string list * string) list =
  [
    ("length", [ "n" ], "i");
    ("digit", [ "n"; "i" ], "i");
    ("copy", [ "a"; "a"; "i"; "i" ], "a");
    ("normal", [ "a"; "i" ], "n");
    ("compareDigits", [ "n"; "n"; "i" ], "i");
    ("compare", [ "n"; "n" ], "i");
    ("addLoop", [ "n"; "n"; "a"; "i"; "i"; "i" ], "n");
    ("subLoop", [ "n"; "n"; "a"; "i"; "i"; "i" ], "n");
    ("mulLoop", [ "n"; "n"; "a"; "i"; "i"; "i" ], "n");
    ("slowAdd", [ "n"; "n" ], "n");
    ("slowSub", [ "n"; "n" ], "n");
    ("slowMul", [ "n"; "n" ], "n");
    ("natAdd", [ "n"; "n" ], "n");
    ("natSub", [ "n"; "n" ], "n");
    ("natMul", [ "n"; "n" ], "n");
    ("natEq", [ "n"; "n" ], "n");
    ("natLt", [ "n"; "n" ], "n");
  ]

let leg_key (rs : E.repr list) : string =
  "leg<" ^ String.concat "," (List.map E.print_repr rs) ^ ">"

(** The runtime fields a leg carries, in declaration order. *)
let leg_fields (l : leg) : E.repr list =
  match l with
  | LUnit -> []
  | LRepr r -> [ r ]
  | LMu (_t, rs) -> rs

(** The type key and the fields of a leg that has a struct.  A payload
    free leg is a tagged integer and has no type at all (SD-D5). *)
let leg_type (l : leg) : (string * E.repr list) option =
  match l with
  | LUnit -> None
  | LRepr r -> Some (leg_key [ r ], [ r ])
  | LMu (t, rs) -> Some (t, rs)

let sig_key (params : E.repr list) (result : E.repr) : string =
  "sig<"
  ^ String.concat "," (List.map E.print_repr params)
  ^ "->" ^ E.print_repr result ^ ">"

let env_tid (rs : E.repr list) : string =
  "tuple<" ^ String.concat "," (List.map E.print_repr rs) ^ ">"

let fun_fkey (name : string) : string = "fun:" ^ name
let wrap_fkey (name : string) (caps : int) : string = Printf.sprintf "wrap:%s:%d" name caps
let apply_fkey (k : int) : string = Printf.sprintf "apply:%d" k
let papw_fkey (m : int) (k : int) : string = Printf.sprintf "papw:%d:%d" m k
let entry_fkey : string = "entry"

let decls_of_entry (e : Kanon_kernel.Erase.entry) : E.kdecl list =
  match e with
  | Kanon_kernel.Erase.Dropped -> []
  | Kanon_kernel.Erase.Postulate _ -> []
  | Kanon_kernel.Erase.Code ds -> ds

let fn_of_decl (d : E.kdecl) : (string * fn) list =
  match d with
  | E.KFun (E.Fid f, params, result, body) -> [ (f, { params; result; body }) ]
  | E.KRec _ -> []

let post_of_row ((name : string), (e : Kanon_kernel.Erase.entry)) : (string * E.repr) list =
  match e with
  | Kanon_kernel.Erase.Postulate r -> [ (name, r) ]
  | Kanon_kernel.Erase.Dropped -> []
  | Kanon_kernel.Erase.Code _ -> []

let rec_tids (d : E.kdecl) : string list =
  match d with
  | E.KFun (_f, _ps, _r, _b) -> []
  | E.KRec ts -> List.map E.tid_text ts

(** The legs of one family, at the position of the constructor index.
    Every leg of a family is published, so a position no row names is a
    payload free leg and holds no struct type (SD-D5). *)
let legs_in_order (xs : (int * leg) list) : leg list =
  let top : int =
    List.fold_left
      (fun (m : int) (((k : int), (_l : leg)) : int * leg) -> if k > m then k else m)
      (-1) xs
  in
  List.init (top + 1) (fun (i : int) ->
      Option.value ~default:LUnit (List.assoc_opt i xs))

(** The mu families of the erased rows.  One pass over the rec group of
    every definition gives the leg tids, and a leg tid names its family,
    its constructor index and its runtime fields (SJ-D23). *)
let mu_table (rows : (string * Kanon_kernel.Erase.entry) list) : (string * leg list) list
    =
  let rs : (string * string * int * E.repr list) list =
    List.concat_map
      (fun ((_n : string), (e : Kanon_kernel.Erase.entry)) ->
        List.concat_map
          (fun (d : E.kdecl) -> List.filter_map parse_mu_leg (rec_tids d))
          (decls_of_entry e))
      rows
  in
  let fams : string list =
    List.fold_left
      (fun (acc : string list)
           (((_t : string), (f : string), (_k : int), (_x : E.repr list)) :
             string * string * int * E.repr list) ->
        if List.mem f acc then acc else acc @ [ f ])
      [] rs
  in
  List.map
    (fun (f : string) ->
      ( f,
        legs_in_order
          (List.filter_map
             (fun (((t : string), (g : string), (k : int), (fs : E.repr list)) :
                    string * string * int * E.repr list) ->
               if String.equal g f then
                 Some
                   (k, if Int.equal (List.length fs) 0 then LUnit else LMu (t, fs))
               else None)
             rs) ))
    fams

let program_table (rows : (string * Kanon_kernel.Erase.entry) list) : prog =
  {
    funs =
      List.concat_map
        (fun ((_n : string), (e : Kanon_kernel.Erase.entry)) ->
          List.concat_map fn_of_decl (decls_of_entry e))
        rows;
    posts = List.concat_map post_of_row rows;
    mus = mu_table rows;
  }

(** The result repr of a primitive.  natEq and natLt answer the two leg
    sum of the unit type, which is what a boolean is at M0. *)
let prim_result (p : P.t) : E.repr =
  match p with
  | P.Nat_add -> nat_repr
  | P.Nat_sub -> nat_repr
  | P.Nat_mul -> nat_repr
  | P.Nat_eq -> E.RUnion (E.Tid "sum<unit|unit>")
  | P.Nat_lt -> E.RUnion (E.Tid "sum<unit|unit>")

let prim_params : E.repr list = [ nat_repr; nat_repr ]

(** What a head of an application is.  A global with a known arity calls
    through its typed signature;  anything else is a closure value. *)
type headk =
  | HFun of string * fn
  | HPrim of P.t
  | HValue

let head_kind (p : prog) (h : E.ktm) : headk =
  match h with
  | E.KGlobal n ->
      List.assoc_opt n p.funs
      |> Option.fold
           ~none:
             (P.of_name n |> Option.fold ~none:HValue ~some:(fun (x : P.t) -> HPrim x))
           ~some:(fun (f : fn) -> HFun (n, f))
  | E.KVar _ | E.KLit _ | E.KErased | E.KLet _ | E.KClos _ | E.KApp _ | E.KTail _
  | E.KStruct _ | E.KProj _ | E.KTag _ | E.KCase _ | E.KDelay _ | E.KForce _ ->
      HValue

(* ---------- repr inference ---------- *)

let sum_legs (t : string) : (leg list, Err.t) result =
  let* f = parse_tid t in
  match f with
  | FSum ls -> Ok ls
  | FI31 | FUnit | FAny | FFields _ | FFn _ ->
      Error (Err.Mismatch ("a case scrutinee is not a sum:  " ^ t))

(** The legs of a case scrutinee or of a constructor.  A mu family is
    nominal, so its legs come from the table of the rec groups;  an M0
    sum reads its own structural tid text (SJ-D22). *)
let sum_legs_p (p : prog) (t : string) : (leg list, Err.t) result =
  Option.fold ~none:(sum_legs t)
    ~some:(fun (ls : leg list) -> Ok ls)
    (List.assoc_opt t p.mus)

let fields_of (t : string) : (E.repr list, Err.t) result =
  let* f = parse_tid t in
  match f with
  | FFields rs -> Ok rs
  | FI31 | FUnit | FAny | FSum _ | FFn _ ->
      Error (Err.Mismatch ("a struct tid is not a pair or a tuple:  " ^ t))

let arity_of_fn (t : string) : (int, Err.t) result =
  let* f = parse_tid t in
  match f with
  | FFn n -> Ok n
  | FI31 | FUnit | FAny | FSum _ | FFields _ ->
      Error (Err.Mismatch ("a function repr is not fn<n>:  " ^ t))

let any_repr : E.repr = E.RUnion (E.Tid "any")

(** Construction, registration and the wrapper share the lifted
    function's capture signature, even when a capture expression is
    inferred as any after a generic call. *)
let capture_reprs (p : prog) (name : string) (count : int) :
    (E.repr list, Err.t) result =
  let* f = List.assoc_opt name p.funs
    |> Option.to_result ~none:(Err.Unbound ("no function named " ^ name)) in
  if count < 0 || count > List.length f.params then
    Error (Err.Mismatch ("invalid capture count for " ^ name))
  else Ok (List.filteri (fun (i : int) (_r : E.repr) -> i < count) f.params)

(** The leg a branch reads. *)
let branch_leg (p : prog) (scrut : E.repr) (b : E.kbranch) : (leg, Err.t) result =
  tid_text scrut
  |> Option.fold
       ~none:(Error (Err.Mismatch "a case scrutinee has no tid"))
       ~some:(fun (t : string) ->
         let* ls = sum_legs_p p t in
         nth_at ls b.E.tag
         |> Option.fold
              ~none:(Error (Err.Wrong_leg (Printf.sprintf "leg %d of %s" b.E.tag t)))
              ~some:(fun (l : leg) -> Ok l))

(** The binders a branch adds, innermost first.  A leg of an M0 sum
    carries one field or none (SD-D21) and a leg of a mu family carries
    one binder per runtime field in declaration order, so the last
    runtime field is the innermost binder (SJ-D25). *)
let branch_binders (p : prog) (scrut : E.repr) (b : E.kbranch) :
    (E.repr list, Err.t) result =
  if Int.equal b.E.arity 0 then Ok []
  else
    let* l = branch_leg p scrut b in
    let fs : E.repr list = leg_fields l in
    if Int.equal (List.length fs) b.E.arity then Ok (List.rev fs)
    else
      Error
        (Err.Mismatch
           (Printf.sprintf "leg %d binds %d fields and the branch binds %d" b.E.tag
              (List.length fs) b.E.arity))

(** The generic steps of an application whose head is already a value.
    A head of a known arity calls its code directly (SD-D3);  anything
    else goes through the apply helper of SD-D4. *)
type step =
  | SCallRef of int
  | SApply of int

let rec steps_of (r : E.repr) (k : int) : (step list, Err.t) result =
  if Int.equal k 0 then Ok []
  else
    match r with
    | E.RFunc (E.Tid t) ->
        let* m = arity_of_fn t in
        if m > 0 && m <= k then
          Result.map (fun (rest : step list) -> SCallRef m :: rest) (steps_of any_repr (k - m))
        else Ok [ SApply k ]
    | E.RUnion _ -> Ok [ SApply k ]
    | E.RI31 | E.RStruct _ ->
        Error (Err.Mismatch "an application head is not a function")
    | E.RThunk _ -> Error (Err.Not_yet "KForce arrives at M2")

let rec steps_result (r : E.repr) (k : int) : (E.repr, Err.t) result =
  if Int.equal k 0 then Ok r
  else
    match r with
    | E.RFunc (E.Tid t) ->
        let* m = arity_of_fn t in
        (match () with
        | () when m > 0 && m <= k -> steps_result any_repr (k - m)
        | () when m > k -> Ok (E.RFunc (E.Tid (fn_key (m - k))))
        | () -> Ok any_repr)
    | E.RUnion _ -> Ok any_repr
    | E.RI31 | E.RStruct _ ->
        Error (Err.Mismatch "an application head is not a function")
    | E.RThunk _ -> Error (Err.Not_yet "KForce arrives at M2")

let rec infer (p : prog) (env : E.repr list) (tm : E.ktm) : (E.repr, Err.t) result =
  match tm with
  | E.KVar i ->
      nth_at env i
      |> Option.fold
           ~none:(Error (Err.Unbound (Printf.sprintf "KVar %d is out of scope" i)))
           ~some:(fun (r : E.repr) -> Ok r)
  | E.KLit _l -> Ok nat_repr
  | E.KGlobal n -> global_repr p n
  | E.KErased -> Ok any_repr
  | E.KLet (_x, v, b) ->
      let* vr = infer p env v in
      infer p (vr :: env) b
  | E.KClos (_f, n, _caps) -> Ok (E.RFunc (E.Tid (fn_key n)))
  | E.KApp (h, args) -> app_repr p env h args
  | E.KTail (h, args) -> app_repr p env h args
  | E.KStruct (t, _fs) -> Ok (E.RStruct t)
  | E.KProj (E.Tid t, k, _x) ->
      let* rs = fields_of t in
      nth_at rs k
      |> Option.fold
           ~none:(Error (Err.Wrong_leg (Printf.sprintf "field %d of %s" k t)))
           ~some:(fun (r : E.repr) -> Ok r)
  | E.KTag (t, _k, _ps) -> Ok (E.RUnion t)
  | E.KCase (tid, _s, bs) -> (
      match bs with
      | [] -> Ok any_repr
      | b :: _rest ->
          let* binders = branch_binders p (E.RUnion tid) b in
          infer p (binders @ env) b.E.body)
  | E.KDelay (_f, _cs) -> Error (Err.Not_yet "KDelay arrives at M2")
  | E.KForce _x -> Error (Err.Not_yet "KForce arrives at M2")

and global_repr (p : prog) (n : string) : (E.repr, Err.t) result =
  match head_kind p (E.KGlobal n) with
  | HFun (_name, f) ->
      if Int.equal (List.length f.params) 0 then Ok f.result
      else Ok (E.RFunc (E.Tid (fn_key (List.length f.params))))
  | HPrim _pr -> Ok (E.RFunc (E.Tid (fn_key 2)))
  | HValue ->
      List.assoc_opt n p.posts
      |> Option.fold
           ~none:(Error (Err.Unbound ("no runtime declaration for " ^ n)))
           ~some:(fun (_r : E.repr) ->
             Error (Err.Unbound ("axiom " ^ n ^ " has no body")))

and app_repr (p : prog) (env : E.repr list) (h : E.ktm) (args : E.ktm list) :
    (E.repr, Err.t) result =
  let k : int = List.length args in
  if Int.equal k 0 then infer p env h
  else
    match head_kind p h with
    | HFun (_n, f) -> after_head (List.length f.params) f.result k
    | HPrim pr -> after_head 2 (prim_result pr) k
    | HValue ->
        let* hr = infer p env h in
        steps_result hr k

and after_head (m : int) (res : E.repr) (k : int) : (E.repr, Err.t) result =
  match () with
  | () when Int.equal k m -> Ok res
  | () when k > m -> steps_result res (k - m)
  | () -> steps_result (E.RFunc (E.Tid (fn_key m))) k

(* ---------- the keys the program needs ---------- *)

type tspec =
  | TSLimbs
  | TSBigNat
  | TSRuntime of string list * string
  | TSClos
  | TSFn of int
  | TSStruct of E.repr list
  | TSLeg of E.repr list
  | TSPap of int
  | TSSig of E.repr list * E.repr
  | TSApply of int
  | TSEntry

type fspec =
  | FSRuntime of string
  | FSProg of string
  | FSWrap of string * int
  | FSApply of int
  | FSPapw of int * int
  | FSEntry

type keys = {
  tys : (string * tspec) list;
  fns : (string * fspec) list;
}

let no_keys : keys = { tys = []; fns = [] }
let merge (a : keys) (b : keys) : keys = { tys = a.tys @ b.tys; fns = a.fns @ b.fns }
let merge_all (xs : keys list) : keys = List.fold_left merge no_keys xs
let ty_key (k : string) (s : tspec) : keys = { tys = [ (k, s) ]; fns = [] }
let fn_key_of (k : string) (s : fspec) : keys = { tys = []; fns = [ (k, s) ] }
let clos_keys : keys = ty_key clos_key TSClos
let fnty_keys (n : int) : keys = merge clos_keys (ty_key (fn_key n) (TSFn n))

let nat_data_keys : keys =
  merge (ty_key limb_key TSLimbs) (ty_key big_key TSBigNat)

let nat_runtime_keys : keys =
  merge nat_data_keys
    (merge_all
       (List.map
          (fun (((n : string), (ps : string list), (r : string)) :
                 string * string list * string) ->
            merge (ty_key (runtime_ty_key n) (TSRuntime (ps, r)))
              (fn_key_of (runtime_fkey n) (FSRuntime n)))
          runtime_sigs))

let rec need_repr (r : E.repr) : (keys, Err.t) result =
  match r with
  | E.RI31 -> Ok no_keys
  | E.RUnion (E.Tid t) ->
      Ok (if String.equal t "nat" then nat_data_keys else no_keys)
  | E.RStruct (E.Tid t) -> need_struct t
  | E.RFunc (E.Tid t) ->
      let* n = arity_of_fn t in
      Ok (fnty_keys n)
  | E.RThunk _t -> Error (Err.Not_yet "RThunk arrives at M2")

and need_struct (t : string) : (keys, Err.t) result =
  let* rs = fields_of t in
  let* inner = seq (List.map need_repr rs) in
  Ok (merge (ty_key t (TSStruct rs)) (merge_all inner))

(** Every leg of the family enters the type table, so a case on one
    constructor still brings the struct of every other leg and the rec
    group of 3.6 holds the whole family (D-M1-5). *)
let need_sum (p : prog) (t : string) : (keys, Err.t) result =
  let* ls = sum_legs_p p t in
  let* inner =
    seq
      (List.map
         (fun (l : leg) ->
           Option.fold ~none:(Ok no_keys)
             ~some:(fun (((key : string), (rs : E.repr list)) : string * E.repr list) ->
               let* ks = seq (List.map need_repr rs) in
               Ok (merge (merge_all ks) (ty_key key (TSLeg rs))))
             (leg_type l))
         ls)
  in
  Ok (merge_all inner)

let need_steps (ss : step list) : keys =
  merge_all
    (List.map
       (fun (s : step) ->
         match s with
         | SCallRef m -> fnty_keys m
         | SApply k ->
             merge_all
               [
                 clos_keys;
                 ty_key (apply_ty_key k) (TSApply k);
                 fn_key_of (apply_fkey k) (FSApply k);
               ])
       ss)

(** The wrapper a global needs when it is a value and not a call. *)
let need_wrap (p : prog) (n : string) : (keys, Err.t) result =
  match head_kind p (E.KGlobal n) with
  | HFun (_x, f) ->
      let m : int = List.length f.params in
      let* ps = seq (List.map need_repr f.params) in
      let* rr = need_repr f.result in
      Ok
        (merge_all
           [
             fnty_keys m;
             fn_key_of (wrap_fkey n 0) (FSWrap (n, 0));
             merge_all ps;
             rr;
           ])
  | HPrim _pr ->
      Ok (merge_all [ nat_runtime_keys; fnty_keys 2;
        fn_key_of (wrap_fkey n 0) (FSWrap (n, 0)) ])
  | HValue -> Result.map (fun (_r : E.repr) -> no_keys) (global_repr p n)

(** The walk that collects every key.  Lets use expression inference;
    captures use the lifted signature and cases use their retained tid. *)
let rec walk (p : prog) (env : E.repr list) (tm : E.ktm) : (keys, Err.t) result =
  match tm with
  | E.KVar _i -> Ok no_keys
  | E.KLit _l -> Ok nat_data_keys
  | E.KErased -> Ok no_keys
  | E.KGlobal n -> (
      match head_kind p (E.KGlobal n) with
      | HFun (_x, f) ->
          if Int.equal (List.length f.params) 0 then Ok no_keys else need_wrap p n
      | HPrim _pr -> need_wrap p n
      | HValue -> Result.map (fun (_r : E.repr) -> no_keys) (global_repr p n))
  | E.KLet (_x, v, b) ->
      let* kv = walk p env v in
      let* vr = infer p env v in
      let* kr = need_repr vr in
      let* kb = walk p (vr :: env) b in
      Ok (merge_all [ kv; kr; kb ])
  | E.KClos (E.Fid f, n, caps) ->
      let* kc = seq (List.map (walk p env) caps) in
      let* crs = capture_reprs p f (List.length caps) in
      let* krs = seq (List.map need_repr crs) in
      let* kenv =
        if Int.equal (List.length crs) 0 then Ok no_keys else need_struct (env_tid crs)
      in
      Ok
        (merge_all
           [
             fnty_keys n;
             fn_key_of (wrap_fkey f (List.length caps)) (FSWrap (f, List.length caps));
             kenv;
             merge_all kc;
             merge_all krs;
           ])
  | E.KApp (h, args) -> walk_app p env h args
  | E.KTail (h, args) -> walk_app p env h args
  | E.KStruct (E.Tid t, fs) ->
      let* kt = need_struct t in
      let* kf = seq (List.map (walk p env) fs) in
      Ok (merge kt (merge_all kf))
  | E.KProj (E.Tid t, _k, x) ->
      let* kt = need_struct t in
      let* kx = walk p env x in
      Ok (merge kt kx)
  | E.KTag (E.Tid t, _k, ps) ->
      let* kt = need_sum p t in
      let* kp = seq (List.map (walk p env) ps) in
      Ok (merge kt (merge_all kp))
  | E.KCase (E.Tid t, s, bs) ->
      let* ks = walk p env s in
      let sr = E.RUnion (E.Tid t) in
      let* ksum =
        match bs with
        | [] -> Ok no_keys
        | _b :: _rest -> need_sum p t
      in
      let* rr = infer p env tm in
      let* krr = need_repr rr in
      let* kbs =
        seq
          (List.map
             (fun (b : E.kbranch) ->
               let* binders = branch_binders p sr b in
               let* kb = walk p (binders @ env) b.E.body in
               let* kbind = seq (List.map need_repr binders) in
               Ok (merge kb (merge_all kbind)))
             bs)
      in
      Ok (merge_all [ ks; ksum; krr; merge_all kbs ])
  | E.KDelay (_f, _cs) -> Error (Err.Not_yet "KDelay arrives at M2")
  | E.KForce _x -> Error (Err.Not_yet "KForce arrives at M2")

and walk_app (p : prog) (env : E.repr list) (h : E.ktm) (args : E.ktm list) :
    (keys, Err.t) result =
  let k : int = List.length args in
  let* ka = seq (List.map (walk p env) args) in
  if Int.equal k 0 then
    let* kh = walk p env h in
    Ok (merge kh (merge_all ka))
  else
    let saturated (m : int) (res : E.repr) : (keys, Err.t) result =
      let* ss = steps_of res (k - m) in
      Ok (merge (merge_all ka) (need_steps ss))
    in
    let under (n : string) (m : int) : (keys, Err.t) result =
      let* kw = need_wrap p n in
      let* ss = steps_of (E.RFunc (E.Tid (fn_key m))) k in
      Ok (merge_all [ merge_all ka; kw; need_steps ss ])
    in
    match head_kind p h with
    | HFun (n, f) ->
        let m : int = List.length f.params in
        if k >= m then saturated m f.result else under n m
    | HPrim pr ->
        let* kp =
          if k >= 2 then saturated 2 (prim_result pr) else under (P.name pr) 2 in
        Ok (merge nat_runtime_keys kp)
    | HValue ->
        let* kh = walk p env h in
        let* hr = infer p env h in
        let* ss = steps_of hr k in
        Ok (merge_all [ kh; merge_all ka; need_steps ss ])

let walk_fun (p : prog) (((name : string), (f : fn)) : string * fn) :
    (keys, Err.t) result =
  let* ps = seq (List.map need_repr f.params) in
  let* rr = need_repr f.result in
  let* kb = walk p (List.rev f.params) f.body in
  Ok
    (merge_all
       [
         ty_key (sig_key f.params f.result) (TSSig (f.params, f.result));
         fn_key_of (fun_fkey name) (FSProg name);
         merge_all ps;
         rr;
         kb;
       ])

(* ---------- the closure over the helper arities ---------- *)

let dedup_int (xs : int list) : int list =
  List.fold_left
    (fun (acc : int list) (x : int) -> if List.mem x acc then acc else acc @ [ x ])
    [] xs

let dedup_ty (xs : (string * tspec) list) : (string * tspec) list =
  List.fold_left
    (fun (acc : (string * tspec) list) (((k : string), (s : tspec)) : string * tspec) ->
      if List.mem_assoc k acc then acc else acc @ [ (k, s) ])
    [] xs

let dedup_fn (xs : (string * fspec) list) : (string * fspec) list =
  List.fold_left
    (fun (acc : (string * fspec) list) (((k : string), (s : fspec)) : string * fspec) ->
      if List.mem_assoc k acc then acc else acc @ [ (k, s) ])
    [] xs

(** One round of the fixpoint of SD-D4.  An apply of [k] arguments on a
    closure of arity [m] leaves [k - m] arguments for another apply when
    [m] is the smaller one, and builds a partial application of arity
    [m - k] when [k] is. *)
let step_once (a : int list) (k : int list) : int list * int list =
  ( dedup_int
      (a
      @ List.concat_map
          (fun (m : int) ->
            List.filter_map
              (fun (kk : int) -> if m > kk then Some (m - kk) else None)
              k)
          a),
    dedup_int
      (k
      @ List.concat_map
          (fun (kk : int) ->
            List.filter_map
              (fun (m : int) -> if kk > m && m > 0 then Some (kk - m) else None)
              a)
          k) )

let rec close_arities (a : int list) (k : int list) (fuel : int) : int list * int list =
  if fuel <= 0 then (a, k)
  else
    let a2, k2 = step_once a k in
    if
      Int.equal (List.length a2) (List.length a)
      && Int.equal (List.length k2) (List.length k)
    then (a, k)
    else close_arities a2 k2 (fuel - 1)

let helper_keys (a : int list) (k : int list) : keys =
  merge_all
    (List.map
       (fun (kk : int) ->
         merge
           (ty_key (apply_ty_key kk) (TSApply kk))
           (fn_key_of (apply_fkey kk) (FSApply kk)))
       k
    @ List.map (fun (m : int) -> ty_key (fn_key m) (TSFn m)) a
    @ List.concat_map
        (fun (m : int) ->
          List.filter_map
            (fun (kk : int) ->
              if m > kk then
                Some
                  (merge_all
                     [
                       ty_key (pap_key m kk) (TSPap kk);
                       fn_key_of (papw_fkey m kk) (FSPapw (m, kk));
                       ty_key (fn_key (m - kk)) (TSFn (m - kk));
                     ])
              else None)
            k)
        a)

(* ---------- the order of the sections ---------- *)

(** A composite type may name only an earlier one, so the ranks put the
    closure first, then the generic function types, then the struct tids
    by nesting depth, then the shapes built here. *)
let trank (s : tspec) : int =
  match s with
  | TSLimbs -> -2
  | TSBigNat -> -1
  | TSRuntime (_ps, _r) -> 5
  | TSClos -> 0
  | TSFn _n -> 1
  | TSStruct _rs -> 2
  | TSLeg _rs -> 3
  | TSPap _k -> 4
  | TSSig (_ps, _r) -> 5
  | TSApply _k -> 6
  | TSEntry -> 7

let frank (s : fspec) : int =
  match s with
  | FSRuntime _n -> 4
  | FSProg _n -> 0
  | FSWrap (_n, _c) -> 1
  | FSApply _k -> 2
  | FSPapw (_m, _k) -> 3
  | FSEntry -> 4

let depth (s : string) : int =
  String.fold_left
    (fun (n : int) (c : char) -> if Char.equal c '<' then n + 1 else n)
    0 s

let order_types (xs : (string * tspec) list) : (string * tspec) list =
  List.stable_sort
    (fun (((ka : string), (sa : tspec)) : string * tspec)
         (((kb : string), (sb : tspec)) : string * tspec) ->
      Stdlib.compare (trank sa, depth ka) (trank sb, depth kb))
    xs

let order_funcs (xs : (string * fspec) list) : (string * fspec) list =
  List.stable_sort
    (fun (((_ka : string), (sa : fspec)) : string * fspec)
         (((_kb : string), (sb : fspec)) : string * fspec) ->
      Int.compare (frank sa) (frank sb))
    xs

(* ---------- the rec groups of D-M1-5 ---------- *)

let dedup_str (xs : string list) : string list =
  List.fold_left
    (fun (acc : string list) (x : string) -> if List.mem x acc then acc else acc @ [ x ])
    [] xs

(** Two families are mutual when a leg of one holds a value of the
    other, which is the edge the leg tid text carries (SJ-D24).  An edge
    to a tid that no family owns is not an edge, so an M0 sum inside a
    constructor never joins two families. *)
let mu_edges (p : prog) : (string * string) list =
  List.concat_map
    (fun (((f : string), (ls : leg list)) : string * leg list) ->
      List.concat_map
        (fun (l : leg) ->
          List.filter_map
            (fun (r : E.repr) ->
              match r with
              | E.RUnion (E.Tid g) ->
                  if List.mem_assoc g p.mus then Some (f, g) else None
              | E.RI31 | E.RStruct _ | E.RFunc _ | E.RThunk _ -> None)
            (leg_fields l))
        ls)
    p.mus

let rec closure (es : (string * string) list) (acc : string list) (fuel : int) :
    string list =
  if fuel <= 0 then acc
  else
    let nxt : string list =
      dedup_str
        (acc
        @ List.filter_map
            (fun (((a : string), (b : string)) : string * string) ->
              if List.mem a acc then Some b else None)
            es)
    in
    if Int.equal (List.length nxt) (List.length acc) then acc
    else closure es nxt (fuel - 1)

(** The families one family reaches through its leg tids, in one step or
    more. *)
let reach (es : (string * string) list) (f : string) : string list =
  closure es
    (List.filter_map
       (fun (((a : string), (b : string)) : string * string) ->
         if String.equal a f then Some b else None)
       es)
    64

(** A family is recursive when it reaches itself, and two families are
    mutual when each reaches the other.  That pair of readings is the
    strongly connected component of the reference edges, so a family
    that only holds a value of another family is not mutual with it. *)
let recursive (es : (string * string) list) (f : string) : bool =
  List.mem f (reach es f)

let mutual (es : (string * string) list) (f : string) (g : string) : bool =
  List.mem g (reach es f) && List.mem f (reach es g)

(** The mutual families of the program, one list per family group. *)
let components (es : (string * string) list) (fams : string list) : string list list =
  List.fold_left
    (fun (acc : string list list) (f : string) ->
      let hit, miss =
        List.partition
          (fun (c : string list) -> List.exists (fun (g : string) -> mutual es f g) c)
          acc
      in
      miss @ [ dedup_str (List.concat hit @ [ f ]) ])
    [] fams

(** The group name of every family whose legs share a rec group.  A
    family that does not reach itself is not recursive and keeps one
    composite one group, which is SD-D17 (D-M1-5). *)
let family_groups (es : (string * string) list) (fams : string list) :
    (string * string) list =
  List.concat_map
    (fun (c : string list) ->
      let name : string = "group:" ^ String.concat "," (List.sort String.compare c) in
      List.filter_map
        (fun (f : string) -> if recursive es f then Some (f, name) else None)
        c)
    (components es fams)

(** The group name of a composite type.  Every leg of every constructor
    of every member of one mutual family answers the one name, and every
    other composite type answers its own key (D-M1-5, SD-D17). *)
let group_of (fgs : (string * string) list) (key : string) : string =
  Option.fold ~none:key
    ~some:(fun (((_t : string), (f : string), (_k : int), (_rs : E.repr list)) :
                 string * string * int * E.repr list) ->
      Option.value ~default:key (List.assoc_opt f fgs))
    (parse_mu_leg key)

(** The ordered types cut into rec groups.  A group stands at its first
    member and holds its members in the order they already have, so the
    ordering work of the pass is kept and only the members of one mutual
    family move together. *)
let group_types (fgs : (string * string) list) (xs : (string * tspec) list) :
    (string * tspec) list list =
  List.map
    (fun (((_g : string), (ms : (string * tspec) list)) :
           string * (string * tspec) list) -> ms)
    (List.fold_left
       (fun (acc : (string * (string * tspec) list) list)
            (((k : string), (s : tspec)) : string * tspec) ->
         let g : string = group_of fgs k in
         if List.mem_assoc g acc then
           List.map
             (fun (((gg : string), (ms : (string * tspec) list)) :
                    string * (string * tspec) list) ->
               if String.equal gg g then (gg, ms @ [ (k, s) ]) else (gg, ms))
             acc
         else acc @ [ (g, [ (k, s) ]) ])
       [] xs)

let indices (xs : (string * 'a) list) : (string * int) list =
  List.mapi (fun (i : int) (((k : string), (_s : 'a)) : string * 'a) -> (k, i)) xs

(* ---------- the answer ---------- *)

type t = {
  prog : prog;
  types : (string * tspec) list;  (** the flat reading of [groups] *)
  groups : (string * tspec) list list;  (** one rec group per entry (D-M1-5) *)
  tmap : (string * int) list;
  funcs : (string * fspec) list;
  fmap : (string * int) list;
  arities : int list;  (** every closure arity the module builds *)
  calls : int list;  (** every apply the module needs *)
  declared : int list;  (** the functions the module declares *)
}

let arity_keys (tys : (string * tspec) list) : int list =
  dedup_int
    (List.filter_map
       (fun (((_k : string), (s : tspec)) : string * tspec) ->
         match s with
         | TSFn n -> Some n
         | TSLimbs | TSBigNat | TSRuntime _ | TSClos | TSStruct _ | TSLeg _
         | TSPap _ | TSSig _ | TSApply _ | TSEntry ->
             None)
       tys)

let call_keys (tys : (string * tspec) list) : int list =
  dedup_int
    (List.filter_map
       (fun (((_k : string), (s : tspec)) : string * tspec) ->
         match s with
         | TSApply n -> Some n
         | TSLimbs | TSBigNat | TSRuntime _ | TSClos | TSFn _ | TSStruct _
         | TSLeg _ | TSPap _ | TSSig _ | TSEntry -> None)
       tys)

let build (rows : (string * Kanon_kernel.Erase.entry) list) : (t, Err.t) result =
  let p : prog = program_table rows in
  let* ks = seq (List.map (walk_fun p) p.funs) in
  let base : keys =
    merge (merge_all ks)
      (merge (ty_key entry_ty_key TSEntry) (fn_key_of entry_fkey FSEntry))
  in
  let tys0 : (string * tspec) list = dedup_ty base.tys in
  let fns0 : (string * fspec) list = dedup_fn base.fns in
  let a, k = close_arities (arity_keys tys0) (call_keys tys0) 64 in
  let extra : keys = helper_keys a k in
  let ordered : (string * tspec) list = order_types (dedup_ty (tys0 @ extra.tys)) in
  let edges : (string * string) list = mu_edges p in
  let groups : (string * tspec) list list =
    group_types (family_groups edges (List.map fst p.mus)) ordered
  in
  let types : (string * tspec) list = List.concat groups in
  let funcs : (string * fspec) list = order_funcs (dedup_fn (fns0 @ extra.fns)) in
  let fmap : (string * int) list = indices funcs in
  Ok
    {
      prog = p;
      types;
      groups;
      tmap = indices types;
      funcs;
      fmap;
      arities = a;
      calls = k;
      declared =
        List.filter_map
          (fun (((key : string), (s : fspec)) : string * fspec) ->
            match s with
            | FSWrap (_n, _c) -> List.assoc_opt key fmap
            | FSPapw (_m, _kk) -> List.assoc_opt key fmap
            | FSRuntime _ | FSProg _ | FSApply _ | FSEntry -> None)
          funcs;
    }

let type_index (l : t) (key : string) : (int, Err.t) result =
  List.assoc_opt key l.tmap
  |> Option.fold
       ~none:(Error (Err.Unbound ("no type index for " ^ key)))
       ~some:(fun (i : int) -> Ok i)

let func_index (l : t) (key : string) : (int, Err.t) result =
  List.assoc_opt key l.fmap
  |> Option.fold
       ~none:(Error (Err.Unbound ("no function index for " ^ key)))
       ~some:(fun (i : int) -> Ok i)

(** The value type of a repr.  A function value is a closure struct and a
    sum value is an eq reference, so only a pair, a tuple and a tagged
    integer name a type index (SD-D6). *)
let valtype_of (l : t) (r : E.repr) : (G.valtype, Err.t) result =
  match r with
  | E.RI31 -> Ok (G.Ref G.HI31)
  | E.RUnion _t -> Ok (G.Ref G.HEq)
  | E.RStruct (E.Tid t) -> Result.map (fun (i : int) -> G.Ref (G.HType i)) (type_index l t)
  | E.RFunc _t -> Result.map (fun (i : int) -> G.Ref (G.HType i)) (type_index l clos_key)
  | E.RThunk _t -> Error (Err.Not_yet "RThunk arrives at M2")

let eqs (n : int) : G.valtype list = List.init n (fun (_i : int) -> G.Ref G.HEq)

let runtime_valtype (l : t) (s : string) : (G.valtype, Err.t) result =
  match () with
  | () when String.equal s "i" -> Ok G.I32
  | () when String.equal s "n" -> Ok (G.Ref G.HEq)
  | () when String.equal s "a" -> Result.map (fun (i : int) -> G.Ref (G.HType i)) (type_index l limb_key)
  | () -> Error (Err.Mismatch ("unknown natural runtime value type: " ^ s))

(** Aggregate storage is uniform across type instantiations.  A pair of
    any values and a pair of naturals have identical final struct types,
    so an erased type argument cannot change their layout.  Reads cast
    each field to its checked repr; function signatures stay typed. *)
let comptype_of (l : t) (((_key : string), (s : tspec)) : string * tspec) :
    (G.comptype, Err.t) result =
  match s with
  | TSLimbs -> Ok (G.CArray G.I32)
  | TSBigNat ->
      let* ai = type_index l limb_key in
      Ok (G.CStruct [ G.I32; G.Ref (G.HType ai) ])
  | TSRuntime (ps, r) ->
      let* vs = seq (List.map (runtime_valtype l) ps) in
      let* v = runtime_valtype l r in
      Ok (G.CFunc (vs, [ v ]))
  | TSClos -> Ok (G.CStruct [ G.I32; G.Ref G.HFunc; G.Ref G.HEq ])
  | TSFn n -> Ok (G.CFunc (eqs (n + 1), [ G.Ref G.HEq ]))
  | TSStruct rs -> Ok (G.CStruct (eqs (List.length rs)))
  | TSLeg rs -> Ok (G.CStruct (G.Ref G.HI31 :: eqs (List.length rs)))
  | TSPap k -> Ok (G.CStruct (eqs (k + 1)))
  | TSSig (ps, r) ->
      let* vs = seq (List.map (valtype_of l) ps) in
      let* v = valtype_of l r in
      Ok (G.CFunc (vs, [ v ]))
  | TSApply k -> Ok (G.CFunc (eqs (k + 1), [ G.Ref G.HEq ]))
  | TSEntry -> Ok (G.CFunc ([], [ G.I32 ]))

(** The composite types of the module, one list per rec group.  The
    index of a type is its position in the concatenation, which is the
    order [l.types] already holds (D-M1-5, A8). *)
let comptype_groups (l : t) : (G.comptype list list, Err.t) result =
  seq (List.map (fun (g : (string * tspec) list) -> seq (List.map (comptype_of l) g)) l.groups)
