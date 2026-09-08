(** The M0 kernel suite (brief section 3.11).  Six groups run in one
    order and each prints its own count, then one verdict line closes
    the run:

    - PARSE, the round trip of Stage A, over every ".kan" file of
      fixtures/, of neg/ and of erase-neg/;
    - CHECK, one line per positive fixture, where OK means the file
      elaborates, checks, and prints the byte for byte text of
      golden/NAME.checked;
    - ERASE, one line per positive fixture, where OK means the same
      file erases and prints the byte for byte text of
      golden/NAME.erased (Stage C, brief section 3.6);
    - NEG, one line per negative, where OK means the file fails and
      [Error.message] equals the single line of neg/NAME.err;
    - ERASE-NEG, one line per erasure negative, where OK means the file
      checks and its erasure fails with the single line of
      erase-neg/NAME.err (M1 Stage G, brief 3.8);
    - KNEG, the shapes M0 declares and does not admit, reached from
      OCaml because no surface production spells them.

    One argument, the test root, not the fixtures directory (SB-D15);
    [root_default] when the argument list is empty.  The suite never
    leaves the result track:  it throws no OCaml failure of its own,
    and the stdlib file calls that can fail pass through the one
    boundary [attempt_sys] below, which reports the failure as a FAIL
    line (SA-D19).

    A FAIL line carries its reason after a colon, in every group, so a
    mutation run reads why a fixture died and not only that it did
    (SB-D36).  The count lines and the verdict line hold the shape the
    gates read. *)

let root_default : string = "test"

(** The file boundary moved to test/sys_io.ml at Stage D (SD-D14).  Two
    runners live under test/ from Stage D on, main.exe and wasm.exe, and
    both read files;  one catch site serves both, so the repository still
    holds exactly one of them, which gate SD-G11 of the brief reads. *)
let read_file : string -> (string, string) result = Sys_io.read_file

(** The ".kan" files of a directory, sorted, without the extension. *)
let kan_names : string -> (string list, string) result = Sys_io.kan_names

let path_of (dir : string) (name : string) (ext : string) : string =
  Filename.concat dir (name ^ ext)

let ( let* ) = Result.bind

(** The round trip for one file:  text, tree, text, tree. *)
let round_trip (path : string) : (unit, string) result =
  let* src = read_file path in
  let* first =
    Kanon_surface.Parser.parse src |> Result.map_error Kanon_kernel.Error.message
  in
  let printed = Kanon_surface.Syntax.print first in
  let* second =
    Kanon_surface.Parser.parse printed |> Result.map_error Kanon_kernel.Error.message
  in
  if first = second then Ok ()
  else Error "the printed text parses to a different tree"

(** A positive fixture:  it checks, and its checked form is the golden
    text byte for byte. *)
let check_fixture (root : string) (name : string) : (unit, string) result =
  let* src = read_file (path_of (Filename.concat root "fixtures") name ".kan") in
  let* golden = read_file (path_of (Filename.concat root "golden") name ".checked") in
  let* rows =
    Kanon_surface.Elab.check_text Kanon_kernel.Global.initial src
    |> Result.map_error Kanon_kernel.Error.to_string
  in
  let printed = Kanon_surface.Elab.checked_form rows in
  if String.equal printed golden then Ok ()
  else Error "the checked form is not the golden text"

(** A positive fixture at the erasure:  it checks, it erases in the
    globals it was checked in, and the erased program is the golden
    text byte for byte.  The suite reads the same text the driver
    prints, because both call [Erase.print] of [Erase.program]
    (SC-D1). *)
let erase_fixture (root : string) (name : string) : (unit, string) result =
  let* src = read_file (path_of (Filename.concat root "fixtures") name ".kan") in
  let* golden = read_file (path_of (Filename.concat root "golden") name ".erased") in
  let* globals, rows =
    Kanon_surface.Elab.check_in Kanon_kernel.Global.initial src
    |> Result.map_error Kanon_kernel.Error.to_string
  in
  let* out =
    Kanon_kernel.Erase.program globals rows
    |> Result.map_error Kanon_kernel.Error.to_string
  in
  let printed = Kanon_kernel.Erase.print out in
  if String.equal printed golden then Ok ()
  else Error "the erased form is not the golden text"

