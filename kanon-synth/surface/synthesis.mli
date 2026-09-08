(** Pure checked synthesis for explicitly typed, nonrecursive definition
    bodies. Models receive only ordinary source preceding the first hole.

    The initial policy refuses every source axiom, including unused axioms,
    and every axiom in the checked prefix except the unchanged built-in Nat
    postulate. This is deliberately stronger than checking just the chosen
    term's dependency closure. No custom environment can enter this API.

    The policy also refuses every declaration that redefines a name already
    bound in the checked prefix or in the initial environment. The
    environment installs by overwrite, so a repeated name would be checked
    against the old entry and then replace it. This rule covers the hole
    itself, every other declaration, and every name a family or recursive
    group binds. *)

type request = {
  declaration : string;
  hint : string;
  expected_type : string;
  context : string;
}

val next : string -> (request option, Kanon_kernel.Error.t) result
(** Check the prefix and goal of the first eligible hole. [Ok None] means
    the entire source checked successfully and has no synthesis holes. *)

val apply : string -> string -> (string, Kanon_kernel.Error.t) result
(** Parse exactly one candidate expression, independently kernel-check its
    complete definition in the fixed prefix, and print the replaced source.
    Later holes remain in the result. Call [next] until it returns [None],
    then check the complete materialized source again before publication.
    The process caller must enforce byte and wall-time limits. *)
