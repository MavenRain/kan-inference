# kanon M0 specification

Date: 2026-09-05.  Status: M0 Stage A.  This file pins the closed grammar
and the R0 counts.  The gate legs R0-COUNT and R0-AUDIT read it.

## 1 The claim

kanon has two type formers, Lan and Ran.  Every type comes from one of the
two, applied to a shape and a diagram.  There are four schema
constructors: In and Elim for Lan, Sec and Out for Ran.  There is one
dispatch point, lib/rules.ml, which maps a shape to its rule pack.  No
other module in the kernel reads a shape name.

Every surface form in section 8 is sugar for one kernel constructor.  No
surface form is a former.

## 2 The closed grammar

The shape sum, the term sum and the erased form are declared whole at
Stage A (D-M0-2).  A constructor past M0 is refused by the module named
in its row, with its milestone name in the message.  A later milestone is
then a loud edit to an exhaustive match, not a new constructor.

### 2.1 Shapes, lib/shape.ml

| constructor | milestone | refused by |
| --- | --- | --- |
| `SPi of Quantity.t * string * 'a` | M0 | admitted |
| `SColl of int` | M0 | admitted |
| `SPar of 'a * 'a` | M2 | rules.ml |
| `SMu of string * 'a list` | M1 | admitted |
| `SNu of string * 'a list` | M2 | rules.ml |

The type parameter is the kernel term.  lib/term.ml therefore spells no
shape name (SA-D5).

Strict positivity, M1 Stage G, lib/positivity.ml.  A constructor field
admits the family it declares only strictly positively.  An occurrence
to the right of an arrow is admitted.  An occurrence to the left of an
arrow, an occurrence in an argument of a former, and an occurrence under
any other former, are refused with the word `a family that is not
strictly positive arrives at M2`.  A nested inductive is therefore M2
and is never reduced to a positive form (D-M1-2, R-Q5).  The check runs
once, when the constructors are installed, and formation reads the
stored verdict (A4).

The fibered elimination, M1 Stage H, lib/rules.ml.  An `Elim` at a mu
shape takes a motive, and an `Elim` with `e_motive` of `None` is refused
with the word `an elimination at a mu shape needs a motive`:  the branch
types of an indexed family are not recoverable from the type of the
scrutinee alone (A7).  The `m_ind` of the motive names a family, and
that name is equal to the family of the scrutinee, so a motive built for
a sibling family is refused.  The `m_idx` of the motive binds one name
per index of that family, and the scrutinee stands at that many indices.
A branch is keyed by the constructor address `ACtor c`, and it binds one
binder per field of that constructor at the mark the field carries.  The
branch list is read in the declaration order of the family:  a
constructor with no branch is refused, a constructor with two branches
is refused, and a branch at a name the family does not declare is
refused.  The body of a branch is checked at `m_body`, read at that
constructor's result index expressions and at that constructor's own
introduction.  An `Elim` at `In (SMu .., ACtor c, args)` reduces to the
branch at `c` with the arguments substituted.

### 2.2 Terms, lib/term.ml

Thirteen constructors.  Two of them form types.

| constructor | milestone | refused by |
| --- | --- | --- |
| `Var of int` | M0 | admitted |
| `Univ of Level.t`.  Prop is `Univ zero` and `Type n` is `Univ (n + 1)` (SB-D2) | M0 | admitted |
| `Lan of t Shape.t * t` | M0 | rules.ml, per shape |
| `Ran of t Shape.t * t` | M0 | rules.ml, per shape |
| `In of t Shape.t * addr * t list` | M0 | rules.ml, per shape |
| `Elim of elim` | M0 | rules.ml, per shape |
| `Sec of t Shape.t * leg list` | M0 | rules.ml, per shape |
| `Out of t Shape.t * addr * t` | M0 | rules.ml, per shape |
| `Let of string * t * t * t` | M0 | admitted |
| `Ann of t * t` | M0 | admitted |
| `Global of string` | M0 | admitted |
| `Lit of Literal.t` | M0 | admitted |
| `Auto` | M2 | check.ml, "instances arrive at M2" |

Addresses.  `APt` is the point address and carries the argument.  `ALeg`
is the leg address.  `ACtor` is the constructor address of the two
recursive shapes, so it arrives at M1 and M2.

### 2.3 The erased form, lib/eterm.ml