(** A negative:  it fails, and the failure is the one the sidecar
    names.  The sidecar holds one line, so its trailing newline is
    dropped before the comparison. *)
let check_negative (root : string) (name : string) : (unit, string) result =
  let dir = Filename.concat root "neg" in
  let* src = read_file (path_of dir name ".kan") in
  let* want = read_file (path_of dir name ".err") in
  Kanon_surface.Elab.check_text Kanon_kernel.Global.initial src
  |> Result.fold
       ~ok:(fun (_rows : (string * Kanon_kernel.Global.entry) list) ->
         Error "the file checks and the negative expects it to fail")
       ~error:(fun (e : Kanon_kernel.Error.t) ->
         let got = Kanon_kernel.Error.message e in
         if String.equal got (String.trim want) then Ok ()
         else Error (Printf.sprintf "the message is \"%s\"" got))

(** An erasure negative:  the file checks, and erasure refuses it with
    the message the sidecar names.  The interim word of a mu shape sits
    here, because a positive fixture that erases nothing cannot pin it
    and a checker negative never reaches erasure (brief 3.8, SG-D7).
    Erasure runs in the globals the file was checked in, exactly as the
    driver does. *)
let erase_negative (root : string) (name : string) : (unit, string) result =
  let dir = Filename.concat root "erase-neg" in
  let* src = read_file (path_of dir name ".kan") in
  let* want = read_file (path_of dir name ".err") in
  let* globals, rows =
    Kanon_surface.Elab.check_in Kanon_kernel.Global.initial src
    |> Result.map_error Kanon_kernel.Error.to_string
  in
  Kanon_kernel.Erase.program globals rows
  |> Result.fold
       ~ok:(fun (_out : (string * Kanon_kernel.Erase.entry) list) ->
         Error "the file erases and the negative expects the erasure to fail")
       ~error:(fun (e : Kanon_kernel.Error.t) ->
         let got = Kanon_kernel.Error.message e in
         if String.equal got (String.trim want) then Ok ()
         else Error (Printf.sprintf "the message is \"%s\"" got))

(** The formers M1 declares and does not admit.  M1 Stage G admits the
    left former at a mu shape, so the row moved to the right former,
    which is the coinductive reading a mu shape does not carry:  the
    kernel answers with the milestone that brings it (SPEC.md:31).  No
    surface production spells a right former at a mu shape, so the term
    is built here. *)
let kneg_smu () : (unit, string) result =
  let shape : Kanon_kernel.Term.t Kanon_kernel.Shape.t =
    Kanon_kernel.Shape.SMu ("F", [ Kanon_kernel.Term.Univ Kanon_kernel.Level.zero ])
  in
  let diagram : Kanon_kernel.Term.t =
    Kanon_kernel.Term.Sec (Kanon_kernel.Shape.SColl 0, [])
  in
  Kanon_kernel.Check.infer_term Kanon_kernel.Global.initial
    (Kanon_kernel.Term.Ran (shape, diagram))
  |> Result.fold
       ~ok:(fun (_v : Kanon_kernel.Value.t) ->
         Error "the right former at a mu shape is admitted at M1")
       ~error:(fun (e : Kanon_kernel.Error.t) ->
         let got = Kanon_kernel.Error.message e in
         if String.equal got "a right former at a mu shape arrives at M2" then Ok ()
         else Error (Printf.sprintf "the message is \"%s\"" got))

(** A body the M1 guard admits, built here because this row reads the
    guard itself and not the elaborator that calls it (SI-D11):  one
    formal, one elimination of that formal, and one call of "self" at a
    leg binder of a branch of that elimination, which is a binder the
    order marks Smaller (lib/order.ml:392).  The certificate therefore
    guards the definition at position 0. *)
