(* carried from tot 8cf0b8b lib/budget.mli, delta: this header line only *)
(** M5 Stage C: see budget.ml.  The type is ABSTRACT here, so no module
    outside this one can read the poll, replace it, or compare two
    budgets. *)
type t

val unlimited : t
val of_poll : (unit -> bool) -> t
val exhausted : t -> bool
