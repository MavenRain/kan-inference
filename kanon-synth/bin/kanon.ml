(** The kanon driver.  SA-D4: the executable exists from Stage A with
    spec-count only.  Stage B lands check and axioms, which need the
    checker and nothing else (SB-D5);  Stage D lands emit and Stage E
    lands run, so the five commands of plan section 10 are built.

    Exit codes.  0 is a file that checks, 1 is a file that does not, 2 is
    an emission the wasm back end refuses or a host that refuses the
    module, 3 is two hosts that disagree, 4 is a trap and 64 is a usage
    error or a missing file.  A check failure writes one
    [Error.to_string] line to stderr and nothing to stdout, so a caller
    reads stdout as the answer alone (SB-D5).

    Reading a file.  The whole repository holds one catch site, in
    test/main.ml, so this file reaches [In_channel] behind a
    [Sys.file_exists] guard (SB-D33) and reports a path it cannot see as
    a usage error.  A path that disappears between the guard and the
    read leaves the process, which is loud, and never a wrong answer.

    [Option.fold] reads its [~none] argument eagerly, so no arm of this
    file hides an [exit] behind it:  the two answers of a guard are an
    if and an else. *)

let usage () : unit =
  prerr_endline
    "usage: kanon check [--print|--erased] FILE | axioms FILE | emit FILE -o \
     OUT.wasm --export NAME | run FILE --export NAME [--host \
     node|wasmtime|kernel|both] | synth FILE -o OUTPUT.kan \
     [--provider EXECUTABLE | --replay RECEIPT] | spec-count"

let read_file (path : string) : string =
  if Sys.file_exists path then In_channel.with_open_bin path In_channel.input_all
  else (
    prerr_endline (Printf.sprintf "kanon: cannot read %s" path);
    exit 64)

(** The file, checked, with the globals it was checked in.  M1 Stage G:
    a mu group leaves its family in those globals and adds no entry row,
    so erasure and emission read this pair and not the rows alone
    (brief 3.8). *)
let checked_in (path : string) :
    Kanon_kernel.Global.t * (string * Kanon_kernel.Global.entry) list =
  Kanon_surface.Elab.check_in Kanon_kernel.Global.initial (read_file path)
  |> Result.fold
       ~ok:
         (fun
           (((g : Kanon_kernel.Global.t),
             (rows : (string * Kanon_kernel.Global.entry) list)))
         -> (g, rows))
       ~error:(fun (e : Kanon_kernel.Error.t) ->
         prerr_endline (Kanon_kernel.Error.to_string e);
         exit 1)

let checked (path : string) : (string * Kanon_kernel.Global.entry) list =
  snd (checked_in path)

(** Parse, elaborate and check one file against [Global.initial].  With
    the flag, print the checked form of every entry in order. *)
let run_check (print_form : bool) (path : string) : unit =
  let rows = checked path in
  if print_form then print_string (Kanon_surface.Elab.checked_form rows) else ()

(** "check --erased FILE" (SC-D1).  The file is checked first, so erasure
    never reads a declaration the kernel did not accept, and the erased
    program is printed in declaration order.  An erasure that refuses a
    declaration prints one error line and exits 1, exactly as a checker
    error does. *)
let run_erased (path : string) : unit =
  let globals, rows = checked_in path in
  Kanon_kernel.Erase.program globals rows
  |> Result.fold
       ~ok:(fun (out : (string * Kanon_kernel.Erase.entry) list) ->
         print_string (Kanon_kernel.Erase.print out))
       ~error:(fun (e : Kanon_kernel.Error.t) ->
         prerr_endline (Kanon_kernel.Error.to_string e);
         exit 1)

(** R-Q3: the postulates of the file, one name per line, in declaration
    order.  A file with no postulate prints nothing. *)
let run_axioms (path : string) : unit =
  List.iter print_endline (Kanon_surface.Elab.axiom_names (checked path))

(** "emit FILE -o OUT.wasm --export NAME" (3.4).  The file is checked and
    erased first, so the emitter never reads a declaration the kernel did
    not accept.  A front end error exits 1.  An emission refusal writes
    one line and exits 2.  A directory that does not exist is a usage
    error, on the [Sys.file_exists] guard of [read_file]. *)
