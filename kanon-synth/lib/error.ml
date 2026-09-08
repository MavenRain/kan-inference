(** Kernel and surface errors.  Stage B extends this sum with the check
    errors;  every consumer matches it exhaustively, so a new arm is a
    compile error at every reader before it is a silent fallthrough.

    [Not_yet] carries a milestone name, plan section 5:  rules.ml returns
    it for a shape that M0 does not admit, and the parser returns it
    through [Parse] for a surface word that M0 reserves.

    [message] returns the bare text and [to_string] adds the position, so
    a test can compare the text a producer chose without also fixing the
    position format.

    Stage B adds the check arms.  Each one carries its own text, so
    [message] stays the bare producer text that a negative fixture
    compares against (SB-D10) and [to_string] adds the decoration. *)

type t =
  | Not_yet of string
  | Parse of string * int * int
  | Carry of string
  | Unbound of string  (** a name with no binder and no declaration *)
  | Mismatch of string  (** the inferred type and the expected type differ *)
  | Universe of string  (** a term used as a type is not a universe *)
  | Quantity of string  (** an erased binder is read in a runtime position *)
  | Wrong_leg of string  (** a leg address is outside the collection *)
  | Missing_branch of string  (** an elimination does not cover every address *)
  | Overflow of string  (** a check-time literal leaves the host int range *)
  | Cannot_infer of string  (** the term has no type without an expectation *)
  | Budget_exhausted of string  (** the driver's cutoff fired (SB-D19) *)
  | Index_not_zero of string
      (** M1 Stage G:  an index binder of a family is not at quantity
          [Zero] (A2, kan-lang-tot-pin/lib/check.ml:1819) *)
  | Index_above_universe of string
      (** M1 Stage G:  an index type is above the declared level (A5,
          kan-lang-tot-pin/lib/check.ml:1820-1823) *)
  | Termination of string
      (** M1 Stage I, SI-D6:  the definition named here failed the
          structural termination guard of lib/order.ml.  The arm is
          mirrored from kan-lang-tot-pin/lib/error.ml:25 and it carries
          the name, so the one message below is written once *)

(** The text of the termination arm, kan-lang-tot-pin/lib/error.ml:185
    word for word.  Every negative fixture of M1 Stage I pins this line
    (SI-D6), so it is written here and nowhere else. *)
let termination_msg (n : string) : string =
  Printf.sprintf "recursive definition %s failed the structural termination guard" n

let message (e : t) : string =
  match e with
  | Not_yet m -> m
  | Parse (m, _, _) -> m
  | Carry m -> m
  | Unbound m -> m
  | Mismatch m -> m
  | Universe m -> m
  | Quantity m -> m
  | Wrong_leg m -> m
  | Missing_branch m -> m
  | Overflow m -> m
  | Cannot_infer m -> m
  | Budget_exhausted m -> m
  | Index_not_zero m -> m
  | Index_above_universe m -> m
  | Termination n -> termination_msg n

let to_string (e : t) : string =
  match e with
  | Not_yet m -> "not yet: " ^ m
  | Parse (m, line, column) -> Printf.sprintf "line %d, column %d: %s" line column m
  | Carry m -> "carry: " ^ m
  | Unbound m -> "unbound: " ^ m
  | Mismatch m -> "mismatch: " ^ m
  | Universe m -> "universe: " ^ m
  | Quantity m -> "quantity: " ^ m
  | Wrong_leg m -> "wrong leg: " ^ m
  | Missing_branch m -> "missing branch: " ^ m
  | Overflow m -> "overflow: " ^ m
  | Cannot_infer m -> "cannot infer: " ^ m
  | Budget_exhausted m -> "budget: " ^ m
  | Index_not_zero m -> "index not zero: " ^ m
  | Index_above_universe m -> "index above universe: " ^ m
  | Termination n -> "termination: " ^ termination_msg n
