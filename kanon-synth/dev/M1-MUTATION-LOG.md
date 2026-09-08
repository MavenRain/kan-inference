# kanon M1 mutation log

## Stage F

Four mutations, each on its own fresh copy of the package made with
`rsync -a --exclude .lake /Users/oobi/Documents/kanon-stage-f/meta/
SCRATCH/stageF/judge/jmN/`, then given a copy of meta/.lake/packages
with a second `rsync -a` so the copy builds with no remote.  Each copy
was built through the detached runner with
`/Users/oobi/.elan/bin/lake +leanprover/lean4:v4.33.0-rc1 --dir
SCRATCH/stageF/judge/jmN build`.  ROOT was never mutated:  `git -C ROOT
status --porcelain` lists the untracked meta/ directory and the two new
dev/M1 log files, and no other path, before and after.  The
judge reran all four at 2026-09-06 03:02.

### SF-M1 dropped hypothesis

- Site.  The copy's KanonMeta/BeckChevalley.lean:29, the right side of
  `bc_lan_spi`.
- Edit.  `Term.lan (Shape.SPi q x (subst sigma dom)) (subst (up sigma)
  A)` becomes `Term.lan (Shape.SPi q x (subst sigma dom)) (subst sigma
  A)`, so the lift under the one binder of the point diagram is gone.
- Killing line.  `error: KanonMeta/BeckChevalley.lean:29:70: unsolved
  goals`, then `error: build failed`, exit file `EXIT 1`.  The column
  names the mutated right side of `bc_lan_spi`.

### SF-M2 swapped side

- Site.  The copy's KanonMeta/BeckChevalley.lean:36, the right side of
  `bc_ran_spi`.
- Edit.  `Term.ran (Shape.SPi q x (subst sigma dom)) (subst (up sigma)
  A)` becomes `Term.ran (Shape.SPi q x dom) (subst (up sigma) A)`, so
  the shape payload is not carried through sigma, which is the error the
  design verdict names at :164-166.
- Killing line.  `error: KanonMeta/BeckChevalley.lean:36:61: unsolved
  goals`, then `error: build failed`, exit file `EXIT 1`.

### SF-M3 SColl n to SColl 0

- Site.  The copy's KanonMeta/BeckChevalley.lean:52, the right side of
  `bc_ran_scoll`.
- Edit.  `= Term.ran (Shape.SColl n) (subst sigma A)` becomes
  `= Term.ran (Shape.SColl 0) (subst sigma A)`, on the right side only.
- Killing line.  `error: KanonMeta/BeckChevalley.lean:52:52: unsolved
  goals`, then `error: build failed`, exit file `EXIT 1`.

### SF-M4 the SF-G2 control

- Site.  The copy's KanonMeta/BeckChevalley.lean:30, the proof body of
  `bc_lan_spi`.
- Edit.  `kan_rfl` becomes `sorry`.
- Killing line.  The sweep kills it, not the build, which is what the
  brief expects.  `rg -n -c "sorry" SCRATCH/stageF/judge/jm4` printed
  `SCRATCH/stageF/judge/jm4/KanonMeta/BeckChevalley.lean:1`, rg exit 0,
  so the SF-G2 sweep is not vacuous.  The build itself only warned,
  in these words, with the escape hatch name in backticks:
  warning: KanonMeta/BeckChevalley.lean:26:8: declaration uses `sorry`.
  The last build line is `Build completed successfully (40 jobs).` and
  the exit file holds `EXIT 0`.

### Stage F review mutations (2026-09-06)

Each mutation used a separate copy of the fixed package under
/private/tmp/kanon-stage-f-fixes, retaining cached dependencies.  Each
ran `/Users/oobi/.elan/bin/lake +leanprover/lean4:v4.33.0-rc1 --dir COPY
build`.  The unmutated package and its 16 regression checks built with
exit 0.  All four mutated builds exited 1 in the regression target.

- `binder-subst`: replace `subst (upN binders.length sigma) body` with
  `subst sigma body` in Subst.lean.  First killing line:
  `error: test/Regression.lean:21:43: unsolved goals`.