| constructor | milestone | refused by |
| --- | --- | --- |
| `KVar KLit KGlobal KErased KLet` | M0 | admitted |
| `KClos KApp KTail` | M0 | admitted |
| `KStruct KProj KTag KCase` | M0 | admitted |
| `KDelay KForce` | M2 | emit.ml |
| `RI31 RStruct RUnion RFunc` | M0 | admitted |
| `RThunk` | M2 | emit.ml |
| `KFun KRec` | M0 | admitted |

`tid` and `fid` are symbolic names and never integers.  lib/link.ml
resolves them to indices in one pass, so the emitter never computes an
index.

lib/erase.ml maps each kernel form to one erased form.  The table below
has one row for each row of the erasure section of the plan.  The third
column gives the name the row writes, either a `tid` or a `fid`.

| kernel form | erased form | name |
| --- | --- | --- |
| `Var` | `KVar i` for a runtime binder, `KErased` for a dropped binder | none |
| `Univ`, `Lan`, `Ran` | `KErased` | none |
| `Sec` at `Ran SPi` | the lambda chain lifts to one `KFun` and the occurrence is `KClos (fid, arity, captures)` | `fid` is `NAME$N` |
| `Out` at `APt` | `KApp (head, args)`, `KTail (head, args)` in a tail position, or the head alone when no argument is runtime and source parameters remain | none |
| `In` at `Lan SPi` | `KStruct (tid, the runtime fields)`, `KErased` when no field is runtime | `tid` is `pair<R,R>` |
| `Elim` at `Lan SPi` | one `KLet` of the scrutinee, then one `KLet` over a `KProj` for each runtime binder | `tid` is `pair<R,R>` |
| `In` at `Lan (SColl n)` | `KTag (tid, k, the runtime payload)` | `tid` is `sum<R\|R>` |
| `Elim` at `Lan (SColl n)` | `KCase (tid, scrutinee, one branch for each leg in leg order)` | the checked scrutinee `tid` is `sum<R\|R>`, or `any` for an empty sum |
| `Sec` at `Ran (SColl n)` | `KStruct (tid, the runtime legs)` | `tid` is `tuple<R,R>` |
| `Out` at `ALeg k` | `KProj (tid, k renumbered over the runtime legs, the term)` | `tid` is `tuple<R,R>` |
| `In` at `Lan (SMu ..)` | `KTag (tid, the constructor index in declaration order, the runtime fields)`, and a tag with no payload for a constructor that takes no runtime field | `tid` is `mu<NAME>`, and an index argument never enters it, because every index binder carries the mark 0, so two constructors that differ only in indices give one tid and one tag |
| `Elim` at `Lan (SMu ..)` | `KCase (tid, scrutinee, one branch for each constructor in declaration order)`, and a branch body that is the recursive call itself is `KTail` | the checked scrutinee `tid` is `mu<NAME>`, and the rec group of the declaration also names the leg struct `leg<mu<NAME>,K,R,R>` of each constructor |
| `Let` | `KLet (x, value, body)` for a runtime value, and the binder is dropped for a value that is not | none |
| `Ann` | the term under it, erased | none |
| `Global` | `KGlobal name` | none |
| `Lit` | `KLit` | none |
| `Auto`, `Sec` and `Out` at `SMu`, every form at `SPar` and at `SNu` | `Error (Not_yet ..)` with the milestone word | none |

A function type takes the repr `func fn<n>`, where n counts the runtime
points of the whole chain.  `Nat` takes the `nat` union repr.  A type that the table
does not name takes the tid `any`.

Constructor layouts are computed with the family parameters and earlier
fields bound as variables.  Each nominal family therefore has one layout
across parameter instantiations as well as indices.  A field that always
erases has no slot.  A generic slot instantiated at an erased type holds
`KErased`, preserving the positions of later fields and branch binders.

Function definitions and lifted functions take the parameters of their
whole type chain.  When the body supplies fewer lambdas, erasure adds
the remaining parameters and a tail application of the body.  Thus a
function alias and an explicit lambda have the same calling convention.
An application with only erased arguments preserves a function result,
including a function whose remaining binders all erase.  A fully applied
nullary function still emits a call with an empty argument list.

Erasure emits the original runtime syntax, retaining lets and primitive
calls.  Its checking environment retains let definitions for dependent
types, and a pair fibre receives the codomain instantiated at its point.
Each elimination branch receives the motive instantiated at that branch's
constructor.  These semantic values resolve types; they do not replace
the emitted runtime syntax.  Structural layouts still open dependent
codomains at fresh variables so a type has one layout across its values.

