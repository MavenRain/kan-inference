(* Stage K SK-D1: Zarith 1.14 boundary, a new algorithm rather than a pin port.
   Signed payloads preserve malformed kernel inputs for Nat validation. *)
type t = Z.t

let of_int (value : int) : t = Z.of_int value
let zero : t = Z.zero
let one : t = Z.one
let equal (left : t) (right : t) : bool = Z.equal left right
let compare (left : t) (right : t) : int = Z.compare left right
let sign (value : t) : int = Z.sign value
let add (left : t) (right : t) : t = Z.add left right
let mul (left : t) (right : t) : t = Z.mul left right

(* Nat callers validate nonnegative operands; subtraction truncates at zero. *)
let sub (left : t) (right : t) : t =
  if compare left right <= 0 then zero else Z.sub left right

let of_decimal (source : string) : t option =
  let digit (state : t option) (character : char) : t option =
    Option.bind state (fun value ->
      if character >= '0' && character <= '9' then
        Some (add (mul value (of_int 10))
                (of_int (Char.code character - Char.code '0')))
      else None)
  in
  if String.length source = 0 then None
  else String.fold_left digit (Some zero) source

let to_string (value : t) : string = Z.to_string value

(* Zarith's narrowing requires a representable signed OCaml int. *)
let to_int (value : t) : int option =
  if Z.fits_int value then Some (Z.to_int value) else None

(* SK-D4: the one bound of the small arm.  wasm/emit.ml reads it too. *)
let nat_max : int = 1073741823
let to_i31 (value : t) : int option =
  if sign value >= 0 && compare value (of_int nat_max) <= 0 then to_int value else None

(* SK-D4: radix 32768, least significant limb first; zero has no limbs. *)
let limbs15 (value : t) : int list option =
  let mask : t = of_int 32767 in
  let rec collect (remaining : t) (reversed : int list) : int list option =
    if equal remaining zero then Some (List.rev reversed)
    else
      (* The mask bounds each limb, and to_int independently checks narrowing.
         shift_right requires a nonnegative count, supplied literally here. *)
      Option.bind (to_int (Z.logand remaining mask)) (fun limb ->
        collect (Z.shift_right remaining 15) (limb :: reversed))
  in
  if sign value < 0 then None else collect value []
