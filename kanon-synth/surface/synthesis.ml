(** A synthesis candidate is untrusted source data. This module never calls
    a model, adds a kernel constructor, or installs a candidate as an axiom. *)
open Kanon_kernel

let ( let* ) = Result.bind

type request = {
  declaration : string;
  hint : string;
  expected_type : string;
  context : string;
}

let unsupported : Error.t =
  Error.Cannot_infer
    "synth is supported only as the entire body of an explicitly typed nonrecursive def"

let rec each (check : 'a -> (unit, Error.t) result) (items : 'a list) :
    (unit, Error.t) result =
  match items with
  | [] -> Ok ()
  | item :: rest ->
      let* () = check item in
      each check rest

(** Every term constructor and every annotation is visited explicitly.
    Extending the syntax therefore makes the safety walk nonexhaustive until
    the new constructor has a policy. *)
let rec ordinary (term : Syntax.t) : (unit, Error.t) result =
  match term with
  | Syntax.SSynth _ -> Error unsupported
  | Syntax.SAuto ->
      Error (Error.Cannot_infer "unresolved auto is not allowed in synthesis sources or candidates")
  | Syntax.SVar _ | Syntax.SNat _ | Syntax.SProp | Syntax.SType _
  | Syntax.SPrim _ | Syntax.SUnit -> Ok ()
  | Syntax.SPair (left, right) | Syntax.SApp (left, right)
  | Syntax.SAnn (left, right) ->
      let* () = ordinary left in
      ordinary right
  | Syntax.STuple items | Syntax.SSum items | Syntax.SProd items -> each ordinary items
  | Syntax.SProj (value, _) | Syntax.SInj (_, _, value) | Syntax.SAbsurd value ->
      ordinary value
  | Syntax.SFun (binders, body) ->
      let* () = each ordinary_binder binders in
      ordinary body
  | Syntax.SArrow (binder, body) | Syntax.SStar (binder, body) ->
      let* () = ordinary_binder binder in
      ordinary body
  | Syntax.SLet (_, ty, value, body) ->
      let* () = ordinary ty in
      let* () = ordinary value in
      ordinary body
  | Syntax.SCase (scrutinee, motive, branches)
  | Syntax.SMatch (scrutinee, motive, branches) ->
      let* () = ordinary scrutinee in
      let* () =
        motive |> Option.fold ~none:(Ok ())
          ~some:(fun (m : Syntax.motive) -> ordinary m.Syntax.mo_body)
      in
      each ordinary_branch branches

and ordinary_binder (binder : Syntax.binder) : (unit, Error.t) result =
  ordinary binder.Syntax.b_ty

and ordinary_branch (branch : Syntax.branch) : (unit, Error.t) result =
  match branch with
  | Syntax.BrLeg (_, binders, body) ->
      let* () = each ordinary_binder binders in
      ordinary body
  | Syntax.BrCtor (_, fields, body) ->
      let* () = each ordinary_field fields in
      ordinary body

and ordinary_field (field : Syntax.field) : (unit, Error.t) result =
  field.Syntax.fd_ty |> Option.fold ~none:(Ok ()) ~some:ordinary

let ordinary_family (family : Syntax.fam) : (unit, Error.t) result =
  let* () = each ordinary_binder family.Syntax.fm_params in
  let* () = ordinary family.Syntax.fm_ty in
  each (fun (ctor : Syntax.fam_ctor) -> ordinary ctor.Syntax.fc_ty) family.Syntax.fm_ctors

let ordinary_recursive (member : Syntax.rec_def) : (unit, Error.t) result =
  let* () = ordinary member.Syntax.rd_ty in
  ordinary member.Syntax.rd_body

let validate_decl (decl : Syntax.decl) : (unit, Error.t) result =
  match decl with
  | Syntax.DAxiom (name, _) ->
      Error (Error.Cannot_infer ("synthesis disallows every source axiom: " ^ name))
  | Syntax.DMu families -> each ordinary_family families
  | Syntax.DRec members -> each ordinary_recursive members
  | Syntax.DDef (_, ty, Syntax.SSynth _) -> ordinary ty
  | Syntax.DDef (_, ty, body) ->
      let* () = ordinary ty in
      ordinary body

(** Every name a declaration installs. The namespace is flat, so a family
    group installs its member names and every constructor name, and a
    recursive group installs one name per member. *)
let bound_names (decl : Syntax.decl) : string list =
  match decl with
  | Syntax.DDef (name, _, _) | Syntax.DAxiom (name, _) -> [ name ]
  | Syntax.DMu families ->
      List.concat_map
        (fun (family : Syntax.fam) ->
          family.Syntax.fm_name
          :: List.map
               (fun (ctor : Syntax.fam_ctor) -> ctor.Syntax.fc_name)
               family.Syntax.fm_ctors)
        families
  | Syntax.DRec members ->
      List.map (fun (member : Syntax.rec_def) -> member.Syntax.rd_name) members

(** The environment installs by overwrite. A declaration that repeats a name
    already bound in the frozen prefix would therefore be checked against the
    old entry and then replace it, so the checked term is not the installed
    term. Synthesis refuses every such redefinition, including a redefinition
    of a built-in name. *)