let run_emit (path : string) (out : string) (export : string) : unit =
  if Sys.file_exists (Filename.dirname out) then ()
  else (
    prerr_endline (Printf.sprintf "kanon: cannot write %s" out);
    exit 64);
  let globals, rows = checked_in path in
  Kanon_kernel.Erase.program globals rows
  |> Result.fold
       ~ok:(fun (erased : (string * Kanon_kernel.Erase.entry) list) ->
         Kanon_wasm.Emit.program Kanon_kernel.Global.initial erased ~export
         |> Result.fold
              ~ok:(fun (bytes : string) ->
                Out_channel.with_open_bin out (fun (oc : Out_channel.t) ->
                    Out_channel.output_string oc bytes))
              ~error:(fun (e : Kanon_kernel.Error.t) ->
                prerr_endline ("kanon: emit: " ^ Kanon_kernel.Error.to_string e);
                exit 2))
       ~error:(fun (e : Kanon_kernel.Error.t) ->
         prerr_endline (Kanon_kernel.Error.to_string e);
         exit 1)

(** The argument order is fixed, so any other shape is a usage error. *)
let dispatch_emit (args : string list) : unit =
  match args with
  | [ path; "-o"; out; "--export"; name ] -> run_emit path out name
  | [] | _ :: _ ->
      usage ();
      exit 64

(** "run FILE --export NAME [--host node|wasmtime|kernel|both]" (3.1).
    One host answers alone;  [both] runs node and then wasmtime and
    compares the two answers, so a caller sees one number or one
    disagreement (SE-D1, SE-D4). *)
type mode = One of Host.host | Both

(** The globals the file was checked in, which the kernel host reads. *)
let globals_of (rows : (string * Kanon_kernel.Global.entry) list) :
    Kanon_kernel.Global.t =
  List.fold_left
    (fun (g : Kanon_kernel.Global.t)
         (((n : string), (e : Kanon_kernel.Global.entry))) ->
      Kanon_kernel.Global.add n e g)
    Kanon_kernel.Global.initial rows

(** Check, erase and emit, exactly as "emit" does:  a front end error
    exits 1 and an emission refusal exits 2. *)
let module_bytes (path : string) (export : string) :
    Kanon_kernel.Global.t * string =
  let globals, rows = checked_in path in
  let bytes =
    Kanon_kernel.Erase.program globals rows
    |> Result.fold
         ~ok:(fun (erased : (string * Kanon_kernel.Erase.entry) list) ->
           Kanon_wasm.Emit.program Kanon_kernel.Global.initial erased ~export
           |> Result.fold
                ~ok:(fun (bytes : string) -> bytes)
                ~error:(fun (e : Kanon_kernel.Error.t) ->
                  prerr_endline
                    ("kanon: emit: " ^ Kanon_kernel.Error.to_string e);
                  exit 2))
         ~error:(fun (e : Kanon_kernel.Error.t) ->
           prerr_endline (Kanon_kernel.Error.to_string e);
           exit 1)
  in
  (globals_of rows, bytes)

(** The module of one run lives in the temp directory and leaves with the
    two capture files beside it (SE-D3). *)
let remove_file (path : string) : unit =
  if Sys.file_exists path then Sys.remove path else ()

let cleanup (wasm : string) : unit =
  List.iter remove_file (wasm :: Host.captures ~wasm)

let answer (n : int) : unit = print_endline (string_of_int n)

let refused (h : Host.host) (m : string) : unit =
  prerr_endline (Printf.sprintf "kanon: run: %s invalid: %s" (Host.name h) m);
  exit 2

(** A disagreement names each side:  a value prints its number and a trap
    prints the word. *)
let show (o : Host.outcome) : string =
  match o with
  | Host.Value n -> string_of_int n
  | Host.Trap _text -> "trap"
  | Host.Invalid _text -> "invalid"

let disagree (a : Host.outcome) (b : Host.outcome) : unit =
  prerr_endline
    (Printf.sprintf "kanon: run: hosts disagree: node %s wasmtime %s" (show a)
       (show b));
  exit 3

let report_one (h : Host.host) (o : Host.outcome) : unit =
  match o with
  | Host.Value n -> answer n
  | Host.Trap text ->
      prerr_endline
        (Printf.sprintf "kanon: run: %s trap: %s" (Host.name h) text);
      exit 4
  | Host.Invalid text -> refused h text