- `binder-ren`: replace `ren (upRenN binders.length rho) body` with
  `ren rho body`.  First killing line:
  `error: test/Regression.lean:25:43: unsolved goals`.
- `point-subst`: replace `Addr.apt q (subst sigma arg)` with
  `Addr.apt q arg`.  First killing line:
  `error: test/Regression.lean:75:51: unsolved goals`.
- `point-ren`: replace `Addr.apt q (ren rho arg)` with `Addr.apt q arg`.
  First killing line:
  `error: test/Regression.lean:79:51: unsolved goals`.

The four log and exit files use these names with `.log` and `.exit`
suffixes in the scratch directory.  No repository source was mutated.

## Stage G

Five mutations, each on its own fresh copy of the repository made with
`rsync -a --exclude _build --exclude .gatework`, built through the copy's
own dev/dunecho.sh, which printed `OK build: 0 errors, 0 warnings` and
exit 0 for all five (SG-D11).  ROOT was never mutated.  The judge reran
all five at 2026-09-06 04:23, on the copies judge-m1 to judge-m5 under
the session scratch directory.

### SG-M1 positivity

- Site.  The copy's lib/positivity.ml:129, the arrow domain of
  [positive], which asks [absent] for the left of an arrow (brief 3.2,
  D-M1-2).
- Edit.  `let* () = absent names dom in` becomes `let* () = Ok () in`, so
  an occurrence to the left of an arrow is admitted.
- Killing line.  `kanon.exe check test/neg/mu-nonpositive.kan` printed
  nothing and exit 0, where the sidecar promises the refusal, and the
  suite printed `NEG mu-nonpositive FAIL: the file checks and the
  negative expects it to fail`, `NEG-OK 13/14` and `SUITE-KERNEL FAIL`.
  The accepted line is the file itself, which declares a family whose
  constructor field puts the family to the left of an arrow.
  That line is test/neg/mu-nonpositive.kan:7, `| mk : (P -> P) -> P`.

### SG-M2 the counts

- Site.  The copy's SPEC.md:153 and :157, the two R0 rows the pack moves
  (brief 3.7, A3).
- Edit.  `shapes admitted 3: SPi SColl SMu` becomes `shapes admitted 2:
  SPi SColl` and `no eta 3: Lan-SColl Ran-SMu Lan-SMu` becomes `no eta 1:
  Lan-SColl`.  The pack stays in place.
- Killing line.  `zsh dev/r0-count.sh` printed the two differing rows and
  `R0-COUNT FAIL`, exit 1.  The rows are `4c4 < shapes admitted 2: SPi
  SColl > shapes admitted 3: SPi SColl SMu` and `8c8 < no eta 1:
  Lan-SColl > no eta 3: Lan-SColl Ran-SMu Lan-SMu`.

### SG-M3 the index rule of the introduction

- Site.  The copy's lib/rules.ml:1091, the last step of the mu
  introduction, which calls [mu_indices] (A14, M1-PLAN.md:79).
- Edit.  `mu_indices ops ctx n ct ixv env` becomes
  `let () = ignore (n, ct, ixv, env) in Ok ()`, so the constructor result
  indices are no longer unified with the indices of the expected type.
- Killing line.  `kanon.exe check test/neg/mu-index-mismatch.kan` printed
  nothing and exit 0, and the suite printed `NEG mu-index-mismatch FAIL:
  the file checks and the negative expects it to fail`, `NEG-OK 13/14`
  and `SUITE-KERNEL FAIL`.

### SG-M4 the index quantity

- Site.  The copy's lib/check.ml:337, the [Index_not_zero] refusal of
  brief 3.4 (A2, pin check.ml:1819).
- Edit.  `if Quantity.equal q Quantity.Zero then Ok ()` becomes
  `if Quantity.equal q q then Ok ()`, so the test is always true and an
  index binder at Many or at One is admitted.
