(** The hosts one module runs on (Stage E, 3.1).

    Node and wasmtime run the emitted module through the two dev runners,
    which share one contract:  the answer in decimal on stdout with exit
    0, "trap: TEXT" on stderr with exit 1, "invalid: TEXT" on stderr with
    exit 2, and a usage error with exit 64.  The kernel host runs no
    module.  It reduces the exported global with the evaluator, the
    oracle test/wasm.ml already trusts, so one command compares the
    engines against the kernel.

    The runners sit beside the executable.  [root] climbs four
    [Filename.dirname] steps from [Sys.executable_name], which reaches
    ROOT from ROOT/_build/default/bin/kanon.exe (SE-D2, SE-D14), so a
    copy of the tree under another directory runs its own runners.

    Every answer here is an [outcome], and the driver alone leaves the
    process. *)

type host = Node | Wasmtime | Kernel
type outcome = Value of int | Trap of string | Invalid of string

(** The launcher word and the runner path, relative to the root. *)
let node_runner : string * string = ("node", "dev/run-node.mjs")

let wasmtime_runner : string * string = ("zsh", "dev/run-wasmtime.sh")

let name (h : host) : string =
  match h with Node -> "node" | Wasmtime -> "wasmtime" | Kernel -> "kernel"

let runner (h : host) : (string * string) option =
  match h with
  | Node -> Some node_runner
  | Wasmtime -> Some wasmtime_runner
  | Kernel -> None

let root () : string =
  Filename.dirname
    (Filename.dirname (Filename.dirname (Filename.dirname Sys.executable_name)))

(** The line a caller reports when the host's runner is not beside the
    executable.  The kernel host needs no runner, so it never answers. *)
let missing_runner ~(root : string) (h : host) : string option =
  runner h
  |> Option.fold ~none:None ~some:(fun ((_launcher : string), (rel : string)) ->
         if Sys.file_exists (Filename.concat root rel) then None
         else
           Some
             (Printf.sprintf "kanon: run: cannot find %s beside the executable"
                rel))

(** The two capture files, beside the module the driver wrote. *)
let out_path ~(wasm : string) : string = wasm ^ ".out"

let err_path ~(wasm : string) : string = wasm ^ ".err"
let captures ~(wasm : string) : string list = [ out_path ~wasm; err_path ~wasm ]

let read_text (path : string) : string =
  if Sys.file_exists path then In_channel.with_open_bin path In_channel.input_all
  else ""

let blank (line : string) : bool = String.equal (String.trim line) ""

(** The first line a runner wrote that carries text. *)
let first_line (path : string) : string =
  read_text path |> String.split_on_char '\n'
  |> List.find_opt (fun (l : string) -> not (blank l))
  |> Option.fold ~none:"no message" ~some:String.trim

(** SE-D15:  the runner writes its own "trap: " or "invalid: " word, and
    the driver writes one too, so the prefix is dropped here and a caller
    reads "kanon: run: node trap: TEXT" once.  The drop walks the
    characters, so no range is computed. *)
let strip (prefix : string) (line : string) : string =
  if String.starts_with ~prefix line then
    String.to_seq line |> Seq.drop (String.length prefix) |> String.of_seq
  else line

(* An int match needs a last arm, so it binds the code instead of writing
   a wildcard, as bin/kanon.ml does for an unknown command. *)
let of_exit (code : int) ~(wasm : string) : outcome =
  match code with
  | 0 ->
      let text = String.trim (read_text (out_path ~wasm)) in
      int_of_string_opt text
      |> Option.fold
           ~none:(Invalid ("runner printed " ^ text))
           ~some:(fun (n : int) -> Value n)
  | 1 -> Trap (strip "trap: " (first_line (err_path ~wasm)))
  | _other -> Invalid (strip "invalid: " (first_line (err_path ~wasm)))

(** One runner, with every path quoted and both streams captured beside
    the module. *)
let spawn ((launcher : string), (rel : string)) ~(root : string)
    ~(wasm : string) ~(export : string) : outcome =
  Printf.sprintf "%s %s %s %s > %s 2> %s" launcher
    (Filename.quote (Filename.concat root rel))
    (Filename.quote wasm) (Filename.quote export)
    (Filename.quote (out_path ~wasm))
    (Filename.quote (err_path ~wasm))
  |> Sys.command |> of_exit ~wasm

(** The refusal text for a value that is not a literal (SD-D9). *)
let not_a_literal : string = "the kernel value is not a literal"

(** The oracle:  reduce the exported global to a literal.  A literal in
    the i31 range is the answer, a larger one is the trap the module
    raises, and everything else is a refusal. *)
let kernel_outcome (globals : Kanon_kernel.Global.t) ~(export : string) :
    outcome =
  let refuse (e : Kanon_kernel.Error.t) : outcome =
    Invalid (Kanon_kernel.Error.to_string e)
  in
  Kanon_kernel.Eval.eval globals [] (Kanon_kernel.Term.Global export)
  |> Result.fold ~error:refuse ~ok:(fun (v : Kanon_kernel.Value.t) ->
         Kanon_kernel.Eval.whnf globals v
         |> Result.fold ~error:refuse ~ok:(fun (w : Kanon_kernel.Value.t) ->
                Kanon_kernel.Value.as_lit w
                |> Option.fold ~none:(Invalid not_a_literal)
                     ~some:(fun (lit : Kanon_kernel.Literal.t) ->
                       match lit with
                       | Kanon_kernel.Literal.LInt n ->
                           Kanon_kernel.Bignum.to_i31 n
                           |> Option.fold
                                ~none:(Trap
                                  (Kanon_kernel.Bignum.to_string n
                                   ^ " is outside the i31 range"))
                                ~some:(fun (small : int) -> Value small)
                       | Kanon_kernel.Literal.LString _ -> Invalid not_a_literal)))

(** One host on one module.  [globals] carries the declarations the file
    was checked in, which only the kernel host reads (SE-D13). *)
let run_module ~(root : string) ~(globals : Kanon_kernel.Global.t) (h : host)
    ~(wasm : string) ~(export : string) : outcome =
  match h with
  | Node -> spawn node_runner ~root ~wasm ~export
  | Wasmtime -> spawn wasmtime_runner ~root ~wasm ~export
  | Kernel -> kernel_outcome globals ~export