(** The nine pairs, written out:  a refusal names its host, two traps are
    the module's own answer and every other pair is a disagreement. *)
let report_both (a : Host.outcome) (b : Host.outcome) : unit =
  match (a, b) with
  | Host.Value x, Host.Value y ->
      if Int.equal x y then answer x else disagree a b
  | Host.Value _x, Host.Trap _text -> disagree a b
  | Host.Trap _text, Host.Value _x -> disagree a b
  | Host.Trap _left, Host.Trap _right ->
      prerr_endline "kanon: run: trap on both hosts";
      exit 4
  | Host.Value _x, Host.Invalid text -> refused Host.Wasmtime text
  | Host.Trap _text, Host.Invalid text -> refused Host.Wasmtime text
  | Host.Invalid text, Host.Value _x -> refused Host.Node text
  | Host.Invalid text, Host.Trap _right -> refused Host.Node text
  | Host.Invalid text, Host.Invalid _right -> refused Host.Node text

(** A runner that is not beside the executable is a usage error, so a
    binary moved out of its tree says which file it wants (SE-D2). *)
let need_runners (root : string) (hosts : Host.host list) : unit =
  match List.filter_map (Host.missing_runner ~root) hosts with
  | [] -> ()
  | line :: _rest ->
      prerr_endline line;
      exit 64

let run_run (path : string) (export : string) (m : mode) : unit =
  if Sys.file_exists path then ()
  else (
    prerr_endline (Printf.sprintf "kanon: run: cannot read %s" path);
    usage ();
    exit 64);
  let root = Host.root () in
  let hosts =
    match m with One h -> [ h ] | Both -> [ Host.Node; Host.Wasmtime ]
  in
  need_runners root hosts;
  let globals, bytes = module_bytes path export in
  let wasm = Filename.temp_file "kanon-run-" ".wasm" in
  Out_channel.with_open_bin wasm (fun (oc : Out_channel.t) ->
      Out_channel.output_string oc bytes);
  let on (h : Host.host) : Host.outcome =
    Host.run_module ~root ~globals h ~wasm ~export
  in
  match m with
  | One h ->
      let o = on h in
      cleanup wasm;
      report_one h o
  | Both ->
      let node = on Host.Node in
      let wasmtime = on Host.Wasmtime in
      cleanup wasm;
      report_both node wasmtime

(** The argument order is fixed here too, and the host word is read in
    the shape itself, so an unknown word falls to the usage arm. *)
let dispatch_run (args : string list) : unit =
  match args with
  | [ path; "--export"; name ] -> run_run path name Both
  | [ path; "--export"; name; "--host"; "node" ] ->
      run_run path name (One Host.Node)
  | [ path; "--export"; name; "--host"; "wasmtime" ] ->
      run_run path name (One Host.Wasmtime)
  | [ path; "--export"; name; "--host"; "kernel" ] ->
      run_run path name (One Host.Kernel)
  | [ path; "--export"; name; "--host"; "both" ] -> run_run path name Both
  | [] | _ :: _ ->
      usage ();
      exit 64

(** "check [--print|--erased] FILE".  A flag is read before the path, so
    "check --print F", "check --erased F" and "check F" are the only
    three forms (SC-D1). *)
let dispatch_check (args : string list) : unit =
  match args with
  | "--print" :: path :: _rest -> run_check true path
  | [ "--print" ] ->
      usage ();
      exit 64
  | "--erased" :: path :: _rest -> run_erased path
  | [ "--erased" ] ->
      usage ();
      exit 64
  | path :: _rest -> run_check false path
  | [] ->
      usage ();
      exit 64

let dispatch_axioms (args : string list) : unit =
  match args with
  | path :: _rest -> run_axioms path
  | [] ->
      usage ();
      exit 64

(* A string match cannot be exhaustive without a last arm, so the last arm
   binds the unknown command instead of writing a wildcard. *)
let dispatch (cmd : string) (args : string list) : unit =
  match cmd with
  | "spec-count" -> print_string (Kanon_kernel.Spec_count.print ())
  | "check" -> dispatch_check args
  | "axioms" -> dispatch_axioms args
  | "emit" -> dispatch_emit args
  | "run" -> dispatch_run args
  | "synth" -> Synth_command.run args
  | "synth-request" -> Synth_command.request args
  | "synth-apply" -> Synth_command.apply args
  | _unknown ->
      usage ();
      exit 64

let () =
  match Array.to_list Sys.argv with
  | [] ->
      usage ();
      exit 64
  | _prog :: rest -> (
      match rest with
      | [] ->
          usage ();
          exit 64
      | cmd :: args -> dispatch cmd args)