let guarded_self : Kanon_kernel.Term.t =
  let arrow : Kanon_kernel.Term.t Kanon_kernel.Shape.t =
    Kanon_kernel.Shape.SPi
      (Kanon_kernel.Quantity.Many, "n", Kanon_kernel.Term.Global "N")
  in
  let call : Kanon_kernel.Term.t =
    Kanon_kernel.Term.Out
      ( arrow,
        Kanon_kernel.Term.APt (Kanon_kernel.Quantity.Many, Kanon_kernel.Term.Var 0),
        Kanon_kernel.Term.Global "self" )
  in
  let branch : Kanon_kernel.Term.addr * Kanon_kernel.Term.leg =
    ( Kanon_kernel.Term.ACtor "succ",
      {
        Kanon_kernel.Term.l_binders = [ (Kanon_kernel.Quantity.Many, "m") ];
        l_body = call;
      } )
  in
  let inner : Kanon_kernel.Term.t =
    Kanon_kernel.Term.Elim
      {
        Kanon_kernel.Term.e_shape = Kanon_kernel.Shape.SMu ("N", []);
        e_scrut = Kanon_kernel.Term.Var 0;
        e_scrut_q = Kanon_kernel.Quantity.Many;
        e_motive =
          Some
            {
              Kanon_kernel.Term.m_ind = Some "N";
              m_idx = [];
              m_self = "x";
              m_body = Kanon_kernel.Term.Global "N";
            };
        e_branches = [ branch ];
      }
  in
  Kanon_kernel.Term.Sec
    ( arrow,
      [
        {
          Kanon_kernel.Term.l_binders = [ (Kanon_kernel.Quantity.Many, "n") ];
          l_body = inner;
        };
      ] )

(** The totality guard at M1 (brief 3.9, SI-D6).  The first half is the
    bare self reference:  no chain of elimination legs makes the
    argument of that call smaller, so the guard refuses it with the
    termination line every negative fixture of this stage pins, and no
    longer with the M0 milestone word.  The second half is the guarded
    body above, which the guard answers with its position.  The row
    reads both M1 answers;  the fixtures of M1 Stage I enter as ".kan"
    files through the "def rec" production of brief 3.7 and never
    here. *)
let kneg_self () : (unit, string) result =
  let* () =
    Kanon_kernel.Totality.guard Kanon_kernel.Global.initial "self"
      (Kanon_kernel.Term.Global "Nat") (Kanon_kernel.Term.Global "self")
    |> Result.fold
         ~ok:(fun (_g : int option) ->
           Error "the unguarded self reference is admitted at M1")
         ~error:(fun (e : Kanon_kernel.Error.t) ->
           let got = Kanon_kernel.Error.message e in
           if
             String.equal got
               "recursive definition self failed the structural termination guard"
           then Ok ()
           else Error (Printf.sprintf "the message is \"%s\"" got))
  in
  Kanon_kernel.Totality.guard Kanon_kernel.Global.initial "self"
    (Kanon_kernel.Term.Global "Nat") guarded_self
  |> Result.fold
       ~ok:(fun (g : int option) ->
         g
         |> Option.fold
              ~none:(Error "the guarded self reference answers no position")
              ~some:(fun (k : int) ->
                if Int.equal k 0 then Ok ()
                else Error (Printf.sprintf "the guarded position is %d" k)))
       ~error:(fun (e : Kanon_kernel.Error.t) ->
         Error
           (Printf.sprintf "the message is \"%s\"" (Kanon_kernel.Error.message e)))

(** The KNEG rows by name, so the group reads one list of names as
    every other group does. *)
let kneg (name : string) : (unit, string) result =
  match () with
  | () when String.equal name "smu" -> kneg_smu ()
  | () when String.equal name "self" -> kneg_self ()
  | () -> Error (Printf.sprintf "no kernel negative is named \"%s\"" name)

(** One line of a group, and whether it passed. *)
let report (kind : string) (name : string) (r : (unit, string) result) : bool =
  r
  |> Result.fold
       ~ok:(fun () ->
         print_string (Printf.sprintf "%s %s OK\n" kind name);
         true)
       ~error:(fun (m : string) ->
         print_string (Printf.sprintf "%s %s FAIL: %s\n" kind name m);
         false)

(** Run one group and print its count line.  The answer is the pair of
    the passing count and the total, which the verdict folds. *)
let group (kind : string) (label : string) (run : string -> (unit, string) result)
    (names : string list) : int * int =
  let passed =
    List.fold_left
      (fun (acc : int) (name : string) ->
        if report kind name (run name) then acc + 1 else acc)
      0 names
  in
  let total = List.length names in
  print_string (Printf.sprintf "%s %d/%d\n" label passed total);
  (passed, total)

