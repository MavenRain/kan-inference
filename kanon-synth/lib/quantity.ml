(* carried from tot 8cf0b8b lib/quantity.ml, delta: One and its algebra, plus pure path usage intervals (Stage K SK-D7). *)
(** Usage marks for the 0/1/omega fragment of QTT. [Zero] binders exist
    only at check time (types, proofs) and erase before evaluation.
    [One] is the linear mark: it requires exactly one use on each
    reachable runtime path. [Many] binders are unrestricted runtime data. *)

type t =
  | Zero
  | One
  | Many

(** [Zero] absorbs, [One] is the unit and [Many] is the result of every
    other pair. *)
let mul (a : t) (b : t) : t =
  match (a, b) with
  | Zero, Zero -> Zero
  | Zero, One -> Zero
  | Zero, Many -> Zero
  | One, Zero -> Zero
  | Many, Zero -> Zero
  | One, One -> One
  | One, Many -> Many
  | Many, One -> Many
  | Many, Many -> Many

let equal (a : t) (b : t) : bool =
  match (a, b) with
  | Zero, Zero -> true
  | One, One -> true
  | Many, Many -> true
  | Zero, One -> false
  | Zero, Many -> false
  | One, Zero -> false
  | One, Many -> false
  | Many, Zero -> false
  | Many, One -> false

let to_string (q : t) : string =
  match q with
  | Zero -> "0"
  | One -> "1"
  | Many -> "w"

(** The mark that one entry of an expression carries at mode [q].  A
    body runs one time for each entry, so every mode above [Zero] gives
    [One].  The mode says only whether checking is erased. *)
let runtime (q : t) : t = if equal q Zero then Zero else One

(** The count of two reads on one path.  [Zero] is the unit and two
    nonzero marks give [Many]. *)
let add (a : t) (b : t) : t =
  if equal a Zero then b else if equal b Zero then a else Many

(** The position of a mark in the order [Zero], [One], [Many]. *)
let rank (q : t) : int =
  match q with
  | Zero -> 0
  | One -> 1
  | Many -> 2

(** The lower of two marks in that order. *)
let minimum (a : t) (b : t) : t = if rank a <= rank b then a else b

(** The higher of two marks in that order. *)
let maximum (a : t) (b : t) : t = if rank a >= rank b then a else b

(** The counts of the binders, keyed by the level of each binder. *)
module Uses = Map.Make (Int)

(** The lowest and the highest count of one binder, in that order. *)
type interval = t * t

(** The usage of an expression.  [paths] holds the counts over the
    runtime paths that return, and it is [None] when no path returns.
    [reads] holds the counts over every path, which the paths that
    cannot return also fill. *)
type usage = { paths : interval Uses.t option; reads : interval Uses.t }

(** An expression that reads no binder and returns. *)
let empty : usage = { paths = Some Uses.empty; reads = Uses.empty }

(** An expression that cannot return, such as an empty elimination. *)
let unreachable : usage = { paths = None; reads = Uses.empty }

(** The counts of one level.  A level that is absent reads zero times. *)
let interval (level : int) (uses : interval Uses.t) : interval =
  Option.value (Uses.find_opt level uses) ~default:(Zero, Zero)

(** One read of [level] at mark [q], on the one path of that read. *)
let occurrence (level : int) (q : t) : usage =
  let reads = Uses.singleton level (q, q) in { paths = Some reads; reads }

(** Two count maps joined level by level.  [f] joins the lowest counts
    and [g] joins the highest counts.  A level that one map does not
    hold counts zero times in that map. *)
let combine (f : t -> t -> t) (g : t -> t -> t)
    (a : interval Uses.t) (b : interval Uses.t) : interval Uses.t =
  Uses.merge (fun _level x y ->
    let lo, hi = Option.value x ~default:(Zero, Zero) in
    let lo', hi' = Option.value y ~default:(Zero, Zero) in
    Some (f lo lo', g hi hi')) a b
(** Two expressions that both run, one after the other.  The counts
    add.  A first part that cannot return leaves no returning path. *)
let sequence (a : usage) (b : usage) : usage =
  { paths = Option.bind a.paths (fun x -> Option.map (combine add add x) b.paths);
    reads = combine add add a.reads b.reads }

(** Two expressions of which exactly one runs.  The result keeps the
    lower of the lowest counts and the higher of the highest counts.  A
    branch that cannot return supplies no path of its own. *)
let alternative (a : usage) (b : usage) : usage =
  let join (x : interval Uses.t) : interval Uses.t option =
    Option.fold ~none:(Some x)
      ~some:(fun (y : interval Uses.t) -> Some (combine minimum maximum x y)) b.paths in
  { paths = Option.fold ~none:b.paths ~some:join a.paths;
    reads = combine maximum maximum a.reads b.reads }

(** Every count multiplied by an interval, for an expression that runs
    between [lo] and [hi] times. *)
let scale_range ((lo, hi) : interval) (uses : usage) : usage =
  let scale_map = Uses.map (fun (a, b) -> mul lo a, mul hi b) in
  { paths = Option.map scale_map uses.paths; reads = scale_map uses.reads }

(** Every count multiplied by one mark.  An erased expression reads no
    binder at runtime. *)
let scale (q : t) (uses : usage) : usage =
  if equal q Zero then empty else scale_range (q, q) uses
(** The counts that discharge [level].  An expression that cannot
    return owes no read, so its lowest count is [One].  Its highest
    count still comes from the reads:  a path that cannot return is
    still a path that runs, and two reads on it duplicate the binder. *)
let get (level : int) (uses : usage) : interval =
  let _lo, hi = interval level uses.reads in
  Option.fold ~none:(One, maximum One hi) ~some:(interval level) uses.paths

(** The usage without [level], after the binder of that level closes. *)
let remove (level : int) (uses : usage) : usage =
  { paths = Option.map (Uses.remove level) uses.paths; reads = Uses.remove level uses.reads }

(** True when [level] is read one time on every runtime path. *)
let exactly_once (level : int) (uses : usage) : bool =
  let lo, hi = get level uses in equal lo One && equal hi One

(** True when [level] is read at least one time on some runtime path. *)
let used (level : int) (uses : usage) : bool =
  let _lo, hi = interval level uses.reads in not (equal hi Zero)

(** True when [level] is read at most one time on every runtime path. *)
let at_most_once (level : int) (uses : usage) : bool =
  let _lo, hi = get level uses in not (equal hi Many)

(** Constructing a closure returns even when invoking it cannot return.
    Keep dependencies from nonreturning paths so capture allocation cannot
    conceal an outer runtime read or duplication. *)
let captures (uses : usage) : usage =
  let paths = Option.fold ~none:uses.reads
    ~some:(fun paths -> combine (fun lo _seen -> lo) maximum paths uses.reads) uses.paths in
  { paths = Some paths; reads = uses.reads }
