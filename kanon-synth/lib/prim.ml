(** The native primitive catalog at M0, plan section 6 and SB-D8.  Five
    primitives on the natural numbers, mirroring the closed enum of
    kan-lang-tot-pin/lib/prim.ml:20 with a much smaller row.

    [Nat] itself is a postulated constant of [Global.initial], so a
    primitive type is opaque to conversion and no rule steps into it.  The
    unary recursive presentation of [Nat] arrives at M1 with the recursive
    shape, and SPEC.md section 10 keeps the agreement lemma of the literal
    fast path against it as an obligation.

    [reduce] answers the fast path of SB-D4.  It returns [None] for a
    primitive that has no literal answer, so the caller leaves the
    application stuck instead of guessing.  [natEq] and [natLt] answer with
    a collection value rather than a literal (SB-D22), so [apply] builds
    that answer beside [reduce] and every caller reads [apply]. *)

type t =
  | Nat_add
  | Nat_sub
  | Nat_mul
  | Nat_eq
  | Nat_lt

let name (p : t) : string =
  match p with
  | Nat_add -> "natAdd"
  | Nat_sub -> "natSub"
  | Nat_mul -> "natMul"
  | Nat_eq -> "natEq"
  | Nat_lt -> "natLt"

(** Every M0 primitive takes two naturals. *)
let arity (p : t) : int =
  match p with
  | Nat_add -> 2
  | Nat_sub -> 2
  | Nat_mul -> 2
  | Nat_eq -> 2
  | Nat_lt -> 2

(** Declaration order.  [Global.initial] and the SPEC table read this
    list, so the catalog is written once. *)
let catalog : t list = [ Nat_add; Nat_sub; Nat_mul; Nat_eq; Nat_lt ]

let of_name (s : string) : t option =
  List.find_opt (fun (p : t) -> String.equal (name p) s) catalog

(** The name of the primitive type constant.  [Global.initial] postulates
    it at [Univ one], that is at [Type 0]. *)
let nat_name : string = "Nat"

let nat_ty : Term.t = Term.Global nat_name

(** The closed type of each primitive (SB-D8).  Both binders are at
    [Many], so a primitive is runtime data and an erased argument cannot
    reach one.  The codomain of [natEq] and [natLt] is the two leg sum of
    the unit type, which is what a boolean is at M0:  no primitive boolean
    type exists. *)
let ty (p : t) : Term.t =
  let binary (result : Term.t) : Term.t =
    Rules.arrow Quantity.Many "a" nat_ty (Rules.arrow Quantity.Many "b" nat_ty result)
  in
  match p with
  | Nat_add -> binary nat_ty
  | Nat_sub -> binary nat_ty
  | Nat_mul -> binary nat_ty
  | Nat_eq -> binary Rules.bool_ty
  | Nat_lt -> binary Rules.bool_ty

(** A literal is a natural only when it is an integer and not negative.
    The surface has no negative integer token, so a negative literal can
    reach here only from a hand built term, and the answer is a stuck
    application, not a wrong number. *)
let as_nat (l : Literal.t) : Bignum.t option =
  match l with
  | Literal.LInt n -> if Bignum.sign n < 0 then None else Some n
  | Literal.LString _ -> None

let add (a : Bignum.t) (b : Bignum.t) : (Bignum.t, Error.t) result =
  Ok (Bignum.add a b)

(** Truncated subtraction (SB-D4):  the naturals have no negative, so a
    larger subtrahend gives zero. *)
let sub (a : Bignum.t) (b : Bignum.t) : (Bignum.t, Error.t) result =
  Ok (Bignum.sub a b)

(** SK-D3: Zarith promotes the result before any machine integer wrap. *)
let mul (a : Bignum.t) (b : Bignum.t) : (Bignum.t, Error.t) result =
  Ok (Bignum.mul a b)

(** The arithmetic row.  [None] marks a primitive whose answer is not a
    literal. *)
let arith (p : t) : (Bignum.t -> Bignum.t -> (Bignum.t, Error.t) result) option =
  match p with
  | Nat_add -> Some add
  | Nat_sub -> Some sub
  | Nat_mul -> Some mul
  | Nat_eq -> None
  | Nat_lt -> None

(** The comparison row, the other half of the same split. *)
let compare_op (p : t) : (Bignum.t -> Bignum.t -> bool) option =
  match p with
  | Nat_eq -> Some Bignum.equal
  | Nat_lt -> Some (fun (a : Bignum.t) (b : Bignum.t) -> Bignum.compare a b < 0)
  | Nat_add -> None
  | Nat_sub -> None
  | Nat_mul -> None

(** The two arguments as naturals, when the application is saturated with
    two natural literals. *)
let two_nats (args : Literal.t list) : (Bignum.t * Bignum.t) option =
  Rules.two_of args
  |> Fun.flip Option.bind (fun ((x : Literal.t), (y : Literal.t)) ->
         Option.bind (as_nat x) (fun (a : Bignum.t) ->
             Option.map (fun (b : Bignum.t) -> (a, b)) (as_nat y)))

let reduce (p : t) (args : Literal.t list) : (Literal.t option, Error.t) result =
  two_nats args
  |> Option.fold ~none:None ~some:(fun ((a : Bignum.t), (b : Bignum.t)) ->
         Option.map
           (fun (f : Bignum.t -> Bignum.t -> (Bignum.t, Error.t) result) -> f a b)
           (arith p))
  |> Option.fold ~none:(Ok None) ~some:(fun (r : (Bignum.t, Error.t) result) ->
         Result.map (fun (n : Bignum.t) -> Some (Literal.LInt n)) r)

(** The whole fast path, literal answers and collection answers together.
    [None] leaves the application stuck. *)
let apply (p : t) (args : Literal.t list) : (Value.t option, Error.t) result =
  let comparison : Value.t option =
    two_nats args
    |> Fun.flip Option.bind (fun ((a : Bignum.t), (b : Bignum.t)) ->
           Option.map
             (fun (f : Bignum.t -> Bignum.t -> bool) -> Rules.bool_value (f a b))
             (compare_op p))
  in
  reduce p args
  |> Result.map (fun (l : Literal.t option) ->
         Option.fold ~none:comparison ~some:(fun (x : Literal.t) -> Some (Value.VLit x)) l)
