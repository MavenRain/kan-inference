(** The M0 emission suite (brief section 3.7).  One group runs over the
    positive fixtures and one verdict line closes the run.

    A fixture joins the suite when it elaborates against
    [Global.initial] and defines [main] (SD-D9).  Every other fixture is
    skipped without a line, because the kernel suite already reads it.

    Five steps run for each fixture, in this order, and the first step
    that fails names the reason:

    - emit, the driver path of bin/kanon.ml:  check, erase, then
      [Emit.program] with the export [main];
    - validate, [wasm-opt] with the four feature flags, which writes the
      text form beside the module and its own noise into NAME.err;
    - the golden, a byte for byte reading of test/golden/NAME.wat;
    - the expectation, which comes from the kernel alone (evaluate
      [main], take the weak head normal form, read the literal), never
      from a sidecar;
    - the answer, [node] on dev/run-node.mjs, compared with that
      expectation.  A literal inside the i31 range is printed;  a larger
      literal traps, which the runner reports as exit 1 (SK-D4, d10).

    Two arguments, the test root and the output directory;  the second
    is optional and defaults to ROOT/_build/wasm-suite, which the suite
    creates when it is missing.  Every command runs through
    [Sys.command] with absolute paths and shell redirection, so nothing
    is read from a pipe.  The suite never leaves the result track:  the
    stdlib calls that can fail pass through [Sys_io.attempt_sys], the
    one catch site of the repository (SD-D14). *)

let root_default : string = "test"
let wasm_opt : string = "/opt/homebrew/bin/wasm-opt"
let node : string = "/opt/homebrew/bin/node"

(** The four features of the toolchain probe, in the order the brief
    writes them. *)
let features : string =
  "--enable-gc --enable-reference-types --enable-tail-call \
   --enable-exception-handling"

(** The steps of one fixture stay on the result track. *)
let ( let* ) = Result.bind

let absolute (path : string) : string =
  if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path

let path_of (dir : string) (name : string) (ext : string) : string =
  Filename.concat dir (name ^ ext)

(** The first line of a text, trimmed, which reports one tool failure in
    one line of the suite.  The text is consumed as a sequence, so no
    range is computed. *)
let first_line (text : string) : string =
  String.to_seq text
  |> Seq.take_while (fun (c : char) -> not (Char.equal c '\n'))
  |> String.of_seq |> String.trim

let ensure_dir (dir : string) : (unit, string) result =
  if Sys.file_exists dir then Ok ()
  else Sys_io.attempt_sys (fun () -> Sys.mkdir dir 0o755)

(** The output directory and its parent, so ROOT/_build/wasm-suite
    exists after a clean. *)
let ensure_outdir (dir : string) : (unit, string) result =
  let* () = ensure_dir (Filename.dirname dir) in
  ensure_dir dir

let write_file (path : string) (bytes : string) : (unit, string) result =
  Sys_io.attempt_sys (fun () ->
      Out_channel.with_open_bin path (fun (oc : Out_channel.t) ->
          Out_channel.output_string oc bytes))

(** The globals and the rows of one fixture, checked against
    [Global.initial] exactly as the driver checks them
    (bin/kanon.ml:41).  The globals the elaborator answers hold the
    inductive families of the file, which the rows alone do not carry, so
    the suite reads them and never rebuilds them from the rows. *)
let checked_of (root : string) (name : string) :
    ( Kanon_kernel.Global.t * (string * Kanon_kernel.Global.entry) list,
      string )
    result =
  let* src =
    Sys_io.read_file (path_of (Filename.concat root "fixtures") name ".kan")
  in
  Kanon_surface.Elab.check_in Kanon_kernel.Global.initial src
  |> Result.map_error Kanon_kernel.Error.to_string

let defines_main (rows : (string * Kanon_kernel.Global.entry) list) : bool =
  List.exists
    (fun ((n : string), (_e : Kanon_kernel.Global.entry)) -> String.equal n "main")
    rows

