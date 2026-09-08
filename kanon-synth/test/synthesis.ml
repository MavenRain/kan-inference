(** Adversarial tests for the boundary between proposed source and checked
    definitions. No fixture proposer or model result substitutes for checking. *)
open Kanon_kernel
open Kanon_surface

let ( let* ) = Result.bind

let explain (result : ('a, Error.t) result) : ('a, string) result =
  result |> Result.map_error Error.to_string

let require (condition : bool) (message : string) : (unit, string) result =
  if condition then Ok () else Error message

let rejected (result : ('a, Error.t) result) : (unit, string) result =
  result |> Result.fold ~ok:(fun _value -> Error "invalid input was accepted")
    ~error:(fun (_error : Error.t) -> Ok ())

let refusal (message : string) (result : ('a, Error.t) result) : (unit, string) result =
  result |> Result.fold ~ok:(fun _value -> Error "invalid input was accepted")
    ~error:(fun (error : Error.t) ->
      require (String.equal message (Error.message error)) (Error.to_string error))

let complete (source : string) : (unit, string) result =
  let* request = explain (Synthesis.next source) in
  let* () = require (Option.is_none request) "materialized source still has a hole" in
  let* _checked = explain (Elab.check_in Global.initial source) in
  Ok ()

let next_request (source : string) : (Synthesis.request, string) result =
  let* request = explain (Synthesis.next source) in
  request |> Option.to_result ~none:"no request returned"

let same_tree (first : string) (second : string) : (unit, string) result =
  let* a = explain (Parser.parse first) in
  let* b = explain (Parser.parse second) in
  require (a = b) "materialization changed a declaration besides its selected body"

let success (source : string) (candidate : string) (expected : string) :
    (unit, string) result =
  let* expanded = explain (Synthesis.apply source candidate) in
  let* () = same_tree expanded expected in
  complete expanded

let invalid_candidate (source : string) (candidate : string) : (unit, string) result =
  let* _parsed = explain (Parser.expression candidate) in
  rejected (Synthesis.apply source candidate)

let round_trip_hint (hint : string) : (unit, string) result =
  let source = "def result : Nat := " ^ Syntax.at 0 (Syntax.SSynth hint) in
  let* parsed = explain (Parser.parse source) in
  let* printed = explain (Parser.parse (Syntax.print parsed)) in
  let* () = require (parsed = printed) "hint changed during print/parse roundtrip" in
  let* request = next_request source in
  require (String.equal request.Synthesis.hint hint) "request hint differs from its literal"

let unsupported =
  "synth is supported only as the entire body of an explicitly typed nonrecursive def"

let auto_refusal = "unresolved auto is not allowed in synthesis sources or candidates"
let hole = "def result : Nat := synth \"return seven\"\n"
let family = "mu N : Type 0 := | zero : N | succ (n : N) : N\n"

let boundary_cases : (string * (unit -> (unit, string) result)) list =
  [ "literal", (fun () -> success hole "7" "def result : Nat := 7");
    "whole-lambda", (fun () -> success
      "def id : Nat -> Nat := synth \"identity\""
      "fun (x : Nat) => x" "def id : Nat -> Nat := fun (x : Nat) => x");
    "linear-lambda", (fun () -> success
      "def id : (1 x : Nat) -> Nat := synth \"identity\""
      "fun (1 x : Nat) => x" "def id : (1 x : Nat) -> Nat := fun (1 x : Nat) => x");
    "dependent-lambda", (fun () -> success
      "def id : (0 A : Type 0) -> A -> A := synth \"identity\""
      "fun (0 A : Type 0) (x : A) => x"
      "def id : (0 A : Type 0) -> A -> A := fun (0 A : Type 0) (x : A) => x");
    "existing-prefix", (fun () -> success
      ("def base : Nat := 7\n" ^ hole) "base"
      "def base : Nat := 7\ndef result : Nat := base");
    "fixed-request", (fun () ->
      let prefix = "def base : Nat := 7\n" in
      let* request = next_request (prefix ^ hole ^ "def future : Nat := 8") in
      let* () = require (String.equal request.Synthesis.declaration "result") "wrong declaration" in
      let* () = require (String.equal request.Synthesis.expected_type "Nat") "wrong goal" in
      same_tree request.Synthesis.context prefix);
    "multiple-holes", (fun () ->
      let source = hole ^ "def second : Nat := synth \"reuse the first\"" in
      let* first = explain (Synthesis.apply source "7") in
      let* request = next_request first in
      let* () = require (String.equal request.Synthesis.declaration "second") "wrong next hole" in
      let* () = same_tree request.Synthesis.context "def result : Nat := 7" in
      success first "result" "def result : Nat := 7\ndef second : Nat := result");
    "family-prefix", (fun () -> success
      (family ^ "def result : N := synth \"zero\"") "zero"
      (family ^ "def result : N := zero"));
    "family-suffix", (fun () -> success
      (hole ^ family ^ "def final : N := zero") "7"
      ("def result : Nat := 7\n" ^ family ^ "def final : N := zero"));
    "mutual-families", (fun () ->
      let prefix = "mutual mu A : Type 0 := | a (b : B) : A mu B : Type 0 := | b : B end\n" in
      success (prefix ^ hole) "7" (prefix ^ "def result : Nat := 7"));
    "escaped-hint", (fun () -> round_trip_hint "quote \" slash \\ line\nreturn\rtab\tback\b");
    "byte-hint", (fun () -> round_trip_hint "\000\001\031\127\128\255");
    "unicode-hint", (fun () -> round_trip_hint "return λ with 日本語");
    "declaration-like-hint", (fun () -> round_trip_hint "\" def injected : Nat := 9 --");
    "unresolved-default", (fun () -> refusal
      "unresolved synth: materialize a checked candidate before checking"
      (Elab.check_in Global.initial hole));
    "unresolved-ignored-annotation", (fun () -> refusal
      "unresolved synth: materialize a checked candidate before checking"
      (Elab.check_in Global.initial
        "def result : Nat := case (inj 0 of 1 7 : sum (Nat)) with | 0 (x : synth \"Nat\") => x"));
    "empty-candidate", (fun () -> rejected (Parser.expression ""));
    "declaration-injection", (fun () -> rejected (Parser.expression "7 def injected : Nat := 9"));
    "axiom-injection", (fun () -> rejected (Parser.expression "7 axiom poison : Type 0"));
    "closing-token-injection", (fun () -> rejected (Parser.expression "7 )"));
    "wrong-type", (fun () -> invalid_candidate hole "()");
    "wrong-goal", (fun () -> invalid_candidate hole "(Type 0 : Type 1)");
    "unknown-variable", (fun () -> invalid_candidate hole "missing");
    "future-variable", (fun () -> invalid_candidate (hole ^ "def future : Nat := 7") "future");
    "self-reference", (fun () -> invalid_candidate hole "result");
    "linear-duplicate", (fun () -> invalid_candidate
      "def result : (1 x : Nat) -> Nat := synth \"identity\""
      "fun (1 x : Nat) => natAdd x x");
    "linear-unused", (fun () -> invalid_candidate
      "def result : (1 x : Nat) -> Nat := synth \"identity\""
      "fun (1 x : Nat) => 0");
    "erased-runtime-use", (fun () -> invalid_candidate
      "def result : (0 x : Nat) -> Nat := synth \"ignore\""
      "fun (0 x : Nat) => x");
    "bad-prefix", (fun () -> rejected (Synthesis.next ("def bad : Nat := ()\n" ^ hole)));
    "bad-goal", (fun () -> rejected (Synthesis.next "def result : 7 := synth \"a term\""));
    "unknown-goal", (fun () -> rejected (Synthesis.next "def result : Missing := synth \"a term\""));
    "no-hole-fully-checked", (fun () -> rejected (Synthesis.next "def bad : Nat := ()"));
    "no-hole-valid", (fun () -> complete "def result : Nat := 7");
    "empty-program", (fun () -> complete "");
    "no-hole-apply-refused", (fun () -> refusal "source has no unresolved synth"
      (Synthesis.apply "def result : Nat := 7" "8"));
    "bad-suffix-on-final-check", (fun () ->
      let* expanded = explain (Synthesis.apply (hole ^ "def bad : Nat := ()") "7") in
      rejected (Synthesis.next expanded));
    "failed-candidate-keeps-request", (fun () ->
      let* before = next_request hole in
      let* () = invalid_candidate hole "missing" in
      let* after = next_request hole in
      require (before = after) "a failed candidate changed the request");
    "direct-axiom", (fun () -> refusal "synthesis disallows every source axiom: poison"
      (Synthesis.next ("axiom poison : Nat\n" ^ hole)));
    "transitive-axiom", (fun () -> refusal "synthesis disallows every source axiom: Poison"
      (Synthesis.next ("axiom Poison : Type 0\ndef Alias : Type 0 := Poison\n" ^ hole)));
    "suffix-axiom", (fun () -> refusal "synthesis disallows every source axiom: poison"
      (Synthesis.next (hole ^ "axiom poison : Nat")));
    "source-nat-repostulate", (fun () -> refusal "synthesis disallows every source axiom: Nat"
      (Synthesis.next ("axiom Nat : Type 0\n" ^ hole)));
    "redefined-hole", (fun () -> refusal
      "synthesis refuses a declaration that redefines result"
      (Synthesis.next ("def result : Nat := 7\n" ^ hole)));
    "redefined-hole-apply", (fun () -> refusal
      "synthesis refuses a declaration that redefines result"
      (Synthesis.apply ("def result : Nat := 7\n" ^ hole) "result"));
    "redefined-prefix", (fun () -> refusal
      "synthesis refuses a declaration that redefines base"
      (Synthesis.next ("def base : Nat := 7\ndef base : Nat := 8\n" ^ hole)));
    "redefined-suffix-on-final-check", (fun () ->
      let* expanded = explain (Synthesis.apply (hole ^ "def result : Nat := 8") "7") in
      refusal "synthesis refuses a declaration that redefines result"
        (Synthesis.next expanded));
    (* The body stays ordinary: a self-referential body loops in a build
       without the guard, and a regression must fail, not hang. *)
    "redefined-builtin-type", (fun () -> refusal
      "synthesis refuses a declaration that redefines Nat"
      (Synthesis.next ("def Nat : Type 0 := Type 0\n" ^ hole)));
    "redefined-family", (fun () -> refusal
      "synthesis refuses a declaration that redefines N"
      (Synthesis.next (family ^ family ^ hole)));
    "redefined-constructor", (fun () -> refusal
      "synthesis refuses a declaration that redefines zero"
      (Synthesis.next (family ^ "mu M : Type 0 := | zero : M\n" ^ hole)));
    "redefined-recursive", (fun () -> refusal
      "synthesis refuses a declaration that redefines base"
      (Synthesis.next
        ("def base : Nat := 7\ndef rec base : Nat -> Nat := fun (x : Nat) => x\n" ^ hole)));
    "missing-hint", (fun () -> rejected (Parser.parse "def result : Nat := synth"));
    "bad-escape", (fun () -> rejected (Parser.parse {|def result : Nat := synth "\q"|}));
    "bad-byte-escape", (fun () -> rejected (Parser.parse {|def result : Nat := synth "\256"|}));
    "short-byte-escape", (fun () -> rejected (Parser.parse {|def result : Nat := synth "\12"|}));
    "unterminated-hint", (fun () -> rejected (Parser.parse "def result : Nat := synth \"open"));
    "raw-newline-hint", (fun () -> rejected (Parser.parse "def result : Nat := synth \"line\nline\"")) ]

let unsupported_sources : (string * string) list =
  [ "nested-lambda", "def id : Nat -> Nat := fun (x : Nat) => synth \"x\"";
    "nested-let", "def result : Nat := let x : Nat := synth \"zero\" in x";
    "type-position", "def result : synth \"Nat\" := 7";
    "binder-type", "def id : Nat -> Nat := fun (x : synth \"Nat\") => x";
    "recursive-body", "def rec result : Nat := synth \"zero\"";
    "family-kind", "mu N : synth \"universe\" :=";
    "family-parameter", "mu N (A : synth \"universe\") : Type 0 :=";
    "constructor-type", "mu N : Type 0 := | zero : synth \"N\"";
    "later-unsupported", hole ^ "def id : Nat -> Nat := fun (x : Nat) => synth \"x\"" ]

let restricted_candidates : (string * string) list =
  [ "body", "auto";
    "binder-type", "fun (x : auto) => x";
    "arrow-domain", "(x : auto) -> Nat";
    "arrow-codomain", "(x : Nat) -> auto";
    "star-domain", "(x : auto) * Nat";
    "annotation", "(7 : auto)";
    "let-type", "let x : auto := 7 in x";
    "let-value", "let x : Nat := auto in x";
    "let-body", "let x : Nat := 7 in auto";
    "pair", "(7, auto)";
    "tuple", "tuple (7, auto)";
    "sum", "sum (Nat, auto)";
    "product", "prod (Nat, auto)";
    "projection", "auto.1";
    "injection", "inj 0 of 1 auto";
    "absurd", "absurd auto";
    "application", "natAdd 7 auto";
    "case-motive", "case 7 as x return auto with";
    "case-branch", "case 7 with | 0 (x : Nat) => auto";
    "case-binder", "case 7 with | 0 (x : auto) => x";
    "match-motive", "match zero as x in N return auto with | zero => zero";
    "match-field", "match zero with | succ (x : auto) => x";
    "match-body", "match zero with | zero => auto" ]

let cases : (string * (unit -> (unit, string) result)) list =
  boundary_cases
  @ List.map (fun (name, source) ->
      ("unsupported-" ^ name, fun () -> refusal unsupported (Synthesis.next source)))
      unsupported_sources
  @ List.concat_map (fun (name, candidate) ->
      [ ("candidate-auto-" ^ name, fun () ->
          let* _parsed = explain (Parser.expression candidate) in
          refusal auto_refusal (Synthesis.apply hole candidate));
        ("source-auto-" ^ name, fun () ->
          refusal auto_refusal (Synthesis.next ("def result : Nat := " ^ candidate))) ])
      restricted_candidates
  @ [ "candidate-nested-synth", (fun () -> refusal unsupported
        (Synthesis.apply hole "let x : Nat := synth \"zero\" in x"));
      "candidate-synth-binder", (fun () -> refusal unsupported
        (Synthesis.apply hole "fun (x : synth \"Nat\") => x"));
      "candidate-synth-motive", (fun () -> refusal unsupported
        (Synthesis.apply hole "case 7 as x return synth \"Nat\" with"));
      "candidate-synth-field", (fun () -> refusal unsupported
        (Synthesis.apply hole "match zero with | succ (x : synth \"Nat\") => x")) ]

let () =
  let passed = List.fold_left
    (fun (count : int) ((name : string), (run : unit -> (unit, string) result)) ->
      run () |> Result.fold
        ~ok:(fun () -> Printf.printf "SYNTHESIS %s OK\n" name; count + 1)
        ~error:(fun (message : string) ->
          Printf.printf "SYNTHESIS %s FAIL: %s\n" name message; count))
    0 cases in
  Printf.printf "SYNTHESIS-OK %d/%d\n" passed (List.length cases);
  if Int.equal passed (List.length cases) then print_endline "SYNTHESIS OK"
  else (print_endline "SYNTHESIS FAIL"; exit 1)
