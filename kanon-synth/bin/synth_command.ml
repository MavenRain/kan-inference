(** Proposals remain text until the surface resolver and kernel accept them.
    The user-facing command enforces process deadlines. *)

let json_string (value : string) : string =
  let escaped =
    String.to_seq value
    |> Seq.map (fun (c : char) ->
           match () with
           | () when Char.equal c '"' -> "\\\""
           | () when Char.equal c '\\' -> "\\\\"
           | () when Char.code c < 32 -> Printf.sprintf "\\u%04x" (Char.code c)
           | () -> String.make 1 c)
    |> List.of_seq |> String.concat ""
  in
  "\"" ^ escaped ^ "\""

let usage () : unit =
  prerr_endline
    "usage: kanon synth FILE -o OUTPUT.kan [--provider EXECUTABLE | --replay RECEIPT]";
  exit 64

let read (path : string) : (string, Kanon_kernel.Error.t) result =
  if Sys.file_exists path && not (Sys.is_directory path) then
    Ok (In_channel.with_open_bin path In_channel.input_all)
  else Error (Kanon_kernel.Error.Carry ("cannot read " ^ path))

let fail (error : Kanon_kernel.Error.t) : unit =
  prerr_endline (Kanon_kernel.Error.to_string error);
  exit 1

let request_json (request : Kanon_surface.Synthesis.request) :
    (string, Kanon_kernel.Error.t) result =
  let fields =
    [ request.declaration; request.hint; request.expected_type; request.context ]
  in
  if List.for_all String.is_valid_utf_8 fields then
    Ok (Printf.sprintf
    "{\"protocol_version\":1,\"declaration\":%s,\"hint\":%s,\"expected_type\":%s,\"context\":%s,\"allowed_axioms\":[\"Nat\"]}"
    (json_string request.declaration) (json_string request.hint)
    (json_string request.expected_type) (json_string request.context))
  else Error (Kanon_kernel.Error.Cannot_infer
    "synthesis requests must contain valid UTF-8 text")

let request (args : string list) : unit =
  match args with
  | [ path ] ->
      Result.bind (read path) Kanon_surface.Synthesis.next
      |> Result.fold ~error:fail ~ok:(fun (next : Kanon_surface.Synthesis.request option) ->
             Option.fold ~none:(Ok "null") ~some:request_json next
             |> Result.fold ~error:fail ~ok:print_endline)
  | [] | _ :: _ -> usage ()

let apply (args : string list) : unit =
  match args with
  | [ path; "--candidate"; candidate; "-o"; output ] ->
      let resolved =
        Result.bind (read path) (fun (source : string) ->
            Result.bind (read candidate) (Kanon_surface.Synthesis.apply source))
      in
      resolved
      |> Result.fold ~error:fail ~ok:(fun (source : string) ->
             match () with
             | () when Sys.file_exists output ->
                 fail (Kanon_kernel.Error.Carry ("output already exists: " ^ output))
             | () when not (Sys.file_exists (Filename.dirname output)) ->
                 fail (Kanon_kernel.Error.Carry ("output directory is missing: " ^ output))
             | () ->
                 Out_channel.with_open_bin output (fun (channel : Out_channel.t) ->
                     Out_channel.output_string channel source))
  | [] | _ :: _ -> usage ()

let run (args : string list) : unit =
  let script = Filename.concat (Host.root ()) "dev/synth.py" in
  if Sys.file_exists script then
    let command =
      [ "python3"; script; "--compiler"; Sys.executable_name ] @ args
      |> List.map Filename.quote |> String.concat " "
    in
    exit (Sys.command command)
  else fail (Kanon_kernel.Error.Carry ("cannot locate " ^ script))