- Killing line.  `kanon.exe check test/neg/mu-index-runtime.kan` printed
  nothing and exit 0, and the suite printed `NEG mu-index-runtime FAIL:
  the file checks and the negative expects it to fail`, `NEG-OK 13/14`
  and `SUITE-KERNEL FAIL`.

### SG-M5 the erasure word

- Site.  The copy's lib/erase.ml:447, the interim word of brief 3.8 that
  the four SMu arms at :585, :744, :818 and :890 read (A6, SG-D7).
- Edit.  `let mu_erase_word : string = "an erasure at a mu shape arrives
  at M1 Stage J"` becomes `let mu_erase_word : string = "an erasure at a
  shape past M0"`, so erasure answers the generic word of erase.ml:440
  for a checked mu term.
- Killing line.  `kanon.exe check --erased test/erase-neg/mu-erase.kan`
  printed `not yet: an erasure at a shape past M0`, exit 1, and the suite
  printed `ERASE-NEG mu-erase FAIL: the message is "an erasure at a shape
  past M0"`, `ERASE-NEG-OK 0/1` and `SUITE-KERNEL FAIL`.

### Stage G review mutations (2026-09-06)

Each mutation used a separate fixed-source copy under /private/tmp.
The command was `zsh COPY/dev/dunecho.sh build` followed by
`COPY/_build/default/test/main.exe COPY/test`.  All four builds exited
0 with no errors or warnings.  All four suites exited 1.  The unmutated
source passed the full gate battery.  No repository file was mutated.
Logs and exit files are under /private/tmp/kanon-g-mutation-logs-nzj9i441.

- `freshness`: disable the existing-family refusal in declare_family.
  Killing line: `NEG mu-redeclared FAIL: the file checks and the negative
  expects it to fail`.  The duplicate mutual member also fails its
  expected diagnostic, reaching the constructor-installation guard.
- `universe`: compare each field level with itself instead of the family
  level.  Killing line: `NEG mu-field-universe FAIL: the file checks and
  the negative expects it to fail`.
- `indices`: replace the result index telescope and argument lists by
  empty lists at the declaration check.  Killing lines:
  `NEG mu-result-index-type FAIL: the file checks and the negative
  expects it to fail` and `NEG mu-result-index-unbound FAIL: the file
  checks and the negative expects it to fail`.
- `parameters`: make the per-parameter identity check always true.
  Killing lines: `NEG mu-result-parameter FAIL: the file checks and the
  negative expects it to fail` and `NEG mu-result-parameter-order FAIL:
  the file checks and the negative expects it to fail`.

## Stage H

Six mutations, each on its own fresh copy of the repository made with
`rsync -a --exclude _build --exclude .gatework`, built through the copy's
own dev/dunecho.sh, which printed `OK build: 0 errors, 0 warnings` and
exit 0 for all six (SH-D13).  ROOT was never mutated.  The judge reran
all six at 2026-09-06 06:56, on the copies judge-m1 to judge-m6 under the
session scratch directory.  Each copy ran its own
`_build/default/test/main.exe test` and the stage local ELIM-SUITE leg
of brief 3.10.  SH-M6 is the plan's `SH-M1b` at M1-PLAN.md:200, carried
under one form of the id (SH-D14).  The line numbers below are the ones
of the copy, which are the ROOT numbers before the edit.

### SH-M1 part three of the criterion

- Site.  The copy's lib/rules.ml:1010-1011, the part three arm of
  `mu_zero_eliminable`, the port of pin check.ml:232.
- Edit.  `ct.Positivity.c_args` followed by
  `&& not ct.Positivity.c_self_rec)` becomes `ct.Positivity.c_args)`, so
  a self recursive constructor still passes the criterion.