`kanon check --erased FILE` prints the erased program.  A `KFun` prints
as `fun FID (REPR, .., REPR) : REPR := KTM`, and a `KRec` prints as `rec
[TID; ..]`, one declaration to a line.  A repr prints as `i31`, `struct
TID`, `union TID`, `func TID` or `thunk TID`.  A ktm prints in prefix
form with its constructor name, then its scalar fields, then a subterm in
parentheses and a list in square brackets with semicolons.  A declaration
that carries nothing at runtime prints `erased NAME`.  A postulate prints
`axiom NAME : REPR`.  A name prints bare, without quotes.

An erased field leaves the struct, the tag and the tid, and a `KProj`
index counts the runtime fields alone.  A struct with no runtime field is
`KErased`.  A `KVar` counts runtime binders alone.  The erasure
environment maps each kernel binder to a runtime index or to erased, and
a use of an erased binder is `KErased`.

## R0 counts

`kanon spec-count` prints this block.  dev/r0-count.sh diffs the two.  A
count that grows fails the R0-COUNT gate leg.

```
formers 2: Lan Ran
schema constructors 4: In Elim Sec Out
shapes declared 5: SPi SColl SPar SMu SNu
shapes admitted 3: SPi SColl SMu
named rules declared 3: proof-irrelevance subsingleton-large-elimination literal-fast-path
named rules present 3: proof-irrelevance subsingleton-large-elimination literal-fast-path
eta rows 3: Ran-SPi Lan-SPi Ran-SColl
no eta 3: Lan-SColl Ran-SMu Lan-SMu
```

Every number in the block is the length of the list printed after it.
lib/spec_count.ml reads the shape lists from Shape and the former and
schema lists from Term.

## 4 The eta table

The criterion is one test, from plan section 5: a shape gets an eta row
when it has a unique introduction address and its structural expansion
ends.  The table below is derived from that test, not declared.

| row | former and shape | expansion | present |
| --- | --- | --- | --- |
| Ran-SPi | Ran at SPi | `f` to `Sec [x => Out (APt x) f]` | yes |
| Lan-SPi | Lan at SPi | `p` to `In (APt p.1) [p.2]` | yes |
| Ran-SColl | Ran at SColl n | `t` to `Sec [Out (ALeg 0) t, .., Out (ALeg n-1) t]` | yes |
| Lan-SColl | Lan at SColl n | none | no |

Lan at SColl n has n introduction addresses, one per leg, so the
criterion fails and the row is absent.  Ran at SColl 0 holds, and it
gives Unit its eta.  conv.ml applies each row by expansion.

### 4.1 The rule pack, lib/rules.ml

`rules : 'a Shape.t -> (rule_pack, Error.t) result` is the one dispatch
point.  It gives a pack to the two admitted shapes.  It gives
`Error (Not_yet ..)` with the milestone word to the other three.  The
pack has these fields, as built.

| field | what it decides |
| --- | --- |
| `form_lan` | the level of `Lan s d`.  It reads the diagram and `expected : Level.t option` (SB-D6) |
| `form_ran` | the same for `Ran s d` |
| `intro_in` | checks `In` against an expected `Lan` |
| `elim_elim` | checks or infers `Elim`.  `expected : Value.t option` is the constant cocone of a motive free elimination |
| `intro_sec` | checks `Sec` against an expected `Ran` |
| `elim_out` | infers `Out` |
| `beta` | one reduction step at the shape.  The evaluator calls it |
| `eta` | the row of the eta table above, one flag per former |
| `diagram_arity` | how many binders the diagram opens.  Readback asks it, so no reader outside the pack knows (SB-D25) |
| `spine_ty` | one typed step along a neutral spine:  the type of the address argument and the type of the head after the step (SB-D25) |
| `expand_ran` | the eta expansion at the right former.  The SB-M1 site is on this field of the point pack |
| `expand_lan` | the eta expansion at the left former |
| `conv_diagram` | compares two diagrams at the shape |
| `ann_lvl_eq` | compares the carried universe of SB-D7.  Only the width zero collection reads it |
| `lan_lvl` | the level function of the left former |
| `ran_lvl` | the level function of the right former |

A rule reads the checker through an `ops` record, so rules.ml does not
depend on check.ml and no ref cell exists in lib/ (SB-D12).

## 5 The named rules ledger

These are the conversion rules that are not schema rules.  Three are
declared;  two are present at M0 and the third arrives at M1 Stage H.

