(** The shape sum.  Plan section 4 declares it whole at Stage A and the
    later arms are refused by their milestone name (D-M0-2), so the closed
    grammar is visible in SPEC.md from the first commit.

    SA-D5: the type is polymorphic in the kernel term, so term.ml carries
    no shape name and the R0-AUDIT gate leg runs from Stage A.  This
    module and pp.ml are the only two files in lib/ that spell a shape
    name;  rules.ml joins them at Stage B. *)

type 'a t =
  | SPi of Quantity.t * string * 'a
  | SColl of int
  | SPar of 'a * 'a
  | SMu of string * 'a list
  | SNu of string * 'a list

(** The five declared shapes, in the order of the sum above.  spec_count.ml
    prints the length of this list, so a sixth shape moves the R0 count. *)
let declared : string list = [ "SPi"; "SColl"; "SPar"; "SMu"; "SNu" ]

(** M1 Stage G, brief 3.2:  the payload a shape carries, so positivity.ml
    walks a former and spells no shape name (dev/r0-audit.sh:6-11). *)
let payload (s : 'a t) : 'a list =
  match s with
  | SPi (_, _, dom) -> [ dom ]
  | SColl _ -> []
  | SPar (a, b) -> [ a; b ]
  | SMu (_, ix) -> ix
  | SNu (_, ix) -> ix

(** The domain of the point shape, the left of an arrow (rules.ml:220).
    [None] at every other shape, so a reader that must tell the arrow
    from any other former asks here and names no shape. *)
let point_dom (s : 'a t) : 'a option =
  match s with
  | SPi (_, _, dom) -> Some dom
  | SColl _ -> None
  | SPar (_, _) -> None
  | SMu (_, _) -> None
  | SNu (_, _) -> None

(** M1 Stage G:  the family name a recursive shape carries.  A type at a
    family is a left former at that shape and never a global name, so
    positivity.ml asks here whether a former stands at one of a group of
    families. *)
let family (s : 'a t) : string option =
  match s with
  | SMu (n, _) -> Some n
  | SNu (n, _) -> Some n
  | SPi (_, _, _) -> None
  | SColl _ -> None
  | SPar (_, _) -> None

let name (s : 'a t) : string =
  match s with
  | SPi (_, _, _) -> "SPi"
  | SColl _ -> "SColl"
  | SPar (_, _) -> "SPar"
  | SMu (_, _) -> "SMu"
  | SNu (_, _) -> "SNu"