- Killing line.  The copy's suite printed `NEG mu-large-elim-selfrec
  FAIL: the file checks and the negative expects it to fail`,
  `NEG-OK 25/26` and `SUITE-KERNEL FAIL`, exit 1.  ELIM-SUITE printed
  `ELIM-SUITE NEG mu-large-elim-selfrec exit=0 SIDECAR-MISMATCH line=`,
  the empty line being the acceptance where the sidecar promises
  `a large elimination out of a proposition needs a subsingleton family
  at Acc`.

### SH-M2 the branch completeness check

- Site.  Two sites, the copy's lib/rules.ml:1258 `mu_cover` and its
  :1309-1312, the `~none` arm of the `List.find_opt` of `mu_branch`.
  Both are needed, which is finding SH-F-LOW-1.
- Edit.  `mu_cover` answers `Ok ()` at once and its old body is kept
  beside it as `mu_cover_off`;  the `Option.to_result ~none:(...
  Missing_branch ...)` of `mu_branch` becomes an `Option.fold` whose
  `~none` gives an empty branch at `Term.Univ Level.zero`.
- Killing line.  The copy's suite printed `NEG mu-missing-branch FAIL:
  the file checks and the negative expects it to fail`, `NEG-OK 25/26`
  and `SUITE-KERNEL FAIL`, exit 1.  ELIM-SUITE printed
  `ELIM-SUITE NEG mu-missing-branch exit=0 SIDECAR-MISMATCH line=`,
  where the sidecar promises `the elimination of Two has no branch at
  cb`.

### SH-M3 the motive instantiation

- Site.  The copy's lib/rules.ml:1197, the body of `mu_result`.
- Edit.  `(self :: List.rev_append idx (ops.o_env ctx))` becomes
  `(self :: ops.o_env ctx)` with `let _ = idx in` above it, which is the
  plan's motive applied to the scrutinee alone.
- Killing line.  The copy's suite printed `CHECK mu-indexed FAIL:
  unbound: de Bruijn index 1 is outside the environment`, `CHECK-OK
  52/53`, the same row under ERASE with `ERASE-OK 52/53` and
  `SUITE-KERNEL FAIL`, exit 1.  ELIM-SUITE printed `ELIM-SUITE POS
  mu-indexed exit=1 GOLDEN-MISMATCH` with `got: unbound: de Bruijn index
  1 is outside the environment`.  The killer is the definition
  `read_index` at test/fixtures/mu-indexed.kan:22, which the fix round
  added;  before it the same mutation left `SUITE-KERNEL OK`, which was
  finding SH-F-HIGH-1.

### SH-M4 the required motive

- Site.  The copy's lib/rules.ml:1164-1166, the `Option.to_result
  ~none:(Error.Cannot_infer mu_motive_word)` of `mu_motive_of`.
- Edit.  A `None` motive is accepted with a made up one, `m_ind = Some
  n`, one `"_"` per family index, `m_self = "_"` and `m_body =
  Term.Univ Level.zero`.
- Killing line.  The copy's suite printed `NEG mu-no-motive FAIL: the
  message is "the term has type Type 1 and the expected type is Type 0"`,
  `NEG-OK 25/26` and `SUITE-KERNEL FAIL`, exit 1.  ELIM-SUITE printed
  `ELIM-SUITE NEG mu-no-motive exit=1 SIDECAR-MISMATCH line=the term has
  type Type 1 and the expected type is Type 0`.  The fixture is still
  refused, but at the universe of the made up motive and not at the
  missing one, so the sidecar line `an elimination at a mu shape needs a
  motive` is carried by the checked rule alone.

### SH-M5 the m_ind equality

- Site.  The copy's lib/rules.ml:1175-1178, the first guard arm of
  `mu_motive_of`.
- Edit.  The arm `| () when not (String.equal mn n) -> Error (...)` is
  removed, so a motive built for a sibling family is not compared with
  the scrutinee family.
- Killing line.  The copy's suite printed `NEG mu-motive-wrong-family
  FAIL: the file checks and the negative expects it to fail`,
  `NEG-OK 25/26` and `SUITE-KERNEL FAIL`, exit 1.  ELIM-SUITE printed
  `ELIM-SUITE NEG mu-motive-wrong-family exit=0 SIDECAR-MISMATCH line=`,
  where the sidecar promises `the motive is built for Beta and the
  scrutinee is at Alpha`.

### SH-M6 part two of the criterion

- Site.  The copy's lib/rules.ml:1005-1009, the part two arm of
  `mu_zero_eliminable`, the port of pin check.ml:231.  This is the
  plan's `SH-M1b` (SH-D14).
- Edit.  The `List.for_all` over `ct.Positivity.c_args` is dropped and
  the arm reads `(not ct.Positivity.c_self_rec)`, so a field at quantity
  `Many` still passes the criterion.
- Killing line.  The copy's suite printed `NEG mu-large-elim-nonsub
  FAIL: the file checks and the negative expects it to fail`,
  `NEG-OK 25/26` and `SUITE-KERNEL FAIL`, exit 1.  ELIM-SUITE printed
  `ELIM-SUITE NEG mu-large-elim-nonsub exit=0 SIDECAR-MISMATCH line=`,
  where the sidecar promises `a large elimination out of a proposition
  needs a subsingleton family at Box`.

## Stage I

Three mutations, each on its own fresh copy of the repository made with
`rsync -a --exclude _build --exclude .gatework`, built through the copy's
own dev/dunecho.sh, which printed `OK build: 0 errors, 0 warnings` and
exit 0 for all three (SI-D16).  ROOT was never mutated.  The judge reran
all three at 2026-09-06 12:02, on the copies judge-m1, judge-m2 and
judge-m3 under the session scratch directory.  Each copy ran its own
`_build/default/test/main.exe test` and the stage local checks of
brief 3.8 and 3.11 through the copy's own
`_build/default/bin/kanon.exe check`.  The line numbers below are the
ones of the copy, which are the ROOT numbers before the edit.

### SI-M1 the call order of brief 3.7

- Site.  The copy's surface/elab.ml:1003-1009, the `let* cert =` row
  that calls `Totality.guard_group`, with :1023 and :1047, the branch
  that hands the certificate to `Order.translate`.
- Edit.  `let* cert =` becomes `let cert : Order.t option =` with
  `|> Result.value ~default:None` appended, so the refusal of the guard
  is discarded;  `guarded` is renamed `_guarded` and the dispatch at
  :1047 becomes `(fun (_c : Order.t option) -> plain) cert`, so no
  certificate ever reaches the translation and the guard gates nothing.
- Killing line.  The copy's suite printed `NEG mu-nonstructural FAIL:
  the message is "spin"`, with `NEG mu-rec-guard-order FAIL: the message
  is "grow"`, `NEG-OK 27/31`, `ERASE-NEG-OK 1/4` and `SUITE-KERNEL FAIL`,
  exit 1.  The direct run
  `kanon.exe check test/neg/mu-nonstructural.kan` printed
  `unbound: spin`, exit 1, where the sidecar promises `recursive
  definition spin failed the structural termination guard`, so the
  fixture fails to fail with its own line and SI-G6 and SI-G7 both go
  red.

### SI-M2 the strictness of the order

- Site.  The copy's lib/order.ml:282-288, the `smaller_at` helper of
  `passes`, the port of the status read at
  kan-lang-tot-pin/lib/totality.ml:82-88.
- Edit.  The arm `| Principal | Other -> false` becomes
  `| Principal -> true` and `| Other -> false`, so a self call at an
  argument equal to the scrutinee, which stands at status Principal, is
  read as Smaller and passes.
- Killing line.  The copy's suite printed `NEG mu-rec-nondecreasing
  FAIL: the file checks and the negative expects it to fail`, with
  `NEG-OK 28/31` and `SUITE-KERNEL FAIL`, exit 1.  The direct run
  `kanon.exe check test/neg/mu-rec-nondecreasing.kan` printed no output
  and exit 0, which is the acceptance the sidecar refuses, so SI-G7 goes
  red.

### SI-M3 the mutual rule of brief 3.2

- Site.  The copy's lib/order.ml:482-491, the `rows_at` helper of
  `certify`, which asks every member of the group to pass at the one
  shared position `k` (SI-D7, SI-D24).
- Edit.  `passes ~rule ~group k formals inner` becomes a search
  `try_pos 0` that walks every position of that member and answers the
  first that passes, so each member takes its own decreasing position
  and a sibling call at another argument position is allowed.
- Killing line.  The copy's suite printed `NEG mu-rec-sibling-position
  FAIL: the message is "a structurally recursive definition eliminates
  its recursive argument at the head of its body"`, with
  `ERASE-NEG mu-rec-indexed FAIL: mismatch: a structurally recursive
  definition eliminates its recursive argument at the head of its body`,
  `NEG-OK 30/31`, `ERASE-NEG-OK 3/4` and `SUITE-KERNEL FAIL`, exit 1.
  The guard admits the group the sidecar refuses, and the refusal that
  is printed is the mismatch of `Order.translate`, not the termination
  line of SI-D6, so SI-G7 goes red.  The mutation also breaks the
  indexed positive, which the honest order accepts.