| rule | status | where |
| --- | --- | --- |
| proof-irrelevance | present at M0 | conv.ml, step one: two terms at a type in `Univ zero` are equal |
| subsingleton-large-elimination | present | conv.ml, step one, through the `subsingleton` field of the rule pack.  The three-part criterion is tot's, at kan-lang-tot-pin/lib/check.ml:219 and :223 |
| literal-fast-path | present at M0 | conv.ml, step three: `Lit` compares by value and the five prims reduce on literal arguments |

The criterion, M1 Stage H, lib/rules.ml `mu_zero_eliminable`, ported
part for part from kan-lang-tot-pin/lib/check.ml:223.  Part one: the
family has no constructor, which is the empty family and gives ex falso
(pin check.ml:227), or it has exactly one constructor (pin
check.ml:228).  Part two: every argument binder of that constructor is
at the mark `Zero` (pin check.ml:231).  Part three: that constructor is
not self recursive (pin check.ml:232).  A family under declaration and a
kernel family both answer false (pin check.ml:225-226), and a family
with two constructors or more answers false (pin check.ml:233).  A self
recursive family therefore never gets a large elimination, and the words
"the Prop-valued recursive shape" name the milestone that adds the
recursive shape and are not a permission for a recursive family (A1).
An elimination out of a family at the universe `Prop` into a motive
above that universe is admitted only when the family passes all three
parts;  it is refused with the word `a large elimination out of a
proposition needs a subsingleton family`, which carries the name of the
family that failed.  A family above `Prop`, and a motive at `Prop`, are
both small and neither asks the criterion.

Conversion applies the pack's subsingleton shortcut only to families
at `Prop`.  A `Type` family with erased fields can retain distinct type
payloads, so passing the large elimination criterion does not make its
inhabitants definitionally equal.  Such inhabitants use the remaining
conversion rules.

The Stage K agreement obligation follows the approved ruling of
2026-09-06 (d).  Five axiom-free unary SMu fixtures check all operand pairs
from 0 through 32 for `natAdd`, `natSub`, `natMul`, `natEq` and `natLt`:
1089 typed conversion witnesses each, 5445 total.  Each unary definition
and its observer avoid the primitive being tested.  A separate Python
integer oracle supplies 400 full-range cases per primitive, 2000 total,
including i31, host-integer, multi-limb and 100-digit boundaries.  The
kernel, Node and Wasmtime must agree with that oracle.  Both sets are
required finite evidence; they do not constitute a general agreement
theorem or execution of billion-constructor unary values.  The revised
finite obligation is discharged by Stage K SK-G5: all 7445 cases pass,
with the five unary sources in test/agreement and their parser and golden
checks retained by the dedicated gate.

Stage K distinguishes runtime mode from multiplicity.  `One` requires
exactly one runtime use on every reachable path.  Sequence adds uses,
declared argument quantities scale them, and case branches are
alternatives.  Types, annotations and Zero arguments contribute no
runtime uses.  Checked kernel entry points enforce the rule, including
function captures, constructor fields and let aliases (replacing SB-D3).

## 6 The framework axiom

Level rules are functions per shape (R-Q6).  `ran_lvl` at SPi is
`imax l l'`.  The equation

    imax l zero = zero

is a framework axiom of kanon.  It gives Prop its impredicativity.  M0
uses closed levels only.  Level variables arrive at M2.

As built, in lib/rules.ml under the comment `(* SB-M3 site *)`:

    let imax l l' = if Level.equal l' Level.zero then Level.zero
                    else Level.max l l'

`lan_lvl` at SPi is `Level.max`.  Both level functions at SColl n are the
maximum of the leg levels.  At n = 0 there is no leg, so the level comes
from the annotation and defaults to `Univ zero` (D-M0-6).

## 7 The sugar table

Every surface form maps to one kernel constructor.  Read the right-hand
column to confirm that no surface form is a former.

