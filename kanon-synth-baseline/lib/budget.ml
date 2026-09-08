(* carried from tot 8cf0b8b lib/budget.ml, delta: this header line only *)
(** M5 Stage C (verdict item 2, pin 8): the check budget, as the kernel
    sees it.

    The kernel never asks what time it is.  It asks ONE question, "is
    my budget spent?", and the DRIVER supplies the function that
    answers it.  That split is the whole design:

    - `lib/` keeps its rule that it uses neither `Unix` nor `Sys`
      (`lib/dune` depends on `str` alone, and `lib/interp.ml`'s regex
      comment states the rule).  A clock in the kernel would break it.
    - The poll may be as cheap or as accurate as the installation
      wants.  `bin/tot.ml` throttles its own clock reads behind a
      counter, which is legal in the driver and would not be legal
      here.
    - A test can drive the kernel with a deterministic poll, with no
      clock and no sleep.  `test/main.ml`'s C1 case does exactly that.

    [poll ()] returns [true] when the budget IS spent.  [unlimited]
    answers [false] forever and allocates nothing per call, so the
    default configuration pays one closure call per kernel node and no
    clock read at all. *)
type t = { poll : unit -> bool }

let unlimited : t = { poll = (fun () -> false) }
let of_poll (poll : unit -> bool) : t = { poll }
let exhausted (b : t) : bool = b.poll ()