## Stage J

Four mutations, each on its own fresh copy of the repository made with
`rsync -a --exclude _build --exclude .gatework`, built through the
copy's own dev/dunecho.sh, which printed `OK build: 0 errors, 0 warnings`
and exit 0 for all four (SJ-D17).  ROOT was never mutated.  The judge
reran all four at 2026-09-06 15:30, on the copies judge-m1, judge-m2,
judge-m3 and judge-m4 under the session work directory.  Each copy ran
its own `_build/default/test/main.exe test`, its own
`_build/default/test/wasm.exe test`, its own dev/encoder-subset.sh, and
the m2 copy also ran the stage local gate SJ-G8 through its own
`_build/default/bin/kanon.exe`.  The line numbers below are the ones of
the copy, which are the ROOT numbers before the edit.

### SJ-M1 the group boundary of brief 3.8

- Site.  The copy's wasm/link.ml:926, the head of `family_groups`, which
  reads the strongly connected components of the reference edges the leg
  tids carry and gives one group name to each recursive member.
- Edit.  The body becomes `[]`, with the two arguments renamed to `_es`
  and `_fams`, so no member ever joins a group and each member of a
  mutual family is emitted in its own rec group.
- Killing line.  The copy's Wasm suite printed
  `EMIT mu-mutual-emit FAIL: golden differs`, with `WASM-OK 16/17` and
  `SUITE-WASM FAIL`, exit 1, so SJ-G3 goes red.  The kernel suite stayed
  `SUITE-KERNEL OK` and `ENCODER-SUBSET OK` still printed.  Direct
  `wasm-opt --enable-gc --enable-reference-types --enable-tail-call
  --print` on the mutated module exited 0 with an empty stderr and the
  mutated module still answered 4 under node, so the killer is the byte
  for byte golden compare and not the validator (finding SJ-F2).