| surface form | kernel form | note |
| --- | --- | --- |
| `fun (q x : A) => b` | `Sec (SPi (q, x, A)) [x => b]` | sugar, not former |
| `(q x : A) -> B` | `Ran (SPi (q, x, A)) B` | sugar, not former |
| `A -> B` | `Ran (SPi (Many, "_", A)) B` | sugar, not former |
| `(q x : A) * B` | `Lan (SPi (q, x, A)) B` | sugar, not former |
| `A * B` | `Lan (SPi (Many, "_", A)) B` | sugar, not former |
| `f a` | `Out (SPi ..) (APt (q, a)) f` | sugar, not former.  SA-D1 |
| `(a, b)` | `In (SPi ..) (APt (q, a)) [b]` | sugar, not former |
| `p.1` | `Elim` at `Lan (SPi ..)`, leg `ALeg 0`, first branch binder, with the projection motive | sugar, not former.  D-M0-3 |
| `p.2` | `Elim` at `Lan (SPi ..)`, leg `ALeg 0`, second branch binder, with the projection motive | sugar, not former.  D-M0-3 |
| `inj k of n t` | `In (SColl n) (ALeg k) [t]` | sugar, not former |
| `case t as x return M with \| k xs => b` | `Elim` at `Lan (SColl n)` | sugar, not former |
| `match t as x in F i1 .. im return M with \| c y1 .. yn => b` | `Elim` at `Lan (SMu (F, ..))`, constructor keys `ACtor c` | sugar, not former.  SL-D3; Stage H constructor `case` remains accepted |
| `tuple (t1, .., tn)` | `Sec (SColl n) [.. => t1; ..]` | sugar, not former |
| `sum (A1, .., An)` | `Lan (SColl n) (Sec (SColl n) [.. => A1; ..])` | sugar, not former.  SB-D1 |
| `prod (A1, .., An)` | `Ran (SColl n) (Sec (SColl n) [.. => A1; ..])` | sugar, not former.  SB-D1 |
| `t.k` | `Out (SColl n) (ALeg k) t` | sugar, not former |
| `()` | `Sec (SColl 0) []` | sugar, not former |
| `absurd t` | `Elim` at `Lan (SColl 0)` with no branches | sugar, not former |
| `Prop` | `Univ zero` | sugar, not former |
| `Type n` | `Univ (n + 1)` | sugar, not former.  SB-D2 |
| `let x : A := d in b` | `Let (x, A, d, b)` | sugar, not former |
| `(t : A)` | `Ann (t, A)` | sugar, not former |
| `auto` | `Auto` | sugar, not former.  SA-D3 |
| `mu F params : indices -> Type n := ...` | a checked family record; references elaborate to `Lan (SMu (F, indices))` | declaration sugar.  SL-D1; the Stage G `with` spelling remains accepted |
| constructor `\| c binders : F args` | the existing constructor telescope and `In (SMu ..) (ACtor c)` introductions | binder sugar folds to arrows, preserving names and quantities.  SL-D1 |
| `mutual mu ... mu ... end` | one mutually checked family group | two or more members.  SL-D2; the Stage G `and` spelling remains accepted |
| `def rec f : A := body` and recursive `and` groups | a `Totality.guard_group` certificate admits `Order.translate`; the translated `Elim` body is checked and installed as `Global.Def` | sugar, not former.  SI-D9, SL-D9; no new term constructor |
| `nu` | none.  Reserved;  the parser refuses it with "nu arrives at M2" | SA-D3 |

SB-D1.  `sum` and `prod` are the two collection type words.  Both are
sugar rows and neither is a former:  the items are the legs of one
diagram, the diagram is a section at the collection shape, and the word
picks the left former or the right former over it.  The width zero forms
`sum ()` and `prod ()` are the empty and the unit type;  each takes its
universe from an annotation and sits at `Univ zero` without one (D-M0-6).

SB-D3, replaced at Stage K.  The binder mark `1` reads as `Quantity.One`
and requires exactly one runtime use on every reachable path.  The
surface representation and printer preserve all three quantity marks.

SA-D1.  Application by juxtaposition is a surface production and a sugar
row.  Plan sections 4 and 8 leave it out, and `natAdd` cannot be applied
without it.  It binds tighter than the arrow and the star, and looser
than the postfix `.1`, `.2` and `.k`.  It is left associative.

## 8 The encoder subset

wasm/gc_encode.ml encodes this subset and nothing else.  The gate leg
ENCODER-SUBSET fails when an opcode outside the table is emitted, so
growth is visible in a diff of this table.

