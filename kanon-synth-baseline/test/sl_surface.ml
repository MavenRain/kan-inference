(** Stage L parser boundaries and sugar equivalence.  Parser refusals
    live here because the kernel suite round-trips every negative fixture. *)
open Kanon_kernel
open Kanon_surface

let ( let* ) = Result.bind

let parse (source : string) : (Syntax.decl list, string) result =
  Parser.parse source |> Result.map_error Error.to_string

let round_trip (source : string) : (unit, string) result =
  let* first = parse source in
  let* second = parse (Syntax.print first) in
  if first = second then Ok () else Error "printed tree changed"

let parse_refusal (source : string) (message : string) : (unit, string) result =
  Parser.parse source
  |> Result.fold
       ~ok:(fun (_tree : Syntax.decl list) -> Error "invalid source parsed")
       ~error:(fun (e : Error.t) ->
         if String.equal (Error.message e) message then Ok ()
         else Error (Error.to_string e))

let same_tree (first : string) (second : string) : (unit, string) result =
  let* a = parse first in
  let* b = parse second in
  if a = b then Ok () else Error "sugar changed the family tree"

let checked (source : string) : (string, string) result =
  Elab.check_text Global.initial source
  |> Result.map Elab.checked_form |> Result.map_error Error.to_string

let same_checked (first : string) (second : string) : (unit, string) result =
  let* a = checked first in
  let* b = checked second in
  if String.equal a b then Ok () else Error "match changed checked elimination"

let family = "mu N : Type 0 := | zero : N | succ (n : N) : N\n"

let legacy_family = "mu N : Type 0 with | zero : N | succ : (n : N) -> N\n"

let matched = family ^
  "def pred : N -> N := fun (n : N) => match n as x in N return N with | zero => zero | succ (p : N) => p"

let cased = legacy_family ^
  "def pred : N -> N := fun (n : N) => case n as x in N return N with | zero => zero | succ p => p"

let mutual = "mutual mu A : Type 0 := | a (b : B) : A mu B : Type 0 := | b : B end"

let legacy_mutual = "mu A : Type 0 with | a : (b : B) -> A and B : Type 0 with | b : B"

let cases : (string * (unit -> (unit, string) result)) list =
  [ "constructor-sugar", (fun () -> same_tree family legacy_family);
    "mutual-sugar", (fun () -> same_tree mutual legacy_mutual);
    "match-elaboration", (fun () -> same_checked matched cased);
    "mu-roundtrip", (fun () -> round_trip family);
    "legacy-mu-roundtrip", (fun () -> round_trip legacy_family);
    "mutual-roundtrip", (fun () -> round_trip mutual);
    "legacy-mutual-roundtrip", (fun () -> round_trip legacy_mutual);
    "match-roundtrip", (fun () -> round_trip matched);
    "case-roundtrip", (fun () -> round_trip cased);
    "mixed-fields-roundtrip", (fun () -> round_trip
      "def f : Nat := match n as x in N return Nat with | c (0 i : N) x (1 y : Nat) => y");
    "nested-match-roundtrip", (fun () -> round_trip
      "def f : Nat := match n as x in N return Nat with | z => 0 | s p => (match p as y in N return Nat with | z => 1 | s q => 2)");
    "empty-match-roundtrip", (fun () -> round_trip
      "mu Void : Prop := def exFalso : Void -> Type 0 := fun (v : Void) => match v as x in Void return Type 0 with");
    "case-numeric-roundtrip", (fun () -> round_trip
      "def f : Nat := case b with | 0 (x : Nat) => x | 1 (x : Nat) => x");
    "match-numeric-refusal", (fun () -> parse_refusal
      "def f : Nat := match n with | 0 (x : Nat) => x"
      "a match branch keys a constructor, not a leg number");
    "mutual-empty-refusal", (fun () -> parse_refusal "mutual end"
      "a mutual group needs at least two mu declarations");
    "mutual-singleton-refusal", (fun () -> parse_refusal "mutual mu N : Type 0 := end"
      "a mutual group needs at least two mu declarations");
    "mutual-unclosed-refusal", (fun () -> parse_refusal
      "mutual mu A : Type 0 := mu B : Type 0 :="
      "expected 'mu' or 'end' in a mutual group, found end of input");
    "mutual-and-refusal", (fun () -> parse_refusal
      "mutual mu A : Type 0 := and B : Type 0 := end"
      "expected 'mu' or 'end' in a mutual group, found 'and'");
    "nu-term-refusal", (fun () -> parse_refusal "def f : Type 0 := nu" "nu arrives at M2");
    "nu-declaration-refusal", (fun () -> parse_refusal "nu N : Type 0 :=" "nu arrives at M2") ]

let () =
  let passed = List.fold_left
      (fun (count : int) ((name : string), (run : unit -> (unit, string) result)) ->
        run () |> Result.fold
          ~ok:(fun () -> Printf.printf "SL-SURFACE %s OK\n" name; count + 1)
          ~error:(fun (message : string) ->
            Printf.printf "SL-SURFACE %s FAIL: %s\n" name message; count))
      0 cases in
  Printf.printf "SL-SURFACE-OK %d/%d\n" passed (List.length cases);
  if Int.equal passed (List.length cases) then print_endline "SL-SURFACE OK"
  else (print_endline "SL-SURFACE FAIL"; exit 1)