### SJ-M2 the tail call of brief 3.9

- Site.  The copy's wasm/emit.ml:428, the row
  `if tail_ok c tail result then [ G.Return_call fi ]`, the known global
  call of an Elim translated recursion.
- Edit.  The guard becomes `if false`, so the site emits `G.Call fi` and
  the tail eligible recursion becomes an ordinary nested call.
- Killing line.  The stage local gate SJ-G8 printed
  `TAIL-DEPTH mu-tail-100k node exit 2 answer kanon: run: node invalid:
  Maximum call stack size exceeded want 100000` and
  `TAIL-DEPTH mu-tail-100k wasmtime exit 4 answer kanon: run: wasmtime
  trap: call stack exhausted want 100000`, with
  `TAIL-DEPTH-OK 2/4 tail return_call 1 cata return_call 0` and
  `TAIL-DEPTH FAIL`, exit 1.  The second half of the mutation holds:  the
  general catamorphism fixture is unchanged, at
  `TAIL-DEPTH mu-cata-depth node exit 0 answer 4095 want 4095` and
  `TAIL-DEPTH mu-cata-depth wasmtime exit 0 answer 4095 want 4095`,
  because it never held a `return_call` (A10, SJ-D38).  The Wasm suite
  also went red, at `EMIT d02-tail-call FAIL: golden differs`,
  `WASM-OK 13/17` and `SUITE-WASM FAIL`, exit 1.

### SJ-M3 the index rule of brief 3.1