| group | members |
| --- | --- |
| numbers | LEB128 unsigned, LEB128 signed |
| sections used | type, function, export, element (declarative segments only), code |
| sections refused | table, memory, global, start, data |
| composite types | struct, array, func, in rec groups, final subtypes only |
| rec groups | a group of one composite is the bare composite, which keeps the M0 bytes; a group of two or more composites is `0x4E`, the member count, then one `0x4F` sub final entry with an empty supertype vector for each member, in declaration order (D-M1-5) |
| control | `block`, `loop`, `if`, `br`, `br_if`, `br_on_cast`, `return`, `unreachable` |
| calls | `call`, `return_call`, `call_ref`, `return_call_ref` |
| locals | `local.get`, `local.set`, `local.tee` |
| numeric | `i32.const`, `i32.add`, `i32.sub`, `i32.mul`, `i32.div_u`, `i32.eq`, `i32.ne`, `i32.lt_u`, `i32.gt_u` |
| references | `ref.i31`, `i31.get_s`, `i31.get_u`, `ref.cast`, `ref.func`, `ref.null`, `ref.is_null` |
| structs | `struct.new`, `struct.get` |
| arrays | `array.new`, `array.get`, `array.set`, `array.len` |

Stage K adds a mutable i32 array composite (`0x5E`, field mutability
`0x01`).  The array instruction encodings are `0xFB 0x06` plus type index
for `array.new`, `0xFB 0x0B` plus type index for `array.get`, `0xFB 0x0E`
plus type index for `array.set`, and `0xFB 0x0F` for `array.len`.
Distinct limbs require `array.set` because `array.new` repeats a single
initializer.  Stores populate fresh result arrays; shared operands are
never modified.  Struct fields remain immutable.

M0 emits WasmGC core modules only (R-Q4).  There is no linear memory, no
tag, and no import beyond the gate's export.

The text form of a module is the print of the binary, so it can hold
printer presentation words this table does not list.  The printer writes
`drop` around a value
that stays on the stack in front of an `unreachable`, which the case
dispatch of SD-D5 leaves there when no leg casts.  dev/encoder-subset.sh
reads that word as the printer's and not as an opcode of
wasm/gc_encode.ml (SD-D24).

Stage K printer accounting: Binaryen can print an inferred block result
as `(ref (exact $1))`.  `exact` qualifies the printed reference type;
it is a structural word in dev/encoder-subset.sh.  The byte encoder has
no exact-reference form: `Ref h` remains `0x64` followed by the existing
heap-type encoding, and a defined heap type remains its signed index.
This printer exemption adds no instruction or binary type encoding.

### 8.1 The emission table

wasm/emit.ml writes one wasm form for every row.  A shape that is not in
this table is a refusal, not a guess.

| shape | erased form | wasm form |
| --- | --- | --- |
| a call of a known function | `KTail (KGlobal f) [a; ..]` | `call` of the typed signature, and `return_call` in tail position |
| a primitive | `KApp (KGlobal natAdd) [a; b]` | dispatch on i31 or big Nat, exact arithmetic with promotion and normalization, then a Nat or Bool result |
| a closure | `KClos f n [c; ..]` | `struct.new` of the closure type with the arity, `ref.func` of the wrapper and the environment |
| a call of a closure | `KTail (KVar 0) [a; ..]` | `struct.get` of the environment and of the code, `ref.cast` to `fn<n>`, then `call_ref` or `return_call_ref` |
| an application of an unknown arity | `KApp (KVar 0) [a]` | `call` of the helper `apply<k>` |
| a partial application | the same, with a larger arity | `struct.new` of `pap<m,k>` and a closure of the wrapper `papw:m:k` |
| a let | `KLet x v b` | a typed local, `local.set`, then the body |
| a pair or a tuple | `KStruct t [f; ..]` | one `struct.new` of the type of the tid |
| a projection | `KProj t k x` | `ref.cast` to the type of the tid, then `struct.get` and a cast from eq to the field repr |
| a tag with no payload | `KTag t k []` | `ref.i31` of the tag |
| a tag with a payload | `KTag t k [p]` | `struct.new` of the leg type, the tag first |
| a case | `KCase t s [{..}]` | the retained tid supplies the leg types; one `block` per leg shape, `br_on_cast` to i31 and to each leg type, then an `i32.eq` chain on the tag |
| an erased argument | `KErased` | `ref.i31` of zero |
| a literal | `KLit n` | `i32.const` and `ref.i31` for small Nat; fresh limb array and immutable big Nat struct otherwise |
| the export | the definition the caller names | a function with no parameter that calls the definition, casts the answer to i31 and reads it with `i31.get_s` |

The closure (SD-D2).  A closure is a struct of three fields.  The first
field is the arity as an i32.  The second field is the code as a function
reference.  The third field is the environment as an eq reference.  A
closure with no capture holds a tagged zero in the third field.  Every
field is immutable.