(** PARSE prints its count alone:  a passing round trip says nothing,
    because eighteen positives and eight negatives would otherwise
    print twenty six lines that carry no reading (SB-D35). *)
let parse_group (dirs : (string * string list) list) : int * int =
  let files =
    List.concat_map
      (fun ((dir : string), (names : string list)) ->
        List.map (fun (name : string) -> (dir, name)) names)
      dirs
  in
  let passed =
    List.fold_left
      (fun (acc : int) ((dir : string), (name : string)) ->
        round_trip (path_of dir name ".kan")
        |> Result.fold
             ~ok:(fun () -> acc + 1)
             ~error:(fun (m : string) ->
               print_string (Printf.sprintf "PARSE %s FAIL: %s\n" name m);
               acc))
      0 files
  in
  let total = List.length files in
  print_string (Printf.sprintf "PARSE-OK %d/%d\n" passed total);
  (passed, total)

(** Exercise computation as well as admission of recursive groups. *)
let recursive_values (_name : string) : (unit, string) result =
  let open Kanon_kernel in
  let source = {|
mu N : Type 0 with | zero : N | succ : N -> N
mu A : Type 0 with | leaf : A | node : B -> A
and B : Type 0 with | cons : A -> B
mu V : (0 i : N) -> Type 0 with
| vz : V zero
| vs : (0 i : N) -> V i -> V (succ i)
def rec length : (0 i : N) -> V i -> N := fun (0 i : N) (v : V i) => case v as x in V j return N with | vz => zero | vs 0 j w => succ (length j w)
def rec double : N -> N := fun (n : N) => case n as x in N return N with | zero => zero | succ m => succ (succ (double m))
def rec sizeA : A -> Nat := fun (a : A) => case a as x in A return Nat with | leaf => 0 | node b => natAdd 1 (sizeB b)
and sizeB : B -> Nat := fun (b : B) => case b as x in B return Nat with | cons a => natAdd 1 (sizeA a)
def rec f : N -> N := fun (n : N) => case n as x in N return N with | zero => zero | succ m => g m
and g : N -> N := fun (n : N) => zero
and spare : N := zero
def rec keep : Nat -> N -> Nat := fun (a : Nat) => fun (n : N) => case n as x in N return Nat with | zero => a | succ m => keep a m
def rec choose : N -> Nat -> Nat := fun (n : N) => case n as x in N return (Nat -> Nat) with | zero => fun (a : Nat) => a | succ m => choose m
def doubled : N := double (succ (succ zero))
def four : N := succ (succ (succ (succ zero)))
def z : N := zero
def mutualValue : Nat := sizeA (node (cons leaf))
def two : Nat := 2
def helper : N := f (succ zero)
def helperDirect : N := g zero
def kept : Nat := keep 7 (succ (succ zero))
def seven : Nat := 7
def chosen : Nat := choose (succ (succ zero)) 7
def indexed : N := length (succ zero) (vs zero vz)
def one : N := succ zero
def partial : N -> Nat := keep 7
def neutral : N -> Nat := fun (n : N) => keep 7 n
|} in
  let run () =
    let* globals, _rows = Kanon_surface.Elab.check_in Global.initial source in
    let normal n =
      let* v = Eval.eval globals [] (Term.Global n) in
      let* t = Eval.quote globals 0 v in
      Ok (Pp.term [] t)
    in
    let* () =
      List.fold_left (fun acc (actual, expected) ->
          let* () = acc in
          let* got = normal actual in
          let* want = normal expected in
          if String.equal got want then Ok ()
          else Error (Error.Mismatch (actual ^ " did not compute: " ^ got)))
        (Ok ()) ["doubled", "four"; "mutualValue", "two"; "helper", "z";
                 "helperDirect", "z"; "spare", "z"; "kept", "seven";
                 "chosen", "seven"; "indexed", "one"]
    in
    let* () =
      List.fold_left (fun acc n ->
          let* () = acc in
          let* v = Eval.eval globals [] (Term.Global n) in
          if Option.is_some (Value.as_neutral v) then Ok ()
          else Error (Error.Mismatch (n ^ " unfolded before its guarded argument")))
        (Ok ()) ["double"; "keep"; "partial"]
    in
    let* neutral = Eval.eval globals [] (Term.Global "neutral") in
    let* legs = Value.as_sec neutral |> Option.to_result ~none:(Error.Mismatch "neutral lambda") in
    let _shape, legs = legs in
    let* leg = Rules.one_of legs |> Option.to_result ~none:(Error.Mismatch "neutral leg") in
    let* body = Rules.open_closure (Eval.ev globals) leg.Value.vl_clo [Value.var 0] in
    let* () =
      if Option.is_some (Value.as_neutral body) then Ok ()
      else Error (Error.Mismatch "recursive call unfolded on a neutral argument")
    in
    let* entry = Global.find "double" globals |> Option.to_result ~none:(Error.Unbound "double") in
    let* def = Global.def_of entry |> Option.to_result ~none:(Error.Mismatch "double definition") in
    let opaque = Global.add "double" (Global.Def {def with reducible = false}) globals in
    let* value = Eval.eval opaque [] (Term.Global "doubled") in
    if Option.is_some (Value.as_neutral value) then Ok ()
    else Error (Error.Mismatch "an explicitly opaque recursive definition unfolded")
  in
  Result.map_error Error.to_string (run ())