- Site.  The copy's lib/erase.ml:1089, the row
  `let* keep = point_runtime ec q tyv in` of the branch binder fold,
  which drops a binder whose field is not a runtime field.
- Edit.  The answer is bound to `_keep` and `keep` becomes `true`, so
  every branch binder is kept, including an index binder at quantity
  Zero.
- Killing line.  The copy's kernel suite printed
  `ERASE mu-rec-indexed FAIL: the erased form is not the golden text`,
  with `SUITE-KERNEL FAIL`, exit 1, so SJ-G2 goes red.

### SJ-M4 the binary form of brief 3.6

- Site.  The copy's wasm/gc_encode.ml:226, the row
  `let type_section : string = section 1 (vec rectype m.types) in` of
  `encode`, which writes one entry for each rec group.
- Edit.  The groups are flattened to singletons before `vec rectype`, so
  every member of every group becomes a standalone type entry and no
  `0x4E` rec group entry is written.
- Killing line.  The copy's Wasm suite printed
  `EMIT mu-mutual-emit FAIL: golden differs`, with `WASM-OK 16/17` and
  `SUITE-WASM FAIL`, exit 1, so SJ-G3 goes red.  `ENCODER-SUBSET OK`
  still printed and direct
  `wasm-opt --enable-gc --enable-reference-types --enable-tail-call
  --print` on the mutated module exited 0, so the leg the plan names
  first, ENCODER-SUBSET, does not kill this mutation and the golden
  compare does (finding SJ-F2).

### Staged review regressions (2026-09-06)

| Case | Original staged implementation | Fixed implementation |
| --- | --- | --- |
| mu-parameter-layout: Box Nat before Box (Nat -> Nat) | check exits 0; emit exits 2, application head is not a function | check and emit exit 0; Wasm validates; kernel, Node and Wasmtime return 9 |
| mu-dependent-layout: erased generic payload before a Nat field | check exits 0; emit exits 2, argument list is shorter than its signature | check and emit exit 0; Wasm validates; kernel, Node and Wasmtime return 27 |
| Delete migrated fixtures/mu-erase.kan | SUITE-KERNEL OK, exit 0 | MIGRATED mu-erase FAIL, MIGRATED-OK 3/4, SUITE-KERNEL FAIL, exit 1 |

The baseline was freshly built from the original staged tree.  The deletion
mutation ran only in a scratch copy.  Both new language fixtures and all
six associated goldens are part of the normal kernel and Wasm suites.

## M1 Stage K: Nat runtime and exact One mutations (2026-09-06)

Status: all four required semantic mutations are killed.  All eleven
Stage K gates pass after the user-approved M0 spine correction, as
recorded in the Stage K build section.  No mutation touches ROOT or the
active implementation in place.

PREP is `/Users/oobi/Documents/gpt4/kanon-stage-k`.  Each semantic mutant
starts from a separate fresh copy excluding .git, _build, .gatework and
meta/.lake.  Every mutant builds through its copied dev/dunecho.sh with
zero errors and warnings.  Compiler errors are not counted as kills.