let not_a_literal : string = "kernel value not a literal"

(** The value the kernel gives [main], the only source of the
    expectation (SD-D9). *)
let kernel_value (globals : Kanon_kernel.Global.t) :
    (Kanon_kernel.Bignum.t, string) result =
  let* v =
    Kanon_kernel.Eval.eval globals [] (Kanon_kernel.Term.Global "main")
    |> Result.map_error Kanon_kernel.Error.to_string
  in
  let* w =
    Kanon_kernel.Eval.whnf globals v |> Result.map_error Kanon_kernel.Error.to_string
  in
  let* lit = Kanon_kernel.Value.as_lit w |> Option.to_result ~none:not_a_literal in
  match lit with
  | Kanon_kernel.Literal.LInt n -> Ok n
  | Kanon_kernel.Literal.LString _ -> Error not_a_literal

(** The module bytes, along the driver path:  erase in the globals the
    file was checked in, then emit with the export [main]. *)
let emitted (globals : Kanon_kernel.Global.t)
    (rows : (string * Kanon_kernel.Global.entry) list) : (string, string) result =
  let refuse (e : Kanon_kernel.Error.t) : string =
    "emit: " ^ Kanon_kernel.Error.to_string e
  in
  let* erased = Kanon_kernel.Erase.program globals rows |> Result.map_error refuse in
  Kanon_wasm.Emit.program Kanon_kernel.Global.initial erased ~export:"main"
  |> Result.map_error refuse

(** [wasm-opt] with the four features:  it assembles the module and
    prints the text form beside it.  The tool writes one warning into
    NAME.err on every call, which is noise, so only a non zero status is
    a failure. *)
let validate (outdir : string) (name : string) : (unit, string) result =
  let cmd =
    Printf.sprintf "%s %s -S -o %s %s 2> %s" wasm_opt
      (Filename.quote (path_of outdir name ".wasm"))
      (Filename.quote (path_of outdir name ".wat"))
      features
      (Filename.quote (path_of outdir name ".err"))
  in
  if Int.equal (Sys.command cmd) 0 then Ok ()
  else
    Sys_io.read_file (path_of outdir name ".err")
    |> Result.fold
         ~ok:(fun (t : string) -> Error ("validate: " ^ first_line t))
         ~error:(fun (m : string) -> Error ("validate: " ^ m))

(** The text form against its golden, byte for byte. *)
let golden_same (root : string) (outdir : string) (name : string) :
    (unit, string) result =
  let differs (_m : string) : string = "golden differs" in
  let* got =
    Sys_io.read_file (path_of outdir name ".wat") |> Result.map_error differs
  in
  let* want =
    Sys_io.read_file (path_of (Filename.concat root "golden") name ".wat")
    |> Result.map_error differs
  in
  if String.equal got want then Ok () else Error "golden differs"

(** What the runner did, in one phrase, for the FAIL line. *)
let observed (code : int) (printed : string) : string =
  if String.equal printed "" then Printf.sprintf "exit %d" code else printed

(** The answer of the node runner against the expectation.  A literal
    inside the range is printed and the runner exits 0;  a larger
    literal traps, so the runner exits 1 and prints nothing (SK-D4). *)
let node_answer (repo : string) (outdir : string) (name : string)
    (expected : Kanon_kernel.Bignum.t) :
    (unit, string) result =
  let cmd =
    Printf.sprintf "%s %s %s main > %s 2> %s" node
      (Filename.quote (Filename.concat repo (Filename.concat "dev" "run-node.mjs")))
      (Filename.quote (path_of outdir name ".wasm"))
      (Filename.quote (path_of outdir name ".out"))
      (Filename.quote (path_of outdir name ".nodeerr"))
  in
  let code = Sys.command cmd in
  let* out =
    Sys_io.read_file (path_of outdir name ".out")
    |> Result.map_error (fun (m : string) -> "node: " ^ m)
  in
  let printed = String.trim out in
  Kanon_kernel.Bignum.to_i31 expected
  |> Option.fold
       ~none:(if Int.equal code 1 && String.equal printed "" then Ok ()
         else Error
           (Printf.sprintf "node: expected a trap got %s" (observed code printed)))
       ~some:(fun (n : int) ->
         if Int.equal code 0 && String.equal printed (string_of_int n) then Ok ()
         else Error
           (Printf.sprintf "node: expected %d got %s" n (observed code printed)))

