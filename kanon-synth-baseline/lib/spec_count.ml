(** The R0 counts (R-Q2), printed by [kanon spec-count] and pinned in the
    "## R0 counts" block of SPEC.md.  dev/r0-count.sh diffs the two, so a
    count that grows past the spec fails the R0-COUNT gate leg.

    Every printed number is [List.length] of the list printed after it.  A
    literal integer in a printed count is a finding.  The shape lists come
    from [Shape] and the former and schema lists from [Term], so a sixth
    shape or a third former moves its own count with no edit here.

    Stage B: every list below is derived.  A shape is admitted when
    [Rules.rules] gives it a pack, and an eta row exists when the pack
    says so, so a pack that gains or loses a row moves its own count with
    no edit here.  The row names are built by concatenation from
    [Term.formers] and the names [Rules.admitted] reports, both because
    the names are then derived and because a shape name written out in
    this file would fail the R0-AUDIT gate leg. *)

let rules_declared : string list = Rules.named_declared
let rules_present : string list = Rules.named_present

(* total lookup;  plan section 11 bans the partial indexing combinators *)
let rec at (n : int) (xs : string list) : string option =
  match xs with
  | [] -> None
  | x :: rest -> if Int.equal n 0 then Some x else at (n - 1) rest

let pick (n : int) (xs : string list) : string = at n xs |> Option.value ~default:"?"
let lan : string = pick 0 Term.formers
let ran : string = pick 1 Term.formers
let admitted : string list = Rules.admitted

(** The derived eta table, plan section 5: a row exists where the shape has
    a unique introduction address and the structural expansion ends.  The
    two lists partition the four former and shape pairs of the admitted
    shapes, right former first within each shape. *)
let eta_of (keep : bool) : string list =
  List.concat_map
    (fun ((n : string), (e : Rules.eta_row)) ->
      List.filter_map
        (fun ((former : string), (has : bool)) ->
          if Bool.equal has keep then Some (former ^ "-" ^ n) else None)
        [ (ran, e.Rules.eta_ran); (lan, e.Rules.eta_lan) ])
    Rules.eta_table

let eta_rows : string list = eta_of true
let no_eta : string list = eta_of false

let row (label : string) (items : string list) : string =
  Printf.sprintf "%s %d: %s\n" label (List.length items) (String.concat " " items)

let print () : string =
  String.concat ""
    [
      row "formers" Term.formers;
      row "schema constructors" Term.schema;
      row "shapes declared" Shape.declared;
      row "shapes admitted" admitted;
      row "named rules declared" rules_declared;
      row "named rules present" rules_present;
      row "eta rows" eta_rows;
      row "no eta" no_eta;
    ]
