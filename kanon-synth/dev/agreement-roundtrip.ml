let ( let* ) = Result.bind

let round_trip source =
  let* first =
    Kanon_surface.Parser.parse source
    |> Result.map_error Kanon_kernel.Error.message
  in
  let printed = Kanon_surface.Syntax.print first in
  let* second =
    Kanon_surface.Parser.parse printed
    |> Result.map_error Kanon_kernel.Error.message
  in
  if first = second then Ok ()
  else Error "the printed text parses to a different tree"

let () =
  In_channel.input_all stdin |> round_trip
  |> Result.fold
       ~ok:(fun () -> print_endline "ROUNDTRIP OK")
       ~error:(fun message ->
         prerr_endline ("ROUNDTRIP FAIL: " ^ message);
         exit 1)
