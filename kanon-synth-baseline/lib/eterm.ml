(** The erased intermediate form, plan section 7, declared whole at Stage A
    (D-M0-2).  Types only at Stage A;  erase.ml fills it at Stage C and
    emit.ml refuses the arms past M0 with their milestone name at Stage D.

    Repair one of the verdict: [tid] and [fid] are symbolic names and never
    integers, and link.ml resolves them to type and function indices in one
    pass, so the emitter never computes an index.

    Repair three: [KClos] carries its arity, so partial application and
    over-application never touch the closure body.

    [KDelay], [KForce] and [RThunk] are M2 and are refused by emit at M0. *)

type tid = Tid of string
type fid = Fid of string

type repr =
  | RI31
  | RStruct of tid
  | RUnion of tid
  | RFunc of tid
  | RThunk of tid

type ktm =
  | KVar of int
  | KLit of Literal.t
  | KGlobal of string
  | KErased
  | KLet of string * ktm * ktm
  | KClos of fid * int * ktm list
  | KApp of ktm * ktm list
  | KTail of ktm * ktm list
  | KStruct of tid * ktm list
  | KProj of tid * int * ktm
  | KTag of tid * int * ktm list
  | KCase of tid * ktm * kbranch list
  | KDelay of fid * ktm list
  | KForce of ktm

and kbranch = {
  tag : int;
  arity : int;
  body : ktm;
}

(** Repair two: [KRec] is one rec group per definition group.  At M0 every
    declaration owns its group;  M1's mutual recursive shape shares one. *)
type kdecl =
  | KFun of fid * repr list * repr * ktm
  | KRec of tid list

(** The printed form (SC-D2).  The printer is exhaustive over every
    constructor, including the two M2 arms, so a [KDelay] or a [KForce]
    prints here and is refused by emit at Stage D, not by this file.
    Names print bare, without quotes, and a list prints in square
    brackets with a semicolon between its members.

    No shape name appears in this file (SA-D5, gate leg R0-AUDIT).  The
    constructor set stays fixed.  A case retains the checked scrutinee
    tid so generic calls do not erase its branch payload types. *)

let tid_text (t : tid) : string =
  match t with
  | Tid s -> s

let fid_text (f : fid) : string =
  match f with
  | Fid s -> s

(** The literal text of the erased form.  It is written here and not
    read from pp.ml, so the erased printer holds no display convention
    of the kernel printer. *)
let literal_text (l : Literal.t) : string =
  match l with
  | Literal.LString s -> "\"" ^ String.escaped s ^ "\""
  | Literal.LInt n -> Bignum.to_string n

let print_repr (r : repr) : string =
  match r with
  | RI31 -> "i31"
  | RStruct t -> "struct " ^ tid_text t
  | RUnion t -> "union " ^ tid_text t
  | RFunc t -> "func " ^ tid_text t
  | RThunk t -> "thunk " ^ tid_text t

let rec print_ktm (t : ktm) : string =
  match t with
  | KVar i -> Printf.sprintf "KVar %d" i
  | KLit l -> "KLit " ^ literal_text l
  | KGlobal n -> "KGlobal " ^ n
  | KErased -> "KErased"
  | KLet (x, v, b) -> Printf.sprintf "KLet %s (%s) (%s)" x (print_ktm v) (print_ktm b)
  | KClos (f, n, cs) -> Printf.sprintf "KClos %s %d %s" (fid_text f) n (ktm_list cs)
  | KApp (h, args) -> Printf.sprintf "KApp (%s) %s" (print_ktm h) (ktm_list args)
  | KTail (h, args) -> Printf.sprintf "KTail (%s) %s" (print_ktm h) (ktm_list args)
  | KStruct (t', fs) -> Printf.sprintf "KStruct %s %s" (tid_text t') (ktm_list fs)
  | KProj (t', k, x) -> Printf.sprintf "KProj %s %d (%s)" (tid_text t') k (print_ktm x)
  | KTag (t', k, ps) -> Printf.sprintf "KTag %s %d %s" (tid_text t') k (ktm_list ps)
  | KCase (t', s, bs) ->
      Printf.sprintf "KCase %s (%s) [%s]" (tid_text t') (print_ktm s)
        (String.concat "; " (List.map print_branch bs))
  | KDelay (f, cs) -> Printf.sprintf "KDelay %s %s" (fid_text f) (ktm_list cs)
  | KForce x -> Printf.sprintf "KForce (%s)" (print_ktm x)

and ktm_list (xs : ktm list) : string =
  "[" ^ String.concat "; " (List.map print_ktm xs) ^ "]"

and print_branch (b : kbranch) : string =
  Printf.sprintf "{%d %d (%s)}" b.tag b.arity (print_ktm b.body)

let print_decl (d : kdecl) : string =
  match d with
  | KFun (f, params, result, body) ->
      Printf.sprintf "fun %s (%s) : %s := %s" (fid_text f)
        (String.concat ", " (List.map print_repr params))
        (print_repr result) (print_ktm body)
  | KRec ts -> Printf.sprintf "rec [%s]" (String.concat "; " (List.map tid_text ts))