let full ((passed : int), (total : int)) : bool = Int.equal passed total && total > 0

(** Stage J moves these refusal tests to the positive suite.  Require
    all replacements before accepting an empty erasure-negative group,
    so deleting the migrated coverage cannot silently pass the suite. *)
let migrated_erasure_fixtures : string list =
  [ "mu-erase"; "mu-rec-direct"; "mu-rec-indexed"; "mu-rec-mutual" ]

let sound ((passed : int), (total : int)) : bool = Int.equal passed total

let verdict (groups : (int * int) list) (may_be_empty : (int * int) list) : unit =
  match () with
  | () when List.for_all full groups && List.for_all sound may_be_empty ->
      print_string "SUITE-KERNEL OK\n";
      exit 0
  | () ->
      print_string "SUITE-KERNEL FAIL\n";
      exit 1

let run (root : string) (fixtures : string list) (negatives : string list)
    (erase_negatives : string list) : unit =
  let fixtures_dir = Filename.concat root "fixtures" in
  let neg_dir = Filename.concat root "neg" in
  let erase_neg_dir = Filename.concat root "erase-neg" in
  let parsed =
    parse_group
      [
        (fixtures_dir, fixtures);
        (neg_dir, negatives);
        (erase_neg_dir, erase_negatives);
      ]
  in
  let checked = group "CHECK" "CHECK-OK" (check_fixture root) fixtures in
  let erased = group "ERASE" "ERASE-OK" (erase_fixture root) fixtures in
  let refused = group "NEG" "NEG-OK" (check_negative root) negatives in
  let unerased =
    group "ERASE-NEG" "ERASE-NEG-OK" (erase_negative root) erase_negatives
  in
  let closed = group "KNEG" "KNEG-OK" kneg [ "smu"; "self" ] in
  let recursive = group "REC" "REC-OK" recursive_values [ "values" ] in
  let migration =
    group "MIGRATED" "MIGRATED-OK"
      (fun (name : string) ->
        if List.mem name fixtures then Ok ()
        else Error "the migrated erasure fixture is missing")
      migrated_erasure_fixtures
  in
  verdict [ parsed; checked; erased; refused; closed; recursive; migration ]
    [ unerased ]

let fail_out (m : string) : unit =
  print_string (Printf.sprintf "SUITE %s\n" m);
  print_string "SUITE-KERNEL FAIL\n";
  exit 1

let () =
  let root =
    match Array.to_list Sys.argv with
    | _prog :: d :: _rest -> d
    | [] -> root_default
    | [ _only ] -> root_default
  in
  let listed =
    let* fixtures = kan_names (Filename.concat root "fixtures") in
    let* negatives = kan_names (Filename.concat root "neg") in
    let* erase_negatives = kan_names (Filename.concat root "erase-neg") in
    Ok (fixtures, negatives, erase_negatives)
  in
  listed
  |> Result.fold
       ~ok:
         (fun
           (((fixtures : string list), (negatives : string list),
             (erase_negatives : string list)))
         -> run root fixtures negatives erase_negatives)
       ~error:fail_out