(** The five steps for one fixture, in the order of the brief. *)
let one (root : string) (repo : string) (outdir : string) (name : string)
    (globals : Kanon_kernel.Global.t)
    (rows : (string * Kanon_kernel.Global.entry) list) : (unit, string) result =
  let* bytes = emitted globals rows in
  let* () =
    write_file (path_of outdir name ".wasm") bytes
    |> Result.map_error (fun (m : string) -> "emit: " ^ m)
  in
  let* () = validate outdir name in
  let* () = golden_same root outdir name in
  let* expected = kernel_value globals in
  node_answer repo outdir name expected

let report (name : string) (r : (unit, string) result) : bool =
  r
  |> Result.fold
       ~ok:(fun () ->
         print_string (Printf.sprintf "EMIT %s OK\n" name);
         true)
       ~error:(fun (m : string) ->
         print_string (Printf.sprintf "EMIT %s FAIL: %s\n" name m);
         false)

(** The fixtures of the suite:  those that elaborate and define main
    (SD-D9).  Every other fixture is skipped without a line. *)
let selected (root : string) (names : string list) :
    (string
    * (Kanon_kernel.Global.t * (string * Kanon_kernel.Global.entry) list))
    list =
  List.filter_map
    (fun (name : string) ->
      Option.bind
        (checked_of root name |> Result.to_option)
        (fun (((globals : Kanon_kernel.Global.t),
               (rows : (string * Kanon_kernel.Global.entry) list)) :
               Kanon_kernel.Global.t
               * (string * Kanon_kernel.Global.entry) list) ->
          if defines_main rows then Some (name, (globals, rows)) else None))
    names

let verdict (passed : int) (total : int) : unit =
  print_string (Printf.sprintf "WASM-OK %d/%d\n" passed total);
  match () with
  | () when Int.equal passed total && total > 0 ->
      print_string "SUITE-WASM OK\n";
      exit 0
  | () ->
      print_string "SUITE-WASM FAIL\n";
      exit 1

let fail_out (m : string) : unit =
  print_string (Printf.sprintf "SUITE %s\n" m);
  print_string "SUITE-WASM FAIL\n";
  exit 1

let run (root_arg : string) (outdir_arg : string option) : unit =
  let root = absolute root_arg in
  let repo = Filename.dirname root in
  let outdir =
    outdir_arg
    |> Option.fold
         ~none:(Filename.concat (Filename.concat repo "_build") "wasm-suite")
         ~some:absolute
  in
  let listed =
    let* () = ensure_outdir outdir in
    Sys_io.kan_names (Filename.concat root "fixtures")
  in
  listed
  |> Result.fold
       ~ok:(fun (names : string list) ->
         let chosen = selected root names in
         let passed =
           List.fold_left
             (fun (acc : int)
                  (((name : string),
                    ((globals : Kanon_kernel.Global.t),
                     (rows : (string * Kanon_kernel.Global.entry) list)))) ->
               if report name (one root repo outdir name globals rows) then acc + 1
               else acc)
             0 chosen
         in
         verdict passed (List.length chosen))
       ~error:fail_out

let () =
  match Array.to_list Sys.argv with
  | [] -> fail_out "no argument vector"
  | _prog :: rest -> (
      match rest with
      | [] -> run root_default None
      | [ r ] -> run r None
      | r :: o :: _more -> run r (Some o))