Two conventions (SD-D3).  A function with a known name and a known arity
has a typed signature.  Its parameters and its answer keep their repr.
Every other call goes through the generic signature `fn<n>`, where the
environment, each argument and the answer are eq references.  A wrapper
joins the two conventions.  It reads the captures out of the
environment, it casts each capture and argument to its repr, and it tail
calls the typed code.  Registration, construction and the wrapper use
the capture prefix of the lifted function's signature as the environment
tid.  A value goes from the typed form to the generic form at no
cost, because each typed form is a subtype of eq.  A value comes back
with one `ref.cast`.

Generic application (SD-D4).  The helper `apply<k>` applies k arguments
to a closure whose arity the caller does not know.  It reads the arity
out of the closure and compares it with k.  An equal arity gives a
`return_call_ref` of the code.  A smaller arity calls the code and gives
the arguments that are left to `apply<k-m>`.  A larger arity builds a
partial application:  a struct `pap<m,k>` holds the closure and the k
arguments, and a new closure of arity m-k names the wrapper `papw:m:k`.
That wrapper reads the saved arguments, adds the new ones and calls the
target.  The set of helpers is closed:  each helper adds the helpers it
needs, until nothing is new.

Sums (SD-D5).  A leg with no payload is its tag in an i31.  A leg with a
payload is a struct.  The first field of that struct is the tag in an
i31 and the second field is the payload as an eq reference.  Payload
legs have equivalent runtime struct types, and the tag tells them apart.
A payload read casts the eq reference to its checked repr.  A case reads
the tag first.  It uses `br_on_cast` to i31 and one `br_on_cast` for each
leg type.  It then compares the tag with the tag of each branch.

The value types (SD-D6, corrected after review).  A pair and a tuple are
one struct each, with one immutable eq reference field for each runtime
component.  Environments use the same storage convention.  Instantiating
an erased type parameter changes the field's checked repr but leaves its
storage type unchanged; nested aggregates retain this property.  The
emitter casts each field read from eq to its checked repr.  The symbolic
tids stay distinct, but same-width aggregates have equivalent final
Wasm struct types.  link.ml maps each repr to a value type for locals and
function signatures.  The
repr `i31` gives a reference to i31.  A pair or a tuple gives a
reference to its struct type.  A function gives a reference to the
closure type.  A sum and the tid `any` give an eq reference.

A case carries its checked scrutinee tid through erasure.  The emitter
uses that tid for dispatch and payload binders even when a generic call
returns the scrutinee as `any`.  An empty case needs no leg type and emits
`unreachable`.

Naturals (Stage K replaces SD-D7 and SD-D23).  Check-time integers use
the total Bignum boundary over Zarith 1.14.  Decimal Nat literals have no
machine-integer digit ceiling.  Negative forged literals are refused as
Nat inputs.  Grammar quantities, universes and leg indices retain checked
bounded conversions.

Runtime Nat is an eq-reference union.  Values from 0 through 1073741823
use i31; larger values use an immutable struct containing sign 1 and an
i32 limb array.  Limbs are little-endian base 32768.  Arithmetic removes
leading zero limbs and normalizes zero and other small answers to i31.
Fresh output arrays preserve aliased operands.  A schoolbook product
accumulates at most 1073741823 in each i32 intermediate.  Helpers use
tail calls, and no host arithmetic import or linear memory is required.
Small operations promote before overflow.  All five primitives accept
mixed representations.  `natSub` truncates at zero; `natEq` and `natLt`
return the two-leg Bool sum with true at leg 1 and false at leg 0.

The export (SD-D8).  The caller names one definition.  That definition
must be a `Nat` of arity zero.  The module exports a function with no
parameter and an i32 answer.  That function calls the definition and
casts the answer to i31 and reads it with `i31.get_s`.  Large internal
values remain exact and may produce a small exported observation.  Only
an out-of-i31 export traps, with driver exit 4 on every execution host.

## 9 The surface grammar

