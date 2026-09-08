(* carried from tot 8cf0b8b lib/level.mli, delta: this header line only *)
(** Universe levels. Abstract so a negative level cannot be built. *)

type t

val zero : t
val one : t
val succ : t -> t
val max : t -> t -> t
val equal : t -> t -> bool
val le : t -> t -> bool
val of_int : int -> t option
val to_string : t -> string