| Id | Mutation and passing control | Killing observation and evidence |
| --- | --- | --- |
| SK-M1 | Check.bind stores One as Many in PREP/one-mutation/work.  The unmutated one-used-twice fixture rejects with its exact Quantity diagnostic. | The mutant accepts the fixture, exit 0 instead of 1.  Its One path runner exits 1, with only 15/27 direct checks passing.  PREP/one-mutation contains control.json, mutation.diff, build.log, mutant-negative.log, mutant-paths.log and results.json. |
| SK-M2 | Replace the natMul slow dispatch in wasm/emit.ml with Unreachable in PREP/mutations/sk-m2.  The unmutated nat-big source returns 7 after multiplying 35184372088833 by 35184372088837, then consuming the big result. | Node, Wasmtime and both trap instead of returning 7.  The kernel control remains 7, proving that the mutation affects runtime arithmetic.  The focused runtime assertion runner exits 1.  PREP/mutations/sk-m2.diff, sk-m2-build.log and runtime-mutations.json retain exact commands and outputs. |
| SK-M3 | In PREP/mutations/sk-m3, change the first unary natAdd expectation from natAdd 0 0 to natAdd 0 1, keeping the actual unary witness unchanged.  The original gate passes 7445/7445. | The typed constructor-index comparison rejects the altered witness.  The complete gate reports 6356/7445 and exits 1; the same fixture remains selected.  After the byte-identical move into test/agreement, the unary gate again exits 1 at 4356/5445.  PREP/mutations/sk-m3-source.json, sk-m3.diff, sk-m3-build.log, sk-m3-evidence/results.json and sk-m3-final-evidence/unary-results.json retain the source delta, clean build and behavioral failures. |
| SK-M4 | Replace literal limb-store index i by i*0 in PREP/mutations/sk-m4.  The heterogeneous subtraction observation compares natSub 1073807363 1073807358 with 5 and returns 1 unmutated. | Node, Wasmtime and both return 0 after the malformed stores.  The kernel remains 1.  The focused runtime assertion runner exits 1.  PREP/mutations/sk-m4.diff, sk-m4-build.log and runtime-mutations.json retain exact evidence. |

Runtime controls comprise eight unmutated observations, six mutated host
failures, two failed assertion runners and two clean fresh builds.
PREP/mutations/final-erasure-reuse.json establishes that the final erasure
repairs leave the two mutation fixtures' erased inputs byte-identical
and their source and runtime emitter hashes unchanged.  The final runtime
control rerun is PREP/check-review/nat-runtime-final.log, 20/20 PASS.
PREP/one-final-validation.json records unchanged checker hashes for SK-M1.

The subset reader has an additional negative control, separate from the
four semantic mutations.  A real Binaryen WAT containing the structural
exact qualifier passes.  Appending an unlisted i32.and makes the reader
exit 1 and print ENCODER-SUBSET FAIL.  The final actual goldens also pass.
Evidence: PREP/mutations/subset-final/checks.json.  No opcode allowlist,
timer, expected value or denominator is weakened to obtain these kills.

The parser helper also has a negative control: invalid source reports
ROUNDTRIP FAIL with a precise parse error and exit 1.  All five actual
unary files pass the same source/print/source tree-equality assertion
previously run by the ordinary kernel suite.  Evidence:
PREP/agreement-roundtrip-evidence.json.

## Stage L (2026-09-06)

All mutations ran in isolated copies under
/Users/oobi/Documents/gpt4/kanon-stage-l/mutations.  Nine protected active
source hashes matched before and after.  No mutation edited active WORK.

| id | isolated change | observed catch | status |
| --- | --- | --- | --- |
| SL-M1 | M1_CORPUS_MS 713 to 1 | M1-CORPUS exit 1 after the successful 814 pipeline; elapsed 31365.121 ms against 1 at load 143.812 | caught |
| SL-M2 | M0_RATIO 2.000 to 0.1 | M0-RATIO exit 1; median 475.531 ms, normalized ratio 37.331629 against 0.100 at load 212.221 | caught |
| SL-M3 | remove the top-level mu declaration production | isolated build has 0 errors and 0 warnings; spine check exits 1 at the first mu, line 259 column 1; active control checks and returns 599 | caught |

SL-M1's unmodified baseline passed at 416.399 ms against 713 in the full
battery.  SL-M2 proves the ratio comparison fails at the mutated bound;
the unmodified 2.000 baseline still failed under load, so this catch does
not discharge SL-G11.  SL-M3 uses its own build directory, and the two
bound-only copies share the active binary without writing it.

Commands and exact output: mutations/commands.json, results.json,
sl-m1-corpus.stdout, sl-m2-ratio.stdout and sl-m3-spine-check.stderr.
Each *-change.json records old and new source bytes.  The full record is
mutations-result.md.  Additional controls reject each of the five wrong
typed agreement witnesses and five catch-all forms; these supplement the
three required mutations without replacing any one of them.

Stage L validation remains pending M0-TIME, M0-RATIO and complete
AGREEMENT execution.  No failed baseline was waived.
