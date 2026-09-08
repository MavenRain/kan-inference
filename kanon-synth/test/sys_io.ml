(** The one catch site of the whole repository (SA-D19, narrowed in fix
    round 1, moved here at Stage D by SD-D14).

    Two runners live under test/ from Stage D on:  main.exe, the kernel
    suite, and wasm.exe, the emission suite.  Both read files and both
    list a directory, and the OCaml 5.2 standard library offers no total
    form of either call:  each reports its failure as [Sys_error].  The
    brief orders a runner to turn a file error into a FAIL line rather
    than to abort, so the conversion happens once, here, and every other
    line of kanon stays on the result track.

    [Sys_error] is the only caught constructor:  a failure of any other
    kind still leaves the process, because hiding it would make a broken
    suite look green.

    Search guard:  this is the only catch site in lib/, surface/, bin/,
    wasm/ and test/, which gate SD-G11 of the brief reads. *)
let attempt_sys (thunk : unit -> 'a) : ('a, string) result =
  try Ok (thunk ()) with Sys_error m -> Error m

(** The whole text of a file, or the reason it could not be read. *)
let read_file (path : string) : (string, string) result =
  attempt_sys (fun () -> In_channel.with_open_bin path In_channel.input_all)

(** The ".kan" files of a directory, sorted, without the extension. *)
let kan_names (dir : string) : (string list, string) result =
  attempt_sys (fun () -> Sys.readdir dir)
  |> Result.map (fun (entries : string array) ->
         Array.to_list entries
         |> List.filter (fun (n : string) -> Filename.check_suffix n ".kan")
         |> List.map Filename.remove_extension
         |> List.sort String.compare)