```
decl    ::= 'def' name ':' term ':=' term
          | 'axiom' name ':' term
          | 'def' 'rec' rec-member ('and' rec-member)*
          | mu-decl ('and' mu-member)*
          | 'mutual' mu-decl mu-decl+ 'end'
mu-decl ::= 'mu' mu-member
mu-member ::= name binder* ':' term (':=' | 'with') ctor*
ctor    ::= '|' name binder* ':' term
rec-member ::= name ':' term ':=' term
term    ::= 'fun' binder+ '=>' term
          | binder '->' term  |  term '->' term
          | binder '*' term   |  term '*' term
          | term term                              (* SA-D1 *)
          | '(' term ',' term ')'  |  term '.1'  |  term '.2'
          | 'inj' nat 'of' nat term
          | 'case' term ['as' name ['in' name name*] 'return' term] 'with'
              ('|' nat binder* '=>' term | '|' name field* '=>' term)*
          | 'match' term ['as' name ['in' name name*] 'return' term] 'with'
              ('|' name field* '=>' term)*
          | 'tuple' '(' (term (',' term)*)? ')'  |  term '.' nat
          | 'sum' '(' (term (',' term)*)? ')'       (* SB-D1 *)
          | 'prod' '(' (term (',' term)*)? ')'      (* SB-D1 *)
          | '()'  |  'absurd' term
          | 'Prop'  |  'Type' nat?  |  nat
          | 'natAdd' | 'natSub' | 'natMul' | 'natEq' | 'natLt'
          | 'let' name ':' term ':=' term 'in' term
          | 'auto'                                 (* SA-D3 *)
          | 'nu'                                  (* reserved, arrives at M2 *)
          | '(' term ':' term ')'  |  name  |  '(' term ')'
binder  ::= '(' ('0' | '1')? name ':' term ')'
field   ::= ('0' | '1')? name | binder             (* M1 Stages H and L *)
```

Precedence, loosest first: the arrow and the star, then application, then
the postfix projections `.1`, `.2` and `.k`.  The arrow and the star are
right associative.  Application is left associative.

The binder mark is one of three:  `0` is `Quantity.Zero`, `1` is
`Quantity.One` and an absent mark is `Quantity.Many` (SB-D3).  The
printer writes `0 `, `1 ` and the empty text back, so a marked binder
round trips.

`sum`, `prod`, `mu`, `mutual`, `match`, `end` and `nu` are reserved
words.  `mu` opens a declaration; its parameter binders precede the
colon, and its index telescope is the arrow chain after it.  Constructor
binders before the colon abbreviate the same arrow chain in the
constructor type.  `mutual` requires two or more `mu` declarations and
an explicit `end`.  The earlier `mu ... with` and `and` grammar remains
accepted.  The printer normalizes families to `:=` and groups of two or
more to `mutual ... end` (SL-D1, SL-D2, SL-D5).

`match` admits constructor keys and requires a family scrutinee, even
when its branch list is empty.  Numeric `case` remains the collection
eliminator, and the Stage H constructor `case` form remains compatible.
Both forms share the existing elaboration rules.  A constructor field
may be a quantity and a name or a typed binder; an explicit type must
agree with its constructor field type under all preceding fields.
Every branch binder retains its written quantity (SL-D3, SL-D4).

Match and case bodies extend to the right; parentheses delimit nested
eliminations before a following outer branch.  `end` closes a mutual
declaration group only.  The index clause of Stage H remains available
for indexed motives.  The parser accepts the optional-motive grammar,
and the existing kernel requirement for a fibered motive still applies.
`nu` retains the parser refusal "nu arrives at M2" in both declaration
and term positions; `auto` retains its M2 checker refusal (SL-D6).

## 10 Obligations at M0

M0 leaves these six obligations.  Each one names the milestone that
closes it.

| obligation | milestone | note |
| --- | --- | --- |
| linear counting for `One` | M1 | discharged by Stage K SK-G3: exact path usage, 27 direct kernel checks and 22 surface path cases, including duplication negatives |
| arbitrary precision Nat | M1 | discharged by Stage K SK-G4: Zarith 1.14, exact kernel and Wasm arithmetic, both runtime hosts and separate export-boundary checks |
| finite agreement of the literal fast path | M1 | discharged by Stage K SK-G5 under ruling 2026-09-06 (d): all 5445 unary witnesses and 2000 independent full-range cases described in section 5 pass |
| subsingleton large elimination | M1 | discharged by Stage H SH-G7: singleton and empty Prop families admit large elimination, non-subsingleton and self-recursive families are refused.  Section 5 records the criterion and its origin in tot |
| structural recursion certificate | M1 | the elaborator calls `Totality.guard` before it translates a recursive definition into `Elim`.  M0 holds the entry point and no caller.  discharged at M1 Stage I: surface/elab.ml:1004 calls `Totality.guard_group` and only a certificate reaches `Order.translate` at surface/elab.ml:1029 (SI-D9, SI-D13) |
| the `any` repr | M1 | discharged at Stage D: a runtime value of a variable type takes the tid `any`, which link.ml maps to eqref (SD-D6) |