let taken (globals : Global.t) (name : string) : bool =
  Option.is_some (Global.find name globals)
  || Option.is_some (Global.find_family name globals)
  || Global.StringMap.exists
       (fun (_declared : string) (family : Positivity.family) ->
         Option.is_some (Positivity.ctor_of name family))
       globals.Global.families

let fresh (globals : Global.t) (names : string list) : (unit, Error.t) result =
  each
    (fun (name : string) ->
      if taken globals name then
        Error
          (Error.Cannot_infer ("synthesis refuses a declaration that redefines " ^ name))
      else Ok ())
    names

(** The constructor of an entry, as text, so two entries compare without a
    wildcard match arm. *)
let kind (entry : Global.entry) : string =
  match entry with
  | Global.Def _ -> "def"
  | Global.Axiom _ -> "axiom"
  | Global.Prim _ -> "prim"

(** Defense in depth for the axiom scan below: every name of the initial
    environment must still carry the same constructor and the same closed
    type. A replaced built-in would let the axiom scan hold vacuously. *)
let builtins_intact (globals : Global.t) : (unit, Error.t) result =
  Global.StringMap.fold
    (fun (name : string) (expected : Global.entry) (acc : (unit, Error.t) result) ->
      let* () = acc in
      Global.find name globals
      |> Option.fold
           ~none:
             (Error (Error.Cannot_infer ("synthesis requires the built-in " ^ name)))
           ~some:(fun (entry : Global.entry) ->
             if
               String.equal (kind expected) (kind entry)
               && Global.entry_ty expected = Global.entry_ty entry
             then Ok ()
             else
               Error
                 (Error.Cannot_infer ("synthesis refuses a replaced built-in: " ^ name))))
    Global.initial.Global.entries (Ok ())

(** Inspect the entire immutable environment, so an indirect dependency
    cannot hide a postulate behind an ordinary definition. The built-in Nat
    postulate is permitted only with the exact type installed initially. *)
let assumptions (globals : Global.t) : (unit, Error.t) result =
  let* () = builtins_intact globals in
  Global.StringMap.fold
    (fun (name : string) (entry : Global.entry) (acc : (unit, Error.t) result) ->
      let* () = acc in
      match entry with
      | Global.Def _ | Global.Prim _ -> Ok ()
      | Global.Axiom axiom ->
          let permitted =
            String.equal name Prim.nat_name
            && (Global.find_axiom Prim.nat_name Global.initial
                |> Option.fold ~none:false ~some:(fun (initial : Global.axiom_entry) ->
                     axiom.Global.ax_ty = initial.Global.ax_ty))
          in
          if permitted then Ok ()
          else Error (Error.Cannot_infer ("unapproved axiom in synthesis context: " ^ name)))
    globals.Global.entries (Ok ())

type focus = {
  request : request;
  globals : Global.t;
  prefix : Syntax.decl list;
  goal : Syntax.t;
  suffix : Syntax.decl list;
}

let rec locate (globals : Global.t) (prefix_rev : Syntax.decl list)
    (remaining : Syntax.decl list) : (focus option, Error.t) result =
  match remaining with
  | [] ->
      let* () = assumptions globals in
      Ok None
  | Syntax.DDef (name, ty, Syntax.SSynth hint) :: suffix ->
      let* () = assumptions globals in
      let* () = fresh globals [ name ] in
      (* This temporary declaration checks only formation of the fixed goal.
         Its returned environment is discarded. Candidate checking below uses
         a real definition and the original prefix globals. *)
      let* _goal_formation = Elab.elab_program_in globals [ Syntax.DAxiom (name, ty) ] in
      let prefix = List.rev prefix_rev in
      let request =
        { declaration = name; hint; expected_type = Syntax.at 0 ty;
          context = Syntax.print prefix }
      in
      Ok (Some { request; globals; prefix; goal = ty; suffix })
  | ((Syntax.DDef (_, _, _) | Syntax.DAxiom (_, _) | Syntax.DMu _ | Syntax.DRec _) as decl)
    :: rest ->
      let* () = fresh globals (bound_names decl) in
      let* checked, _rows = Elab.elab_program_in globals [ decl ] in
      locate checked (decl :: prefix_rev) rest

let prepare (source : string) : (focus option, Error.t) result =
  let* declarations = Parser.parse source in
  let* () = each validate_decl declarations in
  locate Global.initial [] declarations

let next (source : string) : (request option, Error.t) result =
  prepare source |> Result.map (Option.map (fun (focus : focus) -> focus.request))

let apply (source : string) (candidate : string) : (string, Error.t) result =
  let* focus = prepare source in
  let* focus =
    focus |> Option.to_result ~none:(Error.Cannot_infer "source has no unresolved synth")
  in
  let* term = Parser.expression candidate in
  let* () = ordinary term in
  (* The same freshness rule as the check path, so the two cannot drift. *)
  let* () = fresh focus.globals [ focus.request.declaration ] in
  let definition = Syntax.DDef (focus.request.declaration, focus.goal, term) in
  let* checked, _rows = Elab.elab_program_in focus.globals [ definition ] in
  let* () = assumptions checked in
  Ok (Syntax.print (focus.prefix @ (definition :: focus.suffix)))
