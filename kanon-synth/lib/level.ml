(* carried from tot 8cf0b8b lib/level.ml, delta: this header line only *)
type t = int

let zero : t = 0
let one : t = 1
let succ (l : t) : t = l + 1
let max (a : t) (b : t) : t = Int.max a b
let equal (a : t) (b : t) : bool = Int.equal a b
let le (a : t) (b : t) : bool = a <= b
let of_int (n : int) : t option = if n >= 0 then Some n else None
let to_string (l : t) : string = string_of_int l
