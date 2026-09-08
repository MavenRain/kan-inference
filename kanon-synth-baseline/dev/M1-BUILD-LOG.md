# kanon M1 build log

This log follows the plan at kanon-m1/M1-PLAN.md.  dev/M0-BUILD-LOG.md is
closed at M0-EXIT (M1-PLAN.md:51) and no M1 stage writes to it again.

## Stage F (2026-09-06)

The lake package kanon-meta and the four Beck-Chevalley statements over the two admitted shapes.  One builder wrote the package and the judge reran every gate and every mutation on a cleaned build tree before this entry.

### Deliverables

- meta/lean-toolchain, 1 line.  `leanprover/lean4:v4.33.0-rc1`, byte for
  byte KT/lean-toolchain (SF-D2).
- meta/lakefile.lean, 12 lines.  Package `kanon-meta`, `autoImplicit`
  false, one require of kan-tactics at the 40 character revision
  3317f7ac5a22ca0d85b90a3286b8fe0c36cea8ac, and the default target
  `KanonMeta`.
- meta/.gitignore, 1 line.  `.lake/`, so ROOT/.gitignore stays untouched
  (SF-D8).
- meta/lake-manifest.json, 26 lines.  The two pinned revisions,
  kan-tactics at 3317f7ac and comp-cat-theory at cc6ced10.
- meta/KanonMeta.lean, 11 lines.  The root module.  It imports the three
  module files and holds no declaration.
- meta/KanonMeta/Syntax.lean, 63 lines.  `Quantity`, the mutual family
  `Shape` and `Term`, and `Addr`, mirroring lib/shape.ml:11-12 and
  SPEC.md:26-42 with De Bruijn indices.
- meta/KanonMeta/Subst.lean, 122 lines.  The renaming layer, then
  `Subst`, `up`, `subst` and `substShape`, every function total and
  structurally recursive.
- meta/KanonMeta/BeckChevalley.lean, 55 lines.  The four theorems
  `bc_lan_spi`, `bc_ran_spi`, `bc_lan_scoll` and `bc_ran_scoll`, each
  closed by `kan_rfl` and nothing else.
- meta/Axioms.lean, 21 lines.  The SF-G4 driver with exactly four
  `#print axioms` commands.
- dev/M1-BUILD-LOG.md and dev/M1-MUTATION-LOG.md gain this entry and the
  Stage F mutation section (the judge).

### Gates (the judge reran SF-G1 to SF-G7 on the tree at 2026-09-06 03:01)

- SF-G1 BUILD, OK.  `rm -rf meta/.lake/build`, then
  `/Users/oobi/.elan/bin/lake +leanprover/lean4:v4.33.0-rc1 --dir
  /Users/oobi/Documents/kanon-stage-f/meta build`, detached.  The last
  five log lines are `✔ [36/40] Built KanonMeta.Syntax (557ms)`,
  `✔ [37/40] Built KanonMeta.Subst (392ms)`, `✔ [38/40] Built
  KanonMeta.BeckChevalley (4.0s)`, `✔ [39/40] Built KanonMeta (1.3s)`
  and `Build completed successfully (40 jobs).`;  the exit file holds
  `EXIT 0`.  `rg -c "error:"` over the log prints nothing, rg exit 1.
- SF-G2 NO-SORRY, OK.  `rg -n -c "sorry" meta` printed nothing, exit 1
  (`SWEEP-A-EXIT 1`).  `rg -n -c "axiom |native_decide|partial |unsafe "
  meta` printed nothing, exit 1 (`SWEEP-B-EXIT 1`).
- SF-G3 CLIENT, OK.  The client under SCRATCH/stageF/client, its build
  tree deleted first and its fetched packages kept, built with exit 0.
  The final three lines are `ℹ [41/42] Built Client (1.2s)`, the
  `#check` report `info: Client.lean:5:0: KanonMeta.bc_lan_spi (sigma :
  Subst) (A : Term) (q : Quantity) (x : String) (dom : Term) : subst
  sigma (Term.lan (Shape.SPi q x dom) A) = Term.lan (Shape.SPi q x
  (subst sigma dom)) (subst (up sigma) A)`, and `Build completed
  successfully (42 jobs).`
- SF-G4 AXIOMS, OK.  `lake env lean meta/Axioms.lean`, detached, exit 0.
  The four lines, verbatim and in the order of the brief:
  `'KanonMeta.bc_lan_spi' does not depend on any axioms`,
  `'KanonMeta.bc_ran_spi' does not depend on any axioms`,
  `'KanonMeta.bc_lan_scoll' does not depend on any axioms`,
  `'KanonMeta.bc_ran_scoll' does not depend on any axioms`.  No axiom
  name appears, so SF-B7 does not fire.
- SF-G5 TACTICS, OK.  `rg -n -o "kan_[a-z_]+" meta` returned five hits,
  all `kan_rfl`, the final line
  `meta/KanonMeta/BeckChevalley.lean:53:kan_rfl`.  Four are the proof
  bodies at :30, :37, :46 and :53;  the fifth at :13 is the module doc
  comment.  `rg -n "by$|by " meta` returned four `:= by` lines, at :29,
  :36, :45 and :52, each followed by `kan_rfl` alone.  A word sweep for
  the thirteen core tactic names of the brief over
  BeckChevalley.lean returned only statement text and doc prose, no
  tactic position.
- SF-G6 ROOT-GATES, OK.  `zsh dev/gates.sh` printed fifteen PASS lines,
  the MEASURE block and `GATES-OK`, exit 0.  `rg -c "^PASS "` over the
  log is 15 and the final line is `GATES-OK`.  The battery reads as it
  read at 09e77e9, because Stage F adds no OCaml line.  The battery ran
  twice, before and after this log file was written, and printed
  `GATES-OK` with no FAIL line both times.  `git -C ROOT status
  --porcelain` prints three lines, `?? dev/M1-BUILD-LOG.md`,
  `?? dev/M1-MUTATION-LOG.md` and `?? meta/`.
- SF-G7 TRUSTED-LINES, OK.  `zsh dev/trusted-lines.sh` printed
  `TRUSTED-LINES kernel=2305/3000 encoder=216/600 OK`, exit 0.  The
  numbers are the M0 numbers, because Lean files are not in the believed
  OCaml set.

### MEASURE

| Row | Value |
| --- | --- |
| build wall clock (the build verb of lake) | 15 s, start 1788688894, end 1788688909, after `rm -rf meta/.lake/build`;  budget 900 s |
| olean count under meta/.lake/build | 4 (KanonMeta, KanonMeta.Syntax, KanonMeta.Subst, KanonMeta.BeckChevalley) |
| theorem count | 4 |
| package line count | 312 across the nine meta files |

### Decisions

- SF-D1 The package lives at ROOT/meta with the lake package name
  `kanon-meta` and the library root `KanonMeta`.
- SF-D2 meta/lean-toolchain holds `leanprover/lean4:v4.33.0-rc1`.  No
  agent ran an install verb.
- SF-D3 kan-tactics is required at the 40 character revision
  3317f7ac5a22ca0d85b90a3286b8fe0c36cea8ac, never a branch name.
- SF-D4 The object language holds the two admitted shapes only.  SPar,
  SMu and SNu stay out.
- SF-D5 De Bruijn indices with `Subst := Nat -> Term` and a lift, which
  mirrors `Var of int` (SPEC.md:26).
- SF-D6 The four theorem names are `bc_lan_spi`, `bc_ran_spi`,
  `bc_lan_scoll` and `bc_ran_scoll`, in that order.
- SF-D7 The nineteen kan-tactics names are the whole tactic allowlist
  and SF-G5 is the rg check of it.
- SF-D8 meta/.gitignore carries `.lake/`, so ROOT/.gitignore stays
  untouched.
- SF-D9 meta/lake-manifest.json is committed.
- SF-D10 Every lake command ran through the detached runner of brief
  section 8, never in the foreground.
- SF-D11 Every lake command carries `+leanprover/lean4:v4.33.0-rc1`
  first and an absolute `--dir`, because elan reads the working
  directory and not the flag.
- SF-D12 Stage F writes under ROOT/meta only, plus the two new M1 log
  files under ROOT/dev that the judge writes.
- SF-D13 The fetch order of the brief was kept.  No fetch ran in this
  session:  the packages were already present, so the resumed run never
  fetched twice.
- SF-D14 `Addr` stays outside the mutual family and holds no term:  the
  point argument of `APt` rides in the argument field of `Term.intro`
  and `Term.out`, so the family is the minimal faithful pair Shape and
  Term.  `ACtor` stays out with the two recursive shapes that own it.
- SF-D15 The `lan` and `ran` arms of `ren` and of `subst` split on the
  shape and lift only under `SPi`, which is `spi_diagram_arity = 1` and
  `coll_diagram_arity = 0` (lib/rules.ml:635 and :637).  Every pattern
  field is named and used, so no arm carries a wildcard.
- SF-D16 The branch of `elim` and the leg of `sec` take the substitution
  unlifted, because the kernel gives each leg its own binder list
  (lib/term.ml:27-30) and this mirror does not carry that list.
- SF-D17 The renaming layer is defined before the substitution layer,
  because `up` weakens the terms a substitution carries.
- SF-D18 `Ren` and `Subst` are `abbrev`, so a plain `Nat -> Nat` or
  `Nat -> Term` unifies with them with no coercion.
- SF-D19 The require line of meta/lakefile.lean keeps the absolute path
  /Users/oobi/Documents/kan-tactics of brief 3.1, not the GitHub URL
  that SF-D13 mentions, because meta/lake-manifest.json pins that url at
  3317f7ac and a second update is forbidden.
- SF-D20 meta/Axioms.lean and the client file carry `open KanonMeta`, so
  the unqualified `#check` and the four `#print axioms` commands resolve
  and the output prints the qualified names.
- SF-D21 The doc prose of Subst.lean and Axioms.lean avoids the literal
  tokens that SF-G2 sweeps, because the gate is textual.
- SF-D22 `Level.t` is an OCaml `int` (lib/level.ml:2), so `Term.univ`
  holds a `Nat`, and `Quantity` mirrors lib/quantity.ml:10-13.
- SF-D23 The MEASURE wall clock was taken after `rm -rf
  meta/.lake/build`, so it is a full build of the library against built
  dependencies and not a cache read.
- SF-D24 A scratch probe under SCRATCH/stageF/probe proved the mutual
  structural recursion definitional before any file was written under
  meta, so no core tactic was ever needed in the package.

### Findings

- F1, info, brief text.  Brief section 3.4 SF-D13 asks for the GitHub
  URL of kan-tactics, while section 3.1 asks for the absolute path
  /Users/oobi/Documents/kan-tactics.  kan-tactics has no GitHub remote
  here, so the URL clause cannot apply.  Resolution: the package follows
  3.1 and meta/lake-manifest.json, which pins the absolute path;  the
  brief clause needs the correction, the package needs none.
- F2, low, sandbox.  A rebuild of the SF-G3 client from a deleted
  .lake directory fails, because comp-cat-theory is fetched from GitHub
  and the sandbox has no network.  Resolution: only PACKAGE/.lake/build
  is deleted to force a real build, never .lake/packages.  The judge's
  rerun deleted the build tree of meta and of the client and kept both
  package trees, and both builds are green.
- One defect of the builder was found and fixed inside the run, not
  logged as a finding:  an append with `head -n -2` is not supported by
  the BSD head of this machine and emptied BeckChevalley.lean, so run
  bc2 failed.  The file was rewritten whole and every later append went
  through a checked appender.

### Hand-off notes

- The optional agreement lemma of M1-PLAN.md:89 and :182 stays
  unwritten.  The ruling round 2026-09-06 (b) rules it out of this run.
  It is a separate opt-in now that the four theorems are green.
- The M1-EXIT criterion "Stage F green" (M1-PLAN.md:252) is met by the
  seven gates above.  D-M1-8 (RATIFICATIONS.md:66) makes Stage F, and
  not Stage G, the gate of M1-EXIT.
- meta/.lake is ignored by meta/.gitignore, so the stage commit carries
  the nine files of Deliverables and these two log files.  The user
  commits;  no agent commits.
- The client package of SF-G3 lives under SCRATCH and never in ROOT.  It
  is rebuilt from meta's fetched packages, because the sandbox reaches
  no remote.

### Stage F review fixes (2026-09-06)

The review found that section and branch bodies lost their binders,
and that point addresses lost their argument.  The following changes
supersede SF-D14 and SF-D16 and the original syntax description above.

- `Addr.apt` now holds the point term independently of the function
  head or fibre arguments.  It joins the mutual syntax family.
- `Leg` retains the binder list.  Sections retain all their legs, and
  eliminations retain their quantity, motive and addressed branches.
  Introductions retain their fibre argument list.  `Motive` retains its
  indices, self binder and body as specified in lib/term.ml.
- `ren` and `subst` traverse all these fields.  Leg bodies lift under
  their explicit binders; motive bodies lift under their indices and
  self binder.  Point arguments use the outer context.  List, option
  and pair traversal helpers keep both mutual definitions structurally
  recursive through the equation compiler.
- `meta/test/Regression.lean` adds 16 checks using `kan_rfl`.  A separate
  default Lake target builds them without importing tests from the
  public library.  They cover closed binders, free variables, weakening,
  empty and multiple collection legs, point operands and motive scope.

Validation used scratch copies at /private/tmp/kanon-stage-f-fixes and
the pinned Lean 4.33.0-rc1 toolchain with cached dependencies.  Commands
used `/Users/oobi/.elan/bin/lake +leanprover/lean4:v4.33.0-rc1 --dir`.

- Package `meta build`: `Build completed successfully (42 jobs).`,
  exit 0, including the four theorems and all 16 regression checks.
- Fresh `client build`, requiring the scratch package and checking all
  four theorems plus `substLeg` and `substAddr`:
  `Build completed successfully (42 jobs).`, exit 0.
- `meta env lean /private/tmp/kanon-stage-f-fixes/meta/Axioms.lean`,
  exit 0, printed:
  `'KanonMeta.bc_lan_spi' does not depend on any axioms`
  `'KanonMeta.bc_ran_spi' does not depend on any axioms`
  `'KanonMeta.bc_lan_scoll' does not depend on any axioms`
  `'KanonMeta.bc_ran_scoll' does not depend on any axioms`.
- All four review mutations failed in the regression target, as recorded
  in M1-MUTATION-LOG.md.  The source escape-hatch sweep had no hits.
- No OCaml or root gate implementation changed.  The root runtime
  battery was not rerun for these Lean-only fixes.  The optional
  agreement lemma remains outside this change.

## Stage G (2026-09-06)

### Deliverables

The line counts are read on ROOT after the build of SG-G1.

| file | lines | note |
| --- | --- | --- |
| lib/positivity.ml | 153 | new;  strict positivity, the family record |
| lib/rules.ml | 1193 | the SMu pack replaces the refusal at the old :188 |
| lib/check.ml | 446 | the index telescope rules and the installation |
| lib/global.ml | 130 | the family table and its one accessor |
| lib/shape.ml | 60 | the three total views payload, point_dom, family |
| lib/term.ml | 92 | the ACtor rows of as_apt and as_aleg |
| lib/error.ml | 69 | Index_not_zero and Index_above_universe |
| lib/erase.ml | 1146 | the interim mu erasure word of 3.8 |
| SPEC.md | 470 | the moved R0 counts and the positivity rule text |
| dev/trusted-lines.sh | 74 | positivity.ml and global.ml join the list |
| surface/token.ml | 128 | the mu and and words |
| surface/lexer.ml | 140 | the two new words |
| surface/syntax.ml | 234 | the fam, fam_ctor and DMu rows |
| surface/parser.ml | 458 | the minimal mu production of C7 |
| surface/elab.ml | 811 | the DMu arm, elab_program_in and check_in |
| bin/kanon.ml | 308 | run_erased and module_bytes carry the globals |
| test/main.ml | 289 | the ERASE-NEG group and the moved KNEG row |

The fixtures of brief 3.9 and the interim erasure fixture of 3.8.

| file | lines |
| --- | --- |
| test/fixtures/mu-direct.kan | 8 |
| test/fixtures/mu-indexed.kan | 11 |
| test/fixtures/mu-mutual.kan | 9 |
| test/neg/mu-nonpositive.kan | 7 |
| test/neg/mu-nonpositive.err | 1 |
| test/neg/mu-index-runtime.kan | 10 |
| test/neg/mu-index-runtime.err | 1 |
| test/neg/mu-index-mismatch.kan | 14 |
| test/neg/mu-index-mismatch.err | 1 |
| test/erase-neg/mu-erase.kan | 11 |
| test/erase-neg/mu-erase.err | 1 |

The six golden files test/golden/mu-direct.checked, mu-direct.erased,
mu-indexed.checked, mu-indexed.erased, mu-mutual.checked and
mu-mutual.erased are empty, because the three positives declare families
and add no entry (SG-D22).

The minimal mu production of correction C7 is surface/parser.ml:411-453,
43 lines, with its doc comment at :396-410, the declaration arm at
:388-390 and the term position refusals at :303-306.  The sugar and the
spine additions stay at Stage L (M1-PLAN.md:230).

### Gates

The judge reran SG-G1 to SG-G7 on ROOT at 2026-09-06 04:21, after
`zsh dev/dune.sh clean`.  Each line below is the exact final line of the
command, with its exit code.

- SG-G1 BUILD.  `zsh dev/dune.sh clean` exit 0, then
  `zsh dev/dunecho.sh build` printed `OK build: 0 errors, 0 warnings`,
  exit 0.
- SG-G2 R0-AUDIT.  `zsh dev/r0-audit.sh` printed `R0-AUDIT OK`, exit 0.
- SG-G3 R0-COUNT.  The brief command `zsh dev/gates.sh --leg R0-COUNT`
  printed `gates: unknown leg R0-COUNT`, exit 64, because dev/gates.sh
  accepts only axioms, e2e, time, ratio, denominators and pin at :257-266
  (SG-D25, finding F1).  The leg body `zsh dev/r0-count.sh` printed
  `R0-COUNT OK`, exit 0, and the whole battery printed `PASS R0-COUNT`.
  `_build/default/bin/kanon.exe spec-count` printed
  `shapes admitted 3: SPi SColl SMu` and
  `no eta 3: Lan-SColl Ran-SMu Lan-SMu`, exit 0.
- SG-G4 POSITIVITY.  The stage local command over the six fixtures of
  3.9, `kanon.exe check FILE`, printed:
  test/fixtures/mu-direct.kan, no output, exit 0;
  test/fixtures/mu-indexed.kan, no output, exit 0;
  test/fixtures/mu-mutual.kan, no output, exit 0;
  test/neg/mu-nonpositive.kan,
  `not yet: a family that is not strictly positive arrives at M2`,
  exit 1;
  test/neg/mu-index-runtime.kan, `index not zero: the index i of W is at
  quantity w and every index binder is at 0`, exit 1;
  test/neg/mu-index-mismatch.kan, `mismatch: the constructor vz of V
  gives the index (In SMu N [] (ACtor zero) []) and the type asks for (In
  SMu N [] (ACtor succ) [(In SMu N [] (ACtor zero) [])])`, exit 1.
  The interim erasure fixture of 3.8,
  `kanon.exe check --erased test/erase-neg/mu-erase.kan`, printed
  `not yet: an erasure at a mu shape arrives at M1 Stage J`, exit 1.
- SG-G5 SUITE-KERNEL.  The brief command `zsh dev/gates.sh --leg
  SUITE-KERNEL` printed `gates: unknown leg SUITE-KERNEL`, exit 64, for
  the reason of SG-G3 (SG-D25, finding F1).  The leg body
  `_build/default/test/main.exe test` printed `CHECK-OK 50/50`,
  `NEG-OK 14/14`, `ERASE-NEG-OK 1/1`, `KNEG-OK 2/2` and the final line
  `SUITE-KERNEL OK`.  The whole battery printed `PASS SUITE-KERNEL`.
- SG-G6 TRUSTED-LINES.  `zsh dev/trusted-lines.sh ROOT` printed
  `TRUSTED-LINES kernel=2995/3000 encoder=216/600 OK`, exit 0.  N is
  2995 over the ten believed files of 3.10, which hold lib/positivity.ml
  and lib/global.ml.
- SG-G7 HOUSE.  `zsh dev/house.sh ROOT` printed `HOUSE OK`, exit 0.
- SG-G8 LOGS.  dev/M1-BUILD-LOG.md holds `## Stage G (2026-09-06)` once
  and dev/M1-MUTATION-LOG.md holds `## Stage G` once.
  `git -C ROOT diff --stat -- dev/M0-BUILD-LOG.md dev/MUTATION-LOG.md`
  printed nothing, so both M0 logs are byte for byte unchanged.  The
  porcelain lists only Stage G paths.

### MEASURE table

The judge ran the whole battery `zsh dev/gates.sh` once on ROOT at
2026-09-06 04:21, at the load average 11.47 11.86 13.32.  The rows are
copied from that run.

```
MEASURE BUILD tier=SLOW elapsed_ms=65.823 exit=0
MEASURE CARRY tier=MED elapsed_ms=351.558 exit=1
MEASURE R0-COUNT tier=FAST elapsed_ms=43.445 exit=0
MEASURE R0-AUDIT tier=FAST elapsed_ms=23.733 exit=0
MEASURE SUITE-KERNEL tier=SUITE elapsed_ms=23.876 exit=0
MEASURE SUITE-WASM tier=SUITE elapsed_ms=1469.222 exit=0
MEASURE ENCODER-SUBSET tier=FAST elapsed_ms=44.198 exit=0
MEASURE AXIOMS tier=MED elapsed_ms=23.589 exit=0
MEASURE M0-E2E tier=SLOW elapsed_ms=441.148 exit=0
MEASURE M0-TIME tier=SLOW elapsed_ms=635.494 exit=0
MEASURE M0-RATIO tier=SLOW elapsed_ms=249.866 exit=0
MEASURE TRUSTED-LINES tier=FAST elapsed_ms=21.540 exit=0
MEASURE DENOMINATORS tier=MED elapsed_ms=37.169 exit=0
MEASURE HOUSE tier=MED elapsed_ms=72.436 exit=0
MEASURE PIN tier=FAST elapsed_ms=66.093 exit=0
MEASURE M0-RATIO kanon_ms=26.068 tot_ms=103.662 ratio=0.251
```

The timed leg.  The bound stays 150 ms and no agent moved it;
dev/gates.sh:48 still reads `M0_TIME_MS=150` (dev/M0-BUILD-LOG.md:999).
The battery reading was `PASS M0-TIME median_ms=93.984 bound_ms=150` at
the load average 11.47.  The judge then ran the leg three more times, at
2026-09-06 04:25, and reports every reading with its load average:

```
run 1  load 14.34 13.34 13.57  PASS M0-TIME median_ms=91.806 bound_ms=150
run 2  load 14.34 13.34 13.57  PASS M0-TIME median_ms=92.000 bound_ms=150
run 3  load 14.34 13.34 13.57  PASS M0-TIME median_ms=98.854 bound_ms=150
```

The builder read `FAIL M0-TIME median_ms=182.209 bound_ms=150` at the
load average 12.77 (SG-D27).  Four judge readings under 100 ms, at a
higher load, confirm the load artefact and refute a regression.

### Decisions

SG-D1 to SG-D13 are pinned by the Stage G brief section 3.11.  SG-D13 to
SG-D27 are the builders'.  The number SG-D13 is used twice, because the
brief says the builders continue after SG-D12 but its own list ends at
SG-D13;  both texts are kept and the collision is reported as finding F4.

- SG-D1 The family record and its table live beside the Global table and
  Global.entry gains no constructor (R-Q3);  lib/global.ml joins the
  believed TRUSTED-LINES list and the budgets stay 3000 and 600.
- SG-D2 rules.ml reads the record through exactly one accessor, so no
  family lookup enters check.ml (r0-audit.sh:6-11).
- SG-D3 Positivity and self_rec are computed once at installation and
  stored, never recomputed at formation (A4).
- SG-D4 Ran (SMu ..) is refused inside the pack at ran_lvl and at the Ran
  intro and elim fields, never at the dispatch.
- SG-D5 The pack answers eta_ran false and eta_lan false, so no eta grows
  from 1 to 3 and the eta table stays at three rows.
- SG-D6 The SPar cell at SPEC.md:30 moves from M1 to M2 in this commit
  (open question 4, RATIFICATIONS.md:77).
- SG-D7 The interim erasure word is exactly `an erasure at a mu shape
  arrives at M1 Stage J` and the fixture pins it byte for byte.
- SG-D8 Formation checks the declared level with Level.le and never
  computes a max (A5).
- SG-D9 The elimination fields answer the Stage H word at this stage.
- SG-D10 SG-G8 LOGS is added by the brief on the form of SE-G12.
- SG-D11 Every mutation runs on a fresh copy under SCRATCH/stageG and
  ROOT is never mutated.
- SG-D12 positivity.ml joins the trusted list and the budgets do not
  move.
- SG-D13 (brief) The six fixtures of 3.9 enter as .kan files through the
  minimal mu production of C7;  test/main.ml is not the entry path.
- SG-D13 (builder 1) lib/positivity.ml walks a shape through the three
  total views of shape.ml and spells no shape name, so SG-G2 stays green.
- SG-D14 The family record type lives in lib/positivity.ml, not in
  global.ml, because global.ml reads Prim.catalog and prim.ml reads
  Rules.arrow;  the table and its one accessor stay beside the Global
  table at global.ml:61-79.
- SG-D15 The two level fields of the pack are retyped to read the mu
  level off the family record;  a combinator payload_lvl adapts the two
  M0 packs, so SPi and SColl keep their bodies.
- SG-D16 The diagram at the mu shape is the parameter section, one binder
  free leg per parameter.
- SG-D17 A Provisional family forms, so a field type may name the family
  while the constructors are installed;  only a Complete family whose
  stored verdict is false is refused.
- SG-D18 Three refactors keep the ten believed files at 2995 of 3000:
  inline refusal lambdas, one accessor that merges the lookup and the
  stored verdict, and one telescope walk shared by the binder.
- SG-D19 The words for the sidecars are `a family that is not strictly
  positive arrives at M2`, `a right former at a mu shape arrives at M2`
  and `an elimination at a mu shape arrives at M1 Stage H`;  the two new
  error heads print as `index not zero: ` and `index above universe: `.
- SG-D20 The erase entry path carries the globals:  elab gains
  elab_program_in and check_in, and bin/kanon.ml and test/main.ml pass
  those globals to Erase.program, so a checked mu file no longer erases
  in an empty family table.
- SG-D21 The interim erasure word is pinned by a new negative group,
  test/erase-neg, run by erase_negative and counted as ERASE-NEG-OK.
- SG-D22 The three positives declare families and add no entry, so the
  six golden files are empty;  CHECK and ERASE grow from 47 to 50.
- SG-D23 The KNEG row smu moves from the left former to the right former
  at a mu shape, so KNEG keeps two rows and pins mu_ran_word.
- SG-D24 The constructor lookup of the elaborator reads the public
  Global.StringMap fold over the family table and adds no accessor to
  lib/global.ml, because the kernel budget stands at 2995 of 3000.
- SG-D25 dev/gates.sh --leg accepts only axioms, e2e, time, ratio,
  denominators and pin, so the two brief commands of SG-G3 and SG-G5 exit
  64;  both legs were read from the whole battery and from the leg bodies.
- SG-D26 The whole battery FAILs on CARRY, because Stage G grows
  lib/global.ml and the carried expectation at dev/CARRIED.md:14 still
  reads 164.  That file is out of the brief's scope, so it was left
  untouched and the user rules.
- SG-D27 The battery M0-TIME FAIL the builder saw is a load artefact and
  not a regression;  the bound was not moved.

### Findings

- F1, info, closed as a brief erratum.  The SG-G3 and SG-G5 commands of
  the brief do not exist:  `zsh dev/gates.sh --leg R0-COUNT` and
  `--leg SUITE-KERNEL` both print `gates: unknown leg NAME`, exit 64
  (dev/gates.sh:257-266).  The judge reproduced both and read the two
  legs from the whole battery and from the leg bodies instead.  A later
  stage cites `zsh dev/r0-count.sh` and `_build/default/test/main.exe
  test`, or Stage L adds the two leg names.
- F2, medium, open for the user.  The whole battery ends in `GATES-FAIL`,
  exit 1, on the row `CARRY lib/global.ml diff=196 expected=164
  header=OK FAIL`.  The growth is the family table this stage adds, so
  the code is right and the expectation is stale.  dev/CARRIED.md:14 is
  outside the brief's deliverables, so no agent moved it.  The user
  rules:  move the count at dev/CARRIED.md:14 from 164 to 196 and extend
  the paragraph at :26-29 with the family table, in the Stage G commit,
  or defer the row to Stage L.  The tree does not pass its own battery
  until that ruling lands.
- F3, info, closed.  The builder read `FAIL M0-TIME median_ms=182.209
  bound_ms=150` at the load average 12.77.  The judge read
  `PASS M0-TIME median_ms=93.984 bound_ms=150` in the battery and three
  more PASS readings of 91.806, 92.000 and 98.854 ms at the load average
  14.34.  The reading is a load artefact.  The bound stays 150.
- F4, low, reported.  The number SG-D13 names two decisions:  the brief's
  own last bullet at 3.11 and builder 1's first.  The brief text says the
  builders continue after SG-D12 while its list ends at SG-D13.  Both
  texts are kept above.  A later brief starts its builder range one
  number above the last bullet it writes.

### Hand-off notes for Stage H

Stage H brings the fibered Elim branch and motive rules and the
subsingleton criterion (M1-PLAN.md:198).  It reads three things this
stage leaves ready.

- The elimination fields of the SMu pack.  lib/rules.ml:1113 holds
  `elim_elim`, :1097 holds the BElim beta arm and both answer
  `Error (Error.Not_yet mu_elim_word)`, with the word at rules.ml:957,
  `an elimination at a mu shape arrives at M1 Stage H` (SG-D9, SG-D19).
  Stage H replaces those two sites and no other.  `elim_sec` at :1115,
  `elim_out` at :1116, `form_ran` at :1111 and `ran_lvl` at :1133 keep
  the M2 word `a right former at a mu shape arrives at M2`, because a
  coinductive section is SNu's job (SG-D4).
- The family record accessor.  lib/rules.ml:967 holds `mu_family`, the
  one accessor of brief 3.3, which answers the record of
  lib/positivity.ml:47-55 and refuses a Complete family whose stored
  positivity verdict is false (SG-D2, SG-D17).  The motive rules read
  `f_params`, `f_indices`, `f_level` and `f_ctors` through it, and
  `Positivity.ctor_of` at positivity.ml:59 reads one constructor.  A
  second reader would put a family lookup in check.ml and turn SG-G2 red.
- The SPEC.md status cell.  The named rule row moved with the file, from
  the brief's :208 to SPEC.md:218 today, and still reads the milestone
  M1.  Stage H turns that cell to present and moves
  `named rules present 2: proof-irrelevance literal-fast-path` at
  SPEC.md:155 to three, in the same commit as the criterion, so R0-COUNT
  is never red on a committed tree.  The M1 obligation row at SPEC.md:468
  moves with it.
- `Positivity.self_rec` at positivity.ml:152 stores the flag part one of
  the criterion asks for (A1), so Stage H reads it and never recomputes.

### Addendum, ruling round 2026-09-06 (c)

Applied after the judge verdict CHECK, on the user ruling of 2026-09-06
recorded in RATIFICATIONS.md, round (c).  It resolves finding F2.

- SG-D28 The CARRY row for lib/global.ml moves from 164 to 196 in this
  commit (dev/CARRIED.md:14, paragraph at :26-31), because Stage G adds
  the family record and the families table at lib/global.ml:61-79.  The
  row moves in the form of the quantity.ml row of Stage B.
- D-M1-7 amended once by the user: kernel_bound moves from 3000 to 4000
  at dev/trusted-lines.sh:31, encoder_bound stays 600, the believed list
  stays the ten files of SG-G6.  No stage moves a bound again.
- Reruns after the two edits, load average 11.77 14.46 14.22:
  `CARRY lib/global.ml diff=196 expected=196 OK` and `CARRY-OK`
  `TRUSTED-LINES kernel=2995/4000 encoder=216/600 OK`
  `GATES-OK` with every leg line: PASS BUILD, PASS CARRY, PASS R0-COUNT,
  PASS R0-AUDIT, PASS SUITE-KERNEL, PASS SUITE-WASM, PASS ENCODER-SUBSET,
  PASS AXIOMS, PASS M0-E2E main=521, PASS M0-TIME median_ms=94.423
  bound_ms=150, PASS M0-RATIO ratio=0.243, PASS TRUSTED-LINES,
  PASS DENOMINATORS, PASS HOUSE, PASS PIN sha=8cf0b8b
- dev/M1-MUTATION-LOG.md is unchanged by this addendum.

### Stage G review fixes (2026-09-06)

Four declaration checks now run before a family is installed.  A family
name must be fresh, every field must obey the declared universe bound,
the result parameters must be the original parameter variables in
order, and each result index must check against the dependent index
telescope under the parameters and fields.  The elaborator retains the
result parameters in `Check.ctor_decl` so the kernel can check them.
Constructor installation also refuses a family that is already complete
or builtin.  These checks correct the initial declaration-validation
claims above; introduction still checks result-index conversion.

Seven negative fixtures cover family redeclaration, duplicate mutual
members, oversized fields, ill-typed and unbound indices, and changed
or reordered parameters.  The positive `mu-constructor-scopes` fixture
covers parameter variables under fields, a parameter-dependent index,
dependent result indices, and a field at its allowed universe bound.

Validation ran on the fixed source copy at
/private/tmp/kanon-stage-g-fixes-dx26e5r5.  Its vendor/tot link reads the
existing pinned checkout; it writes no vendor file.  The initial run
lacked that link and failed CARRY and PIN.  With the link present, the
full unmodified `zsh dev/gates.sh` battery exited 0 with 15 PASS lines
and `GATES-OK`.  The log is /private/tmp/kanon-stage-g-fixes-gates.log.

- BUILD: `OK build: 0 errors, 0 warnings`.
- Kernel suite: `PARSE-OK 73/73`, `CHECK-OK 51/51`, `ERASE-OK 51/51`,
  `NEG-OK 21/21`, `ERASE-NEG-OK 1/1`, `KNEG-OK 2/2`, `SUITE-KERNEL OK`.
- WebAssembly suite: `WASM-OK 15/15`, `SUITE-WASM OK`.
- `TRUSTED-LINES kernel=3051/4000 encoder=216/600 OK`.
- Four independent mutations built successfully and then failed the
  kernel suite at the corresponding new negative fixtures.  Their
  exact failures are recorded in M1-MUTATION-LOG.md.

The bounds and existing gate implementations are unchanged by these
fixes.  Source, fixtures and logs are staged for the user to commit.

## Stage H (2026-09-06)

### Deliverables

The line counts are read on ROOT after the build of SH-G1.

| file | lines | note |
| --- | --- | --- |
| lib/rules.ml | 1496 | +312 -9;  the fibered Elim, the branch and motive rules, the criterion at mu_zero_eliminable:993 |
| lib/conv.ml | 416 | +33 -7;  step one gains named rule 2 through the pack field, step three gains the SMu head |
| SPEC.md | 510 | +44 -4;  the count row :173, the status cell :236, the rule text of section 2.1 and section 5 |
| surface/syntax.ml | 268 | +47 -13;  mo_ind, mo_idx, BrLeg, BrCtor, the field binder |
| surface/parser.ml | 503 | +67 -22;  the index clause, the constructor keyed branch row, parse_fields |
| surface/elab.ml | 1008 | +208 -16;  elab_coll_case and elab_mu_case, the family and constructor reads |
| test/fixtures/mu-prop-large-elim.kan | 14 | new;  a large elimination out of a one constructor Prop family |
| test/fixtures/mu-empty-large-elim.kan | 12 | new;  ex falso out of the empty family |
| test/fixtures/mu-indexed.kan | 33 | +11;  the Stage G positive extended by read_index, the SH-M3 killer |
| test/neg/mu-large-elim-nonsub.kan | 12 | new;  one argument at quantity Many, refused by part two |
| test/neg/mu-large-elim-selfrec.kan | 14 | new;  one self recursive argument at Zero, refused by part three |
| test/neg/mu-missing-branch.kan | 11 | new;  one constructor unanswered |
| test/neg/mu-no-motive.kan | 11 | new;  an Elim at an SMu scrutinee with no motive |
| test/neg/mu-motive-wrong-family.kan | 13 | new;  a motive built for a sibling family |
| test/golden/mu-prop-large-elim.checked | 1 | new;  the checked text, with .erased at 1 line |
| test/golden/mu-empty-large-elim.checked | 2 | new;  the checked text, with .erased at 2 lines |
| test/golden/mu-indexed.checked | 1 | +1;  the row read_index, with .erased at +1 |
| the five .err sidecars | 1 each | new;  the exact expected error line of each negative |

The surface widening of brief 3.8 is 322 insertions and 51 deletions
over the three surface files.  No kernel file joined the believed list,
so SH-D15 holds and the two budgets stay at 4000 and 600.

### Gates

The judge reran SH-G1 to SH-G7 on ROOT at 2026-09-06 06:53, after
`zsh dev/dune.sh clean`, at the load average 10.13 10.10 11.76.  Each
line below is the exact final line of the command, with its exit code.

- SH-G1 BUILD.  `zsh dev/dune.sh clean` exit 0, then
  `zsh dev/dunecho.sh build` printed `OK build: 0 errors, 0 warnings`,
  exit 0.
- SH-G2 SUITE-KERNEL.  The leg name is not an accepted argument of
  dev/gates.sh (H-F7), so the whole battery ran once under SH-D16 and
  printed `PASS SUITE-KERNEL`.  The direct run
  `_build/default/test/main.exe test` printed `PARSE-OK 80/80`,
  `CHECK-OK 53/53`, `ERASE-OK 53/53`, `NEG-OK 26/26`,
  `ERASE-NEG-OK 1/1`, `KNEG-OK 2/2` and `SUITE-KERNEL OK`, exit 0.
- SH-G3 R0-COUNT.  Same spelling rule.  The battery printed
  `PASS R0-COUNT`.  `_build/default/bin/kanon.exe spec-count` printed
  `named rules present 3: proof-irrelevance subsingleton-large-elimination
  literal-fast-path`, with `named rules declared 3` and
  `shapes admitted 3: SPi SColl SMu` unchanged, exit 0.
- SH-G4 R0-AUDIT.  `zsh dev/r0-audit.sh` printed `R0-AUDIT OK`, exit 0.
- SH-G5 TRUSTED-LINES.  `zsh dev/trusted-lines.sh ROOT` printed
  `TRUSTED-LINES kernel=3380/4000 encoder=216/600 OK`, exit 0.  The
  kernel reading is 3380 and the encoder reading is 216.
- SH-G6 HOUSE.  `zsh dev/house.sh ROOT` printed `HOUSE no-exception OK`,
  `HOUSE no-mutable-state OK`, `HOUSE one-catch-site OK`,
  `HOUSE no-bool-match OK`, `HOUSE no-em-dash OK` and `HOUSE OK`,
  exit 0.
- The whole battery `zsh dev/gates.sh` printed `GATES-OK`, exit 0, with
  the 15 PASS lines, `PASS M0-TIME median_ms=88.489 bound_ms=150` and
  `PASS PIN sha=8cf0b8b`.  The bound of M0-TIME was not moved.
- SH-G7 ELIM-SUITE, the stage local leg of brief 3.10 over the seven
  fixtures of 3.9.  The two positives are read against both golden files
  and the five negatives against their sidecars, with the error kind
  stripped at the first `: ` (SH-D47, SH-D48).  The seven lines:
  `ELIM-SUITE POS mu-prop-large-elim exit=0 GOLDEN-MATCH` and its
  `erased exit=0 ERASED-MATCH`;
  `ELIM-SUITE POS mu-empty-large-elim exit=0 GOLDEN-MATCH` and its
  `erased exit=0 ERASED-MATCH`;
  `ELIM-SUITE NEG mu-large-elim-nonsub exit=1 SIDECAR-MATCH line=a large
  elimination out of a proposition needs a subsingleton family at Box`;
  `ELIM-SUITE NEG mu-large-elim-selfrec exit=1 SIDECAR-MATCH line=a large
  elimination out of a proposition needs a subsingleton family at Acc`;
  `ELIM-SUITE NEG mu-missing-branch exit=1 SIDECAR-MATCH line=the
  elimination of Two has no branch at cb`;
  `ELIM-SUITE NEG mu-no-motive exit=1 SIDECAR-MATCH line=an elimination
  at a mu shape needs a motive`;
  `ELIM-SUITE NEG mu-motive-wrong-family exit=1 SIDECAR-MATCH line=the
  motive is built for Beta and the scrutinee is at Alpha`.  The leg
  exited 0.
- SH-G8 LOGS.  dev/M1-BUILD-LOG.md holds `## Stage H (2026-09-06)`
  exactly once and dev/M1-MUTATION-LOG.md holds `## Stage H` exactly
  once.  The Stage G sections of both files are unchanged, because both
  sections are appended after the last line of the file.
  `git diff --stat -- dev/M0-BUILD-LOG.md dev/MUTATION-LOG.md` is empty
  and porcelain lists only Stage H paths.

### MEASURE table

The judge ran the whole battery `zsh dev/gates.sh` once on ROOT at
2026-09-06 06:53, at the load average 11.00 10.29 11.81.  The rows are
copied from that run.  No timed leg failed, so no leg was rerun.

```
MEASURE BUILD tier=SLOW elapsed_ms=65.316 exit=0
MEASURE CARRY tier=MED elapsed_ms=673.347 exit=0
MEASURE R0-COUNT tier=FAST elapsed_ms=286.397 exit=0
MEASURE R0-AUDIT tier=FAST elapsed_ms=23.760 exit=0
MEASURE SUITE-KERNEL tier=SUITE elapsed_ms=195.150 exit=0
MEASURE SUITE-WASM tier=SUITE elapsed_ms=1604.048 exit=0
MEASURE ENCODER-SUBSET tier=FAST elapsed_ms=42.962 exit=0
MEASURE AXIOMS tier=MED elapsed_ms=20.601 exit=0
MEASURE M0-E2E tier=SLOW elapsed_ms=201.379 exit=0
MEASURE M0-TIME tier=SLOW elapsed_ms=770.852 exit=0
MEASURE M0-RATIO tier=SLOW elapsed_ms=259.539 exit=0
MEASURE TRUSTED-LINES tier=FAST elapsed_ms=20.652 exit=0
MEASURE DENOMINATORS tier=MED elapsed_ms=36.733 exit=0
MEASURE HOUSE tier=MED elapsed_ms=73.406 exit=0
MEASURE PIN tier=FAST elapsed_ms=59.454 exit=0
```

The two bench rows and the ratio row of the same run:

```
BENCH m0_e2e median_ms=88.489 min_ms=85.850 max_ms=256.346 runs=5
PASS M0-TIME median_ms=88.489 bound_ms=150
BENCH m0_ratio median_ms=28.426 min_ms=28.212 max_ms=28.780 runs=5
MEASURE M0-RATIO kanon_ms=28.426 tot_ms=103.662 ratio=0.274
PASS M0-RATIO ratio=0.274
```

### Decisions

SH-D1 to SH-D16 are pinned by the Stage H brief section 3.11.  SH-D17 to
SH-D45 are the builders'.  SH-D46 to SH-D50 are the verifier's and the
fixer's.  SH-D51 to SH-D53 are the fix round's, which numbered them
SH-D20 to SH-D22 and collided with builder 1;  the judge renumbers them
here and states the renumbering for the user.

- SH-D1 The criterion lives in lib/rules.ml and conv.ml reads it through
  the pack, so R0-AUDIT stays green.
- SH-D2 The criterion is ported part for part, each part citing its pin
  line, and never restated in kanon words.
- SH-D3 The empty family passes part one and gets its ex falso.
- SH-D4 A self recursive family never gets a large elimination.
- SH-D5 An Elim at an SMu scrutinee with e_motive None is an error
  inside the pack, never at the dispatch.
- SH-D6 m_ind is Some n and is checked equal to the scrutinee family.
- SH-D7 m_idx has the length of the family index telescope and a branch
  body is checked at m_body instantiated at that constructor.
- SH-D8 A missing branch and a repeated branch are both errors, read in
  declaration order.
- SH-D9 A branch leg binds one binder per field at the field quantities;
  Lan SPi keeps ALeg 0 with two binders.
- SH-D10 The SPEC.md count and the status cell move in this commit.
- SH-D11 The section 10 obligation row is not edited here.
- SH-D12 The seven fixtures enter as .kan files through the surface.
- SH-D13 Every mutation runs on a fresh copy and ROOT is never mutated.
- SH-D14 The plan's SH-M1b is carried as SH-M6.
- SH-D15 No kernel file joins the believed list and the budgets do not
  move.
- SH-D16 A leg dev/gates.sh does not accept as an argument is read from
  one whole run of the battery.
- SH-D17 The criterion reaches conv.ml through one new pack field,
  `subsingleton : 'c ops -> 'c -> Value.t Shape.t -> (bool, Error.t)
  result` at lib/rules.ml:180, so conv.ml names no shape.
- SH-D18 Every non recursive pack answers that field with
  `no_subsingleton`, which is `Ok false`, at spi_pack and coll_pack.
- SH-D19 `mu_subsingleton` (lib/rules.ml:1035) answers `Ok false` when
  as_vmu fails or the family lookup errors, so conversion never turns a
  missing family into a hard error.
- SH-D20 The pin criterion is ported arm for arm at
  `mu_zero_eliminable` (lib/rules.ml:993), Provisional at :996 for pin
  :225, Builtin at :998 for :226, `Complete []` at :1000 for :227,
  `Complete [c]` at :1002 for :228 with part two at :1006 and part three
  at :1011, and `Complete (_ :: _ :: _)` at :1013 for :233.
- SH-D21 The family record is read through one reader, `mu_family`
  (lib/rules.ml:1018) wrapping ops.o_family, which is Global.find_family
  (lib/global.ml:74);  the constructor is read with Positivity.ctor_of.
- SH-D22 The large elimination refusal is Error.Universe carrying
  `mu_large_word` (lib/rules.ml:980) and the family name.
- SH-D23 `mu_large` (lib/rules.ml:1233) admits at once when the family
  level is not zero and when the motive level is zero, and only then
  asks the criterion, which is the pin order at check.ml:1370.
- SH-D24 The motive level is measured under the index binders and the
  self binder at Quantity.Zero, so the motive is never checked at a made
  up universe.
- SH-D25 The old `mu_elim_word` is dead and deleted, replaced by
  `mu_motive_word` (lib/rules.ml:975) and `mu_large_word` (:980).
- SH-D26 In arguments keep the untyped pairwise comparison in conv.ml;
  the field types are enforced at the introduction site.
- SH-D27 conv.ml step one is is_prop, then one o_whnf, then
  subsingleton_step, then eta_step, so the head is computed once.
- SH-D28 conv.ml branch_addr gains a third arm that compares
  Term.as_actor, so no shape name enters conv.ml.
- SH-D29 `mu_beta` reduces BElim at the branch whose ACtor key equals
  the constructor of the Value.VIn, at `List.rev_append args env`;  BOut
  keeps the Ran refusal.
- SH-D30 Branch coverage is read in the declaration order of f_ctors and
  missing, repeated and unknown each carry their own word
  (lib/rules.ml:1277, :1281, :1289).
- SH-D31 Each branch checks binder count then binder quantity field by
  field against c_args, and a later field type sees the earlier binders.
- SH-D32 The elimination result is the motive body at
  `self :: List.rev_append idx env` (lib/rules.ml:1197), and the
  scrutinee value is computed after the branches are checked.
- SH-D33 Verification beyond the two required gates ran only on a copy
  made with rsync, built with its own dev/dunecho.sh.
- SH-D34 SPEC.md:173 alone carries the count move and reads
  `named rules present 3: proof-irrelevance
  subsingleton-large-elimination literal-fast-path`.
- SH-D35 The status cell at SPEC.md:236 moves from `M1` to `present` and
  names conv.ml step one through the `subsingleton` field, keeping the
  pin citation.
- SH-D36 The rule text lands in two blocks, the fibered Elim rules at
  SPEC.md:47-63 and the three criterion parts at :239-257.
- SH-D37 The section 10 obligation row at SPEC.md:508 keeps `M1` and is
  untouched;  section 11 gains :467 and :480 and section 8 gains :302.
- SH-D38 The surface motive gains `mo_ind` (surface/syntax.ml:46) and
  `mo_idx` (:47) and no new form, so every M0 fixture keeps its text.
- SH-D39 The surface branch becomes a sum, `BrLeg` (surface/syntax.ml:65)
  and `BrCtor` (:66), so no branch carries both keys.
- SH-D40 A field binder carries `fd_q` (surface/syntax.ml:55) and
  `fd_name` (:56) only, because the field type is read from the record.
- SH-D41 The index clause is read by `parse_index_clause`
  (surface/parser.ml:168), which gives the tokens back unread when it
  does not open with `in`, so it cannot collide with a let.
- SH-D42 `parse_fields` (surface/parser.ml:215) and `parse_names` (:178)
  are total and stop at the first token that is not a field or a name.
- SH-D43 The branch bar takes a second row at surface/parser.ml:204 and
  the failure word at :207 becomes `expected a leg number or a
  constructor name after '|'`.
- SH-D44 The elaborator splits on the shape of the scrutinee type,
  `elab_coll_case` (surface/elab.ml:552) and `elab_mu_case` (:635), with
  :611 and :724 refusing the other form.
- SH-D45 The family and the constructor are read in the surface only,
  Global.find_family (surface/elab.ml:639) and Positivity.ctor_of (:731),
  so conv.ml still holds no family lookup.
- SH-D46 The verifier changed no byte of ROOT, because the whole battery
  was green on the tree as found.
- SH-D47 A `.err` sidecar is measured against `Error.message`, which is
  what test/main.ml:107-109 compares, with the error kind stripped at the
  first `: `, and never against the prefixed CLI line.
- SH-D48 The two positives are measured against both golden files,
  `check --print` against .checked and `check --erased` against .erased.
- SH-D49 SH-D16 governs SH-G2 and SH-G3, whose leg names dev/gates.sh
  does not accept, so the whole battery ran once and the two PASS lines
  are quoted from that run.
- SH-D50 SH-D15 stands, because deliverable 3.4 landed in lib/rules.ml,
  an already believed file, so dev/trusted-lines.sh is not edited.
- SH-D51 The SH-M3 killer is the Stage G fixture
  test/fixtures/mu-indexed.kan extended by one definition, not an eighth
  fixture, because M1-PLAN.md:200 names that file.  PARSE-OK stays 80/80
  and CHECK-OK and ERASE-OK go from 52/53 to 53/53.
- SH-D52 The elimination sits under a let inside a definition at Type 0,
  because Erase.decl (lib/erase.ml:1101-1104) drops a definition whose
  declared type is not a runtime type, so the interim erasure word stays
  pinned by test/erase-neg/mu-erase.kan alone.
- SH-D53 The motive body is `V i` and not an index free type, so SH-M3
  is killed by the evaluator, which answers Unbound
  (lib/eval.ml:26-31), and not by a golden text difference.

### Findings

- SH-F-HIGH-1, high, closed by the fix round.  SH-M3 was not killed:
  the index instantiation of `mu_result` (lib/rules.ml:1197) had no
  fixture, because test/fixtures/mu-indexed.kan held no elimination and
  no .kan file in the tree eliminated an indexed family, so the copy
  with the index arguments dropped still printed `SUITE-KERNEL OK`.  The
  fix adds `read_index` at test/fixtures/mu-indexed.kan:22, whose motive
  body is `V i`, with the two goldens filled.  The judge reran the
  mutation on judge-m3 and it now prints `CHECK mu-indexed FAIL:
  unbound: de Bruijn index 1 is outside the environment`, `CHECK-OK
  52/53` and `SUITE-KERNEL FAIL`.
- SH-F-LOW-1, low, open for the user.  The missing branch refusal is
  enforced twice, at `mu_cover` (lib/rules.ml:1277) and again at the
  `List.find_opt` of `mu_branch` (:1309-1312), and the second site is
  unreachable on every real path because `mu_cover` runs first at
  mu_elim_elim:1367.  The fix round left it, because the smallest honest
  edit is four lines plus a helper and the one line rule does not allow
  it.  The judge reproduced the redundancy: SH-M2 is killed only when
  both sites are disabled.

### Hand-off notes for Stage I

Stage I brings the structural order, the totality certificate and the
translation of a recursive definition into one Elim (M1-PLAN.md:206).
It reads five things this stage leaves ready.

- The beta rule the translation feeds.  `mu_beta` at lib/rules.ml:1380
  reduces `BElim` at :1383 by the branch whose ACtor key equals the
  constructor of the value, at `List.rev_append args env` (:1392).
  `BOut` keeps the M2 Ran refusal at :1382 (SH-D29).
- The branch leg shape a recursive leg binder extends.  `mu_branch` at
  lib/rules.ml:1297 binds one binder per field, checks the binder count
  and then the field quantity against `c_args` (SH-D31), and the target
  of each branch is `mu_result` at :1345.
- The one family accessor.  `mu_family` at lib/rules.ml:1018 wraps
  ops.o_family, which is Global.find_family at lib/global.ml:74, and it
  stays the only reader (SH-D21).  A second reader outside that chain
  breaks R0-AUDIT and SG-D2.
- The criterion site of SH-D1.  `mu_zero_eliminable` at
  lib/rules.ml:993, read by the pack field `subsingleton` (:180) and by
  `mu_large` (:1233).  Stage I adds no part to it, because the pin has
  three (SH-D2, SH-D20).
- The obligation row Stage I marks discharged.  SPEC.md:509, the
  structural recursion certificate row, which the plan cites as
  SPEC.md:459 and which the Stage H edits moved to :509.  The
  subsingleton obligation row at SPEC.md:508 keeps its milestone `M1`
  and is Stage L's mark (SH-D11, SH-D37).

Open for Stage I: the surface `case` of brief 3.8 elaborates through
`elab_mu_case` at surface/elab.ml:635 and calls no guard, so the caller
of `Totality.guard` is still absent (SPEC.md:509).

### Stage H conversion review fix (2026-09-06)

The review reproduced a closed cast from `Nat` to `Nat -> Nat` using
a `Type 1` family with one erased type field.  SH-D27's conversion
shortcut applied the large elimination criterion without checking the
family universe, so two different type payloads converted.

`mu_subsingleton` now requires the family level to be `Prop` before
answering true.  Type families retain the remaining conversion rules.
The large elimination check keeps its existing criterion.  The comments
in conv.ml and SPEC.md record the distinction.

The new negative `mu-type-erased-cast` carries the closed reproducer.
The unfixed Stage H checker accepts it with exit 0; the fixed checker
rejects its cast with the expected type mismatch.  Validation on a
scratch copy: build with zero errors and warnings, `SUITE-KERNEL OK`
(81 parses, 53 positive checks, 53 erasures, 27 negatives),
`SUITE-WASM OK` (15/15), HOUSE, R0-COUNT, R0-AUDIT and TRUSTED-LINES
all pass.  The existing Prop and empty-family large elimination
fixtures still pass.  The full runtime gate battery was not rerun.

## Stage I (2026-09-06)

### Deliverables

The line counts are read on ROOT after the build of SI-G1.

| file | lines | note |
| --- | --- | --- |
| lib/order.ml | 581 | new;  the status type at :49, the certificate record at :87, passes at :280, certify at :460, translate at :538 |
| lib/totality.ml | 155 | +105 -89;  guard_group at :127, guard at :151 as the group of one, the budget backstop at :32 |
| lib/error.ml | 82 | +13;  the arm `Termination` at :36, termination_msg at :45, read at :64 and :82 |
| surface/elab.ml | 1145 | +137;  elab_rec_group at :962, the guard call at :1004, Order.translate at :1029, rec_arg at :1040 |
| surface/parser.ml | 544 | +43 -2;  the `def rec` row at :422, parse_rec_group at :459, the member row at :467 |
| surface/syntax.ml | 291 | +23;  rec_def at :93 and DRec at :136 |
| surface/token.ml | 134 | +6;  KRec at :70 and its describe row at :126 |
| surface/lexer.ml | 143 | +3;  the `rec` keyword row at :57 |
| test/main.ml | 361 | +83 -11;  guarded_self at :163, the KNEG row at :216-243, the name list at :333 |
| SPEC.md | 516 | +1 -1;  the obligation row at :515 marked discharged |
| dev/trusted-lines.sh | 78 | +4;  lib/order.ml at :50 with the two line reason at :47-49 |
| test/neg/mu-nonstructural.kan | 15 | new;  a self call at an argument no chain of legs makes smaller |
| test/neg/mu-rec-nondecreasing.kan | 15 | new;  a self call at the scrutinee itself, the SI-M2 killer |
| test/neg/mu-rec-sibling-position.kan | 18 | new;  a sibling call that decreases at another position, the SI-M3 killer |
| test/neg/mu-rec-guard-order.kan | 22 | new;  the SI-G6 fixture, a well typed Elim whose certificate is refused |
| test/erase-neg/mu-rec-direct.kan | 17 | new;  the direct positive, moved by the SI-D12 split |
| test/erase-neg/mu-rec-indexed.kan | 24 | new;  the indexed positive, moved by the SI-D12 split |
| test/erase-neg/mu-rec-mutual.kan | 24 | new;  the mutual positive, moved by the SI-D12 split |
| the seven .err sidecars | 1 each | new;  four termination lines and three interim erasure lines |

The surface widening of brief 3.7 is 212 insertions and 2 deletions over
the five surface files elab.ml, parser.ml, syntax.ml, token.ml and
lexer.ml.  lib/order.ml joins the believed list and the two budgets stay
at 4000 and 600 (SI-D15).  No file under test/fixtures was added, which
is the split of SI-D12.

### Gates

The judge reran SI-G1 to SI-G7 on ROOT at 2026-09-06 11:59, after
`zsh dev/dune.sh clean`, at the load average 19.97 22.47 21.49.  Each
line below is the exact final line of the command, with its exit code.

- SI-G1 BUILD.  `zsh dev/dune.sh clean` exit 0, then
  `zsh dev/dunecho.sh build` printed `OK build: 0 errors, 0 warnings`,
  exit 0.
- SI-G2 SUITE-KERNEL.  The leg name is not an accepted argument of
  dev/gates.sh (I-F15), so the whole battery ran once under SI-D17 and
  printed `PASS SUITE-KERNEL`.  The direct run
  `_build/default/test/main.exe test` printed `PARSE-OK 88/88`,
  `CHECK-OK 53/53`, `ERASE-OK 53/53`, `NEG-OK 31/31`,
  `ERASE-NEG-OK 4/4`, `KNEG-OK 2/2` and `SUITE-KERNEL OK`, exit 0.
  The Stage H counts of 53 checks and 53 erasures are unchanged;  the
  parses rise from 80 to 88, the negatives from 26 to 31 and the erasure
  negatives from 1 to 4.
- SI-G3 R0-AUDIT.  `zsh dev/r0-audit.sh` printed `R0-AUDIT OK`, exit 0.
- SI-G4 TRUSTED-LINES.  `zsh dev/trusted-lines.sh ROOT` printed
  `TRUSTED-LINES kernel=3982/4000 encoder=216/600 OK`, exit 0.  The
  kernel reading is 3982 over the eleven believed files and the encoder
  reading is 216.  The headroom under the bound is 18 lines.
- SI-G5 HOUSE.  `zsh dev/house.sh ROOT` printed `HOUSE no-exception OK`,
  `HOUSE no-mutable-state OK`, `HOUSE one-catch-site OK`,
  `HOUSE no-bool-match OK`, `HOUSE no-em-dash OK` and `HOUSE OK`,
  exit 0.
- SI-G6 GUARD-FIRST.  `_build/default/bin/kanon.exe check
  test/neg/mu-rec-guard-order.kan` printed
  `termination: recursive definition grow failed the structural
  termination guard`, exit 1, which is the line of the sidecar
  test/neg/mu-rec-guard-order.err and never a type error of the
  translated form.
- SI-G7 REC-SUITE, the stage local leg of brief 3.8.  The three
  positives check and the three negatives are refused with the exact
  line of their sidecar.  The six lines, each from
  `_build/default/bin/kanon.exe check`:
  `test/erase-neg/mu-rec-direct.kan exit=0`, no output;
  `test/erase-neg/mu-rec-indexed.kan exit=0`, no output;
  `test/erase-neg/mu-rec-mutual.kan exit=0`, no output;
  `test/neg/mu-nonstructural.kan exit=1` line `termination: recursive
  definition spin failed the structural termination guard`;
  `test/neg/mu-rec-nondecreasing.kan exit=1` line `termination:
  recursive definition same failed the structural termination guard`;
  `test/neg/mu-rec-sibling-position.kan exit=1` line `termination:
  recursive definition left failed the structural termination guard`.
  The checked half of each positive is read by the suite row
  `ERASE-NEG mu-rec-direct OK`, `ERASE-NEG mu-rec-indexed OK` and
  `ERASE-NEG mu-rec-mutual OK`, which fails unless the file elaborates,
  guards, translates and checks.  The erased half is the interim word of
  SI-D12 and no .erased golden was written.
- The whole battery `zsh dev/gates.sh` printed `GATES-OK`, exit 0, with
  the 15 PASS lines, `PASS M0-TIME median_ms=121.153 bound_ms=150` and
  `PASS PIN sha=8cf0b8b`.  `PASS R0-COUNT` is green with no SPEC.md
  count edit (SI-D14) and `PASS CARRY` is green with no CARRIED.md row
  moved (SI-D36).  The bound of M0-TIME was not moved and no timed leg
  failed, so no leg was rerun.
- SI-G8 LOGS.  dev/M1-BUILD-LOG.md holds `## Stage I (2026-09-06)`
  exactly once and dev/M1-MUTATION-LOG.md holds `## Stage I` exactly
  once.  The Stage G and the Stage H sections of both files are
  unchanged, because both sections are appended after the last line of
  the file.  `git diff --stat -- dev/M0-BUILD-LOG.md dev/MUTATION-LOG.md`
  is empty and the porcelain lists only Stage I paths.

### MEASURE table

The judge ran the whole battery `zsh dev/gates.sh` once on ROOT at
2026-09-06 11:59, at the load average 19.97 22.47 21.49 before the run
and 19.01 22.23 21.41 after it.  The rows are copied from that run.  No
timed leg failed, so no leg was rerun.

```
MEASURE BUILD tier=SLOW elapsed_ms=210.356 exit=0
MEASURE CARRY tier=MED elapsed_ms=467.837 exit=0
MEASURE R0-COUNT tier=FAST elapsed_ms=69.544 exit=0
MEASURE R0-AUDIT tier=FAST elapsed_ms=32.143 exit=0
MEASURE SUITE-KERNEL tier=SUITE elapsed_ms=71.944 exit=0
MEASURE SUITE-WASM tier=SUITE elapsed_ms=3085.572 exit=0
MEASURE ENCODER-SUBSET tier=FAST elapsed_ms=55.046 exit=0
MEASURE AXIOMS tier=MED elapsed_ms=27.062 exit=0
MEASURE M0-E2E tier=SLOW elapsed_ms=266.326 exit=0
MEASURE M0-TIME tier=SLOW elapsed_ms=819.407 exit=0
MEASURE M0-RATIO tier=SLOW elapsed_ms=320.932 exit=0
MEASURE TRUSTED-LINES tier=FAST elapsed_ms=26.044 exit=0
MEASURE DENOMINATORS tier=MED elapsed_ms=41.689 exit=0
MEASURE HOUSE tier=MED elapsed_ms=84.616 exit=0
MEASURE PIN tier=FAST elapsed_ms=86.774 exit=0
```

The two bench rows and the ratio row of the same run:

```
BENCH m0_e2e median_ms=121.153 min_ms=112.977 max_ms=139.639 runs=5
PASS M0-TIME median_ms=121.153 bound_ms=150
BENCH m0_ratio median_ms=31.649 min_ms=29.921 max_ms=36.071 runs=5
MEASURE M0-RATIO kanon_ms=31.649 tot_ms=103.662 ratio=0.305
PASS M0-RATIO ratio=0.305
```

### Decisions

SI-D1 to SI-D18 are pinned by the Stage I brief section 3.12.  SI-D19 to
SI-D38 are raised by the builders during the build.

- SI-D1 The order is subterm only, syntactic and checked, and no sized
  and no lexicographic order enters (D-M1-4).
- SI-D2 lib/order.ml is a new kernel file and each function cites the
  pin line it mirrors.
- SI-D3 The certificate is a returned record and never a driver flag.
- SI-D4 The guard keeps the signature of I-F7.
- SI-D5 An argument that is an application is never guarded (ruling R1).
- SI-D6 The refusal is the one arm `Termination of string` with the pin
  message, and every .err sidecar pins that line.
- SI-D7 One order over the group;  the direct case is the group of one.
- SI-D8 The production is `def rec` with `and` joining the members.
- SI-D9 The guard is called at the elaborator declaration row, after the
  body is elaborated and before the translation.
- SI-D10 The translation builds one Elim at the Stage H fibered form and
  adds no term constructor and no motive field.
- SI-D11 test/main.ml is edited for the KNEG row alone.
- SI-D12 A recursive positive whose erased form is refused lands under
  test/erase-neg with the interim word.
- SI-D13 The SPEC.md obligation row is marked discharged at Stage I.
- SI-D14 No R0 count moves and R0-COUNT stays green.
- SI-D15 lib/order.ml joins the believed list and no budget moves.
- SI-D16 Every mutation runs on a fresh copy and ROOT is never mutated.
- SI-D17 A leg that dev/gates.sh does not accept is read from one full
  battery run (erratum SG-D25).
- SI-D18 This brief adds SI-G7 and SI-G8 beyond the plan's six gate ids
  and carries SI-B1 as the lexicographic blocker.
- SI-D19 lib/totality.ml keeps `guard ?budget globals name ty body` at
  its M0 signature (totality.ml:151-155) and is a thin reader of the
  certificate:  it is guard_group at the group of one, so the direct
  case and the mutual case cannot drift apart.
- SI-D20 totality.ml exports `guard_group ?budget globals members`
  (totality.ml:127) so the caller hands the same value to
  Order.translate and the order is computed once.
- SI-D21 The budget stays a backstop with its M0 text unmoved
  (budget_msg at totality.ml:32, Error.Budget_exhausted at :41), and the
  M0 seek walk becomes a name free walk that polls once per node before
  the certificate runs, because lib/order.ml carries no budget.
- SI-D22 The M0 milestone word and its refusal arm leave lib/totality.ml,
  so guard answers `Ok (Some k)`, `Ok None` or
  `Error (Error.Termination name)` and nothing else.
- SI-D23 lib/error.ml gains the arm `Termination of string` (error.ml:36)
  plus termination_msg (error.ml:45), which holds the pin text of
  kan-lang-tot-pin/lib/error.ml:185 word for word, read at error.ml:64
  and :82;  no wildcard arm was added.
- SI-D24 The certificate of M1-PLAN.md:111 is the record group in
  lib/order.ml (step at :60, call at :67, row at :73, t at :87) with one
  o_arg for the whole group.
- SI-D25 lib/order.ml reads no family record at all, which is stronger
  than brief 3.5:  Rules.mu_family keeps its single reader and R0-AUDIT
  stays clean.
- SI-D26 The pin status read `List.nth_opt` is spelled `Rules.at` at
  order.ml:251 because dev/house.sh:23 refuses the pin spelling;  the
  read is the same total combinator.
- SI-D27 DEVIATION from the wording of brief 3.4 and I-F2.
  Order.translate (order.ml:538) validates the Elim the body already
  holds and returns it (order.ml:581), and the recursive result of a
  field is the guarded call at the leg binder the certificate row names,
  rather than legs physically extended by extra binders.  Reason:
  Rules.mu_branch zips the constructor fields against l_binders and
  errors when the lengths differ, and Rules.mu_beta substitutes the
  constructor arguments alone, so a longer leg is refused by the checker
  and would read an unbound index at reduction.  Recorded in the
  translate doc comment.
- SI-D28 Order.translate refuses rather than guesses at three shapes,
  each with its own message constant (order.ml:509-514):  the peeled
  body must be exactly one Elim, the Elim must carry a motive, and every
  branch address must carry a constructor address.
- SI-D29 No fixture was written by builder 1 and no file under test was
  touched by it;  its behaviour claims were checked on a copy of ROOT
  under WORK and then deleted, so ROOT was never mutated for a check.
- SI-D30 The caller stands at surface/elab.ml:1004
  (`Totality.guard_group`), after every body is elaborated at
  surface/elab.ml:999 and before Order.translate at surface/elab.ml:1029,
  which is the pin order at kan-lang-tot-pin/lib/check.ml:1545 then
  :1558, and only the translated term reaches the kernel at
  surface/elab.ml:1030.
- SI-D31 The surface/token.ml and surface/lexer.ml edits are kept
  (token.ml:70 KRec, token.ml:126 its describe row, lexer.ml:57 the
  keyword row), because the shape the mu group of correction C7 uses
  spells its group word as a keyword.
- SI-D32 The SI-D12 split FIRED, and for all three positives:
  test/fixtures gained no file, and mu-rec-direct.kan, mu-rec-indexed.kan
  and mu-rec-mutual.kan stand under test/erase-neg with a .err sidecar
  that pins the interim word of lib/erase.ml.  No Stage J erasure row was
  landed to make a golden.
- SI-D33 test/neg/mu-rec-guard-order.kan refuses under ruling R1 and
  SI-D5 at lib/order.ml:303-311:  its self call stands at an
  application, which never guards a call, so the file reads the ORDER of
  the two steps and not the refusal alone.
  test/neg/mu-rec-nondecreasing.kan is kept distinct:  its call argument
  is the scrutinee variable itself at status Principal
  (lib/order.ml:289-295), which is what SI-M2 kills.
- SI-D34 The KNEG row of I-F8 is rewritten to BOTH M1 answers
  (test/main.ml:216-243) and the row name list does not move
  (test/main.ml:333).  The acceptance half hands the guard a body built
  in OCaml at test/main.ml:163-205 and demands `Ok (Some 0)`.
- SI-D35 The obligation row at SPEC.md:515 is marked discharged in the
  form of the `any` row at SPEC.md:516, and no other row moved.
- SI-D36 dev/CARRIED.md is not edited and no row moves, because
  Global.def_entry already carries rec_arg (lib/global.ml:20).
- SI-D37 lib/order.ml joins the believed list at dev/trusted-lines.sh:50
  with a reason comment at :47-49, and kernel_bound=4000 and
  encoder_bound=600 are byte for byte unmoved.
- SI-D38 No fixture exposed a defect in a builder 1 file, so
  lib/order.ml, lib/totality.ml and lib/error.ml were not edited by
  builder 2.

### Findings

Stage I ran twice:  run wf_f5c9600e-24a (session 26b4aae2) died in
builder 2 on the five hour usage limit at 10:26 PDT before any gate ran,
and this run carried the preflight and the builder 1 results inline and
resumed builder 2 on the salvaged tree.

- SI-F1, info, open for the user.  SI-D27 is a disclosed deviation from
  the wording of brief 3.4 and I-F2.  Order.translate does not build new
  leg binders for recursive results;  it validates the Elim the source
  already holds (lib/order.ml:538-581).  The kernel refuses the literal
  reading (Rules.mu_branch zips the constructor fields against l_binders
  and Rules.mu_beta substitutes the constructor arguments alone), so the
  deviation is forced.  Resolution:  the user rules on SI-D27 before
  Stage J reads a computed recursive value out of a leg binder.
- SI-F2, low, accepted.  The TRUSTED-LINES headroom after Stage I is 18
  lines under the 4000 kernel bound:
  `TRUSTED-LINES kernel=3982/4000 encoder=216/600 OK`, with lib/order.ml
  at 581 lines.  The gate is green and D-M1-7 forbids moving the bound
  again, so Stage J and Stage K must budget any new kernel line against
  a compensating deletion.  SI-B6 did not fire.
- No high and no medium finding stands.  The preflight drift of I-F5,
  where the Stage H hand-off notes cite line numbers five to six lines
  short of the committed tree, is recorded there and is not a defect:
  every named site is present and behaves as described.

### Hand-off notes for Stage J

What Stage J reads on this tree.

- The Elim the translation builds.  `Order.translate` at
  lib/order.ml:538 answers `Ok (rewrap ws (Term.Elim e))` at
  lib/order.ml:581, so the term the kernel checks at
  surface/elab.ml:1030 is one Elim at the Stage H fibered form under the
  peeled lambdas, with a motive and one branch per constructor address.
  The recursive result of a field is not a new binder:  it is the
  guarded call at the leg binder the certificate row names, which is
  SI-D27 and the finding SI-F1 the user rules on.  The leg binder itself
  is `Term.leg.l_binders` at lib/term.ml:27 with `l_body` at :28, and
  the certificate names the branch through `step.st_ctor` at
  lib/order.ml:62 and the chain of `call.cl_chain` at lib/order.ml:69.
  The erasure rows and the KTail guard of M1-PLAN.md:106 and :214 read
  that leg.
- The definition group, the rec group boundary of D-M1-5.  The group is
  `Order.t.o_group` at lib/order.ml:88, built by `certify` at
  lib/order.ml:462 from the members the parser collects in
  `parse_rec_group` at surface/parser.ml:459 through the `def rec ...
  and ...` production at surface/parser.ml:422, carried as
  `Syntax.DRec` at surface/syntax.ml:136 and handed to the guard at
  surface/elab.ml:1004.  One rec group per mutual family is that list.
- The interim erasure word and the files of the SI-D12 split.  The word
  is at lib/erase.ml and it is pinned by four sidecars under
  test/erase-neg:  mu-erase.err from Stage G, and the three of this
  stage, test/erase-neg/mu-rec-direct.kan with .err,
  test/erase-neg/mu-rec-indexed.kan with .err and
  test/erase-neg/mu-rec-mutual.kan with .err.  Stage J turns each of the
  three back into a positive under test/fixtures with its .checked and
  its .erased golden and drops the sidecar.
- The certificate site the tail eligible shape of A10 reads.  The
  guarded position is stored at surface/elab.ml:1040 as
  `rec_arg = Some c.Order.o_arg` into the `Global.Def` entry field
  `rec_arg` at lib/global.ml:20, and the live certificate is
  `Order.t` at lib/order.ml:87 as `guard_group` answers it at
  lib/totality.ml:127.

### Review fixes, 2026-09-06

The staged review reproduced two defects: `double (succ zero)` stayed
neutral, and a guarded group rejected a constant helper without a case.
The following corrections supersede the evaluator and helper behavior
described in SI-D27, SI-D28 and SI-F1 above.

- `Eval.whnf` now unfolds a reducible recursive global only when its
  guarded argument is a constructor.  Bare globals, missing guarded
  arguments, neutral arguments and explicitly opaque definitions stay
  frozen.  Replay preserves application and elimination frames.
- `Elab.elab_rec_group` marks definitions reducible and gives `rec_arg`
  only to members that contain group calls.  `Order.translate` preserves
  helpers without requiring a case.  Helpers with no group calls do not
  constrain the certificate's formal-position search.
- `Order.translate` still validates the source Elim.  SI-D27's deviation
  from extra recursive-result binders remains disclosed: recursive calls
  now compute through guarded unfolding in the evaluator.
- `test/main.ml` adds the mandatory `REC values` row: direct, mutual and
  indexed computation, constant helpers including a nullary member,
  a nonzero guarded position, returned functions, partial applications,
  neutral arguments and explicit opacity.
- Validation on a scratch copy: build with zero errors and warnings;
  full `dev/gates.sh` battery `GATES-OK`; kernel and Wasm suites passed;
  M0-TIME median 89.349 ms against 150 ms; M0-RATIO 0.250.
  `TRUSTED-LINES kernel=3993/4000 encoder=216/600 OK` after shortening
  duplicate order comments.  No bound, denominator or gate was changed.

## Stage J (2026-09-06)

Erasure, rec groups and emission of recursive values (M1-PLAN.md:212-218).
The stage lands the SMu rows of the erasure, the multi-member rec group
form of the encoder, one rec group for each mutual family in the link
pass, the dispatch over recursive payloads in the emitter and the two
A10 fixtures.  SPar and SNu keep the refused arm (A6).

### Deliverables

- `lib/erase.ml` 1439 lines, from 1146 at stage entry.  `mu_tid` at :211
  and `mu_leg_tid` at :219 write the tid text;  the `KTag` answer is at
  :956 and the `KCase` answer at :1031;  the interim word `mu_erase_word`
  and `mu_refused` are gone.
- `lib/eterm.ml` 117 lines, unchanged.  No IR constructor was added.
- `wasm/gc_encode.ml` 237 lines, from 216.  The rec group form and the
  rewritten header invariant.
- `wasm/link.ml` 1091 lines, from 842.  `family_groups` at :926 reads the
  group boundary from the `KRec` groups the erasure publishes.
- `wasm/emit.ml` 778 lines, from 760.  One kernel binder for each runtime
  field, `local.get`, `ref.cast` to the leg type and `struct.get`.
- `bin/kanon.ml` 308 lines.  Two line defect fix at `run_emit`, which
  erased in `Global.initial` and now erases in the globals the file was
  checked in.
- `test/main.ml` 448 lines, from 440.  The ERASE-NEG group verdict is
  `passed = total` alone, because the directory is now empty.
- `test/wasm.ml` 283 lines.  The suite elaborates with `Elab.check_in`
  and keeps the globals it answers.
- `SPEC.md` 519 lines, from 516.  Two erasure rows in section 2.3, the
  rewritten milestone row at :127 and one `rec groups` row at :354.
- Fixtures that left `test/erase-neg` and became positives, each with a
  driver produced `.checked` and `.erased` golden: `mu-erase.kan` 13
  lines, `mu-rec-direct.kan` 19, `mu-rec-indexed.kan` 26 and
  `mu-rec-mutual.kan` 26.  Their four `.err` sidecars are deleted and
  `test/erase-neg` holds only `.gitkeep`.
- New A10 fixtures: `test/fixtures/mu-cata-depth.kan` 22 lines with
  `.checked`, `.erased` and `.wat` goldens, and
  `test/fixtures/mu-mutual-emit.kan` 16 lines with the same three.
  `test/golden` now holds 17 `.wat` files.
- Stage local, outside the repository: the tail eligible fixture
  `mu-tail-100k.kan` 29 lines and the gate script `sj-g8.sh`, both under
  the session work directory (SJ-D40, SJ-D42).

### Gates

Every leg below was rerun by the judge on ROOT at 2026-09-06 15:22,
after `zsh dev/dune.sh clean`.  The lines are the exact final lines.

- SJ-G1 BUILD.  `zsh dev/dune.sh clean` exit 0, then
  `zsh dev/dunecho.sh build`: `OK build: 0 errors, 0 warnings`, exit 0.
- SJ-G2 SUITE-KERNEL.  `_build/default/test/main.exe test`:
  `PARSE-OK 90/90`, `CHECK-OK 59/59`, `ERASE-OK 59/59`, `NEG-OK 31/31`,
  `ERASE-NEG-OK 0/0`, `KNEG-OK 2/2`, `REC-OK 1/1` and `SUITE-KERNEL OK`,
  exit 0.  The four fixtures of brief 3.3 count in the CHECK group and
  in the ERASE group, and the erase-neg group line reads its zero count,
  because the directory is empty (SJ-D27, SJ-D44).
- SJ-G3 SUITE-WASM.  `_build/default/test/wasm.exe test`:
  `EMIT mu-cata-depth OK`, `EMIT mu-mutual-emit OK`, `WASM-OK 17/17` and
  `SUITE-WASM OK`, exit 0.
- SJ-G4 ENCODER-SUBSET.  `zsh dev/encoder-subset.sh .`:
  `ENCODER-SUBSET OK`, exit 0.
- SJ-G5 TRUSTED-LINES.  `zsh dev/trusted-lines.sh .`:
  `TRUSTED-LINES kernel=3993/4000 encoder=237/600 OK`, exit 0.  The
  kernel delta against the entry reading of 3993 is 0 and the 7 lines of
  headroom are untouched, so SJ-B2 does not fire.  The encoder delta
  against 216 is plus 21 and the headroom left for Stage K is 363 lines.
- SJ-G6 M0-E2E.  `zsh dev/gates.sh --leg e2e`: `PASS M0-E2E main=521`,
  exit 0.  The answer is the M0 answer and `examples/m0-spine.kan` was
  not edited.
- SJ-G7 HOUSE.  `zsh dev/house.sh .`: `HOUSE no-exception OK`,
  `HOUSE no-mutable-state OK`, `HOUSE one-catch-site OK` with the one
  allowed site `test/sys_io.ml:19`, `HOUSE no-bool-match OK`,
  `HOUSE no-em-dash OK`, `HOUSE OK`, exit 0.
- SJ-G8 TAIL-DEPTH, stage local (brief 3.10, SJ-D42).
  `zsh sj-g8.sh /Users/oobi/Documents/kanon`:
  `TAIL-DEPTH mu-tail-100k node exit 0 answer 100000 want 100000`,
  `TAIL-DEPTH mu-tail-100k wasmtime exit 0 answer 100000 want 100000`,
  `TAIL-DEPTH mu-cata-depth node exit 0 answer 4095 want 4095`,
  `TAIL-DEPTH mu-cata-depth wasmtime exit 0 answer 4095 want 4095`,
  `TAIL-DEPTH-OK 4/4 tail return_call 15 cata return_call 0` and
  `TAIL-DEPTH OK`, exit 0.  The measured depth of the general
  catamorphism fixture is 4095 (SJ-D39).
- SJ-G9 LOGS.  `dev/M1-BUILD-LOG.md` holds one `## Stage J (2026-09-06)`
  line and `dev/M1-MUTATION-LOG.md` holds one `## Stage J` line, both
  appended after the Stage I section, which is unchanged.
  `git diff --stat -- dev/M0-BUILD-LOG.md dev/MUTATION-LOG.md` is empty
  and the porcelain lists Stage J paths only.

The whole battery.  `zsh dev/gates.sh` ran once at 15:23 and printed
`PASS` for BUILD, CARRY, R0-COUNT, R0-AUDIT, SUITE-KERNEL, SUITE-WASM,
ENCODER-SUBSET, AXIOMS, `PASS M0-E2E main=521`, `PASS M0-RATIO
ratio=2.821`, TRUSTED-LINES, DENOMINATORS, HOUSE and
`PASS PIN sha=8cf0b8b`.  R0-COUNT is green with no count edit (SJ-D10)
and CARRY is green because no carried file was edited.  M0-TIME failed
alone under host load: `FAIL M0-TIME median_ms=179.126 bound_ms=150` at
load average 35.91, then the three reruns of `zsh dev/gates.sh --leg
time` read `FAIL M0-TIME median_ms=188.525 bound_ms=150` at load 27.74,
`FAIL M0-TIME median_ms=248.392 bound_ms=150` at load 29.68 and
`FAIL M0-TIME median_ms=236.997 bound_ms=150` at load 29.68.  The main
loop waived SJ-B9 for this leg at 15:06 on the readings 97.3, 101.1 and
95.1 ms at load 21.7, and the fixer read
`PASS M0-TIME median_ms=149.873 bound_ms=150` at load 48.46 on the same
tree.  `M0_TIME_MS` stays 150 at `dev/gates.sh:48` and no agent edited
it.  The plan calls a real regression a reading above the bound at a
load average at or under 3 (M1-PLAN.md:233), which this host is far
above.

### MEASURE table

The judge ran the whole battery `zsh dev/gates.sh` once on ROOT at
2026-09-06 15:23, at the load average 35.91 35.13 32.87 before the run
and 32.63 34.45 32.67 after it.  The rows are copied from that run.  The
timed leg failed alone and was rerun three times;  the readings and
their load averages are in the Gates section above.

```
MEASURE BUILD tier=SLOW elapsed_ms=381.414 exit=0
MEASURE CARRY tier=MED elapsed_ms=1305.905 exit=0
MEASURE R0-COUNT tier=FAST elapsed_ms=118.605 exit=0
MEASURE R0-AUDIT tier=FAST elapsed_ms=52.972 exit=0
MEASURE SUITE-KERNEL tier=SUITE elapsed_ms=529.114 exit=0
MEASURE SUITE-WASM tier=SUITE elapsed_ms=3384.375 exit=0
MEASURE ENCODER-SUBSET tier=FAST elapsed_ms=137.438 exit=0
MEASURE AXIOMS tier=MED elapsed_ms=60.054 exit=0
MEASURE M0-E2E tier=SLOW elapsed_ms=1531.513 exit=0
MEASURE M0-TIME tier=SLOW elapsed_ms=1248.338 exit=1
MEASURE M0-RATIO tier=SLOW elapsed_ms=2592.306 exit=0
MEASURE TRUSTED-LINES tier=FAST elapsed_ms=51.477 exit=0
MEASURE DENOMINATORS tier=MED elapsed_ms=82.821 exit=0
MEASURE HOUSE tier=MED elapsed_ms=153.936 exit=0
MEASURE PIN tier=FAST elapsed_ms=156.141 exit=0
MEASURE M0-RATIO kanon_ms=292.438 tot_ms=103.662 ratio=2.821
BENCH m0_e2e median_ms=179.126 min_ms=157.531 max_ms=200.455 runs=5
BENCH m0_ratio median_ms=292.438 min_ms=254.743 max_ms=970.102 runs=5
```

### Decisions

SJ-D1 to SJ-D20 are pinned by the stage brief.  SJ-D21 to SJ-D42 are the
builder decisions.  SJ-D43 to SJ-D45 are the fixer decisions, renumbered
by the judge because the builders reached SJ-D42.

- SJ-D1 The erasure lands the four rows of M1-PLAN.md:103-106 and
  nothing else;  SPar and SNu keep the refused arm (A6).
- SJ-D2 No IR constructor is added;  every mu row lands on KTag, KCase,
  KTail and KErased.
- SJ-D3 No believed kernel file is edited.
- SJ-D4 An index argument is erased on the quantity Zero rule of A2.
- SJ-D5 The tid text is mu of the family name with the leg tid at the
  constructor index.
- SJ-D6 The rec group form is one composite type list with the rec group
  opcode and one sub final entry for each member.
- SJ-D7 The group boundary is the family record and never the emitter.
- SJ-D8 The four interim sidecars go and their .kan files become
  positives with driver produced goldens.
- SJ-D9 No SPEC.md obligation row moves at Stage J.
- SJ-D10 No R0 count moves and R0-COUNT stays green.
- SJ-D11 SJ-B1 does not fire for the multi-member rec group form.
- SJ-D12 The tail eligible fixture keeps the depth of 100,000;  the
  depth of the general catamorphism fixture is measured by this stage.
- SJ-D13 The general catamorphism fixture lands under test/fixtures;  the
  100,000-deep fixture is driven by the stage local gate SJ-G8.
- SJ-D14 Every golden is produced by the driver.
- SJ-D15 The two TRUSTED-LINES budgets stay 4,000 and 600.
- SJ-D16 The encoder headroom is shared with Stage K and is reported at
  the end of this stage.
- SJ-D17 Every mutation runs on a fresh copy and ROOT is never mutated.
- SJ-D18 A leg name that dev/gates.sh does not accept is read from one
  full run of the battery (erratum SG-D25).
- SJ-D19 examples/m0-spine.kan is never edited.
- SJ-D20 This brief adds SJ-G8 and SJ-G9 beyond the plan's seven gates.
- SJ-D21 The tid text is pinned in two forms: the family tid is
  `mu<NAME>` and never carries an index, and the leg struct of
  constructor K is `leg<mu<NAME>,K,R1,...,Rn>` with one repr for each
  runtime field in declaration order, or `leg<mu<NAME>,K>` for a
  constructor with no runtime field (lib/erase.ml:211 and :219).
- SJ-D22 The family tid is nominal and not structural, because the
  structural text of a recursive family would contain itself, and
  `tid_of` must agree with `repr_of` for one type (SC-D5).  A mu type
  reprs as the union `mu<NAME>` (lib/erase.ml:276).
- SJ-D23 erase.ml publishes the leg names through the rec group the
  declaration already emits:  `acc` gains a `groups` field, each KTag and
  KCase site appends the leg names of its family, and `def_code` folds
  them into KRec.  Every M0 golden is unchanged, because a program with
  no mu contributes no group name.
- SJ-D24 erase.ml discovers no mutual component:  each site publishes the
  legs of the family it names, a sibling appears inside a leg text as
  `union mu<SIBLING>`, and link.ml joins the group from those reference
  edges, so lib/global.ml needs no new accessor and SJ-B2 does not fire.
- SJ-D25 A branch of a KCase binds one kernel binder for each runtime
  field in declaration order, mirroring `rules.ml mu_branch`;  a field at
  quantity Zero binds no runtime binder and the last runtime field is the
  innermost one.
- SJ-D26 The interim words `mu_erase_word` and `mu_refused` are deleted.
  A `Sec` at SMu and an `Out` at SMu keep a refusal and read the word
  `Rules.mu_ran_word` that rules.ml already holds, so Stage J writes no
  new milestone word (SA-D5).
- SJ-D27 The empty `test/erase-neg` directory stays alive with an empty
  `.gitkeep`, because `kan_names` reads the .kan files of the directory
  and a directory that no commit carries would make the suite exit
  through `fail_out` on a fresh checkout.
- SJ-D28 The test/main.ml verdict is split:  the ERASE-NEG group is
  checked with `passed = total` alone and every other group keeps
  `passed = total && total > 0`, because brief 3.3 foresees the empty
  directory and SJ-G2 still requires SUITE-KERNEL OK.
- SJ-D29 For Stage K:  the leg text of a parameterised family is read at
  the parameter values of the site, so one family at two different
  runtime parameters would give two leg texts under one family tid.  No
  M1 fixture reaches that case;  the array and bignum forms of Stage K
  should pin whether the leg text is canonicalised at the parameter
  variables instead.
- SJ-D30 wasm/gc_encode.ml carries the rec groups as `comptype list
  list`, one entry for each group:  a group of one is the bare comptype,
  so every M0 module keeps its bytes, and a group of two or more is
  `0x4E`, the member count, then one `0x4F` sub final entry with an empty
  supertype vector for each member.  The index of a type stays its
  position in the flat reading of the groups and the header invariant
  comment is rewritten in the same edit (D-M1-5, SD-D17).
- SJ-D31 SPEC.md section 8 gains one row named `rec groups`.  No other
  row is widened and dev/encoder-subset.sh reads only the six instruction
  rows, so the allowlist does not move and SJ-B1 does not fire
  (RATIFICATIONS.md:75).
- SJ-D32 wasm/link.ml reads the legs of a family from the KRec groups the
  erasure publishes, held in `prog.mus`, because a family tid is nominal
  and carries no leg text.  `sum_legs_p` prefers that table and falls
  back to the structural reading of the tid text, which keeps every M0
  sum on its old path.
- SJ-D33 The rec group boundary is the strongly connected component of
  the reference edges the leg tids carry, and not the connected
  component:  a family that only holds a value of another family stays
  its own group, and only families that reach each other share a group
  (D-M1-5, probe p4).
- SJ-D34 A family that does not reach itself is not recursive and keeps
  one composite one group, which is SD-D17;  a recursive family, direct
  or mutual, puts every leg struct of every constructor of every member
  in one group.
- SJ-D35 wasm/emit.ml binds one kernel binder for each runtime field in
  declaration order, the last field innermost, and reads a field with
  `local.get`, `ref.cast` to the leg type and `struct.get` of field k+1,
  then the coercion to the field repr (SJ-D25, SD-D5).
- SJ-D36 Defect fix in bin/kanon.ml:  `run_emit` erases in the globals
  the file was checked in and not in `Global.initial`, because every mu
  family was unbound at emit.  Two lines.
- SJ-D37 Defect fix in test/wasm.ml:  the suite elaborates with
  `Elab.check_in` and keeps the globals it answers, because the rows
  alone do not carry the inductive families.  `kernel_value` and
  `emitted` read those globals and the fold `globals_of` is gone.
- SJ-D38 The general catamorphism fixture `test/fixtures/mu-cata-depth`
  at depth 4,095 holds no `return_call` at all:  its doubling builder is
  a recursion whose branch body consumes the recursive result, each chain
  global is a constructor application and `main` goes through `natAdd`,
  so the SJ-G8 reading of no `return_call` is exact and SJ-M2 cannot
  touch it.
- SJ-D39 The measured depth of the general catamorphism:  node answers
  8191 and fails at 16383 with `Maximum call stack size exceeded`;
  wasmtime answers 8191 and fails at 16383 with `call stack exhausted`.
  The fixture keeps 4,095, which is less than half of the smallest
  failing depth, and the kernel supplies its expectation in about 51 ms.
- SJ-D40 Placement under SJ-D13:  the 100,000-deep tail eligible fixture
  stays out of test/fixtures and is driven by the stage local gate SJ-G8
  out of the work directory, because the kernel needs 4.11 s to reduce
  its expectation while the whole SUITE-WASM leg measures 1.96 s.  The
  general catamorphism fixture lands under test/fixtures with its three
  goldens.
- SJ-D41 A third fixture, `test/fixtures/mu-mutual-emit.kan` with its
  checked, erased and wat goldens, lands beside the two A10 fixtures,
  because no golden held a multi-member rec group and SJ-M1 and SJ-M4
  would have had no subject.  It is the mutual family A and B with
  `sizeA` and `sizeB`, and `main` answers 4.
- SJ-D42 SJ-G8 is the stage local script `sj-g8.sh`, which takes the
  repository root as its one argument and defaults to ROOT, so a
  mutation copy runs it unchanged.  No dev/gates.sh leg is added, which
  stays the Stage L deliverable (M1-PLAN.md:230).
- SJ-D43 The fixer makes no source edit at Stage J.  SJ-F1 is a reporting
  defect and its remedy is the reproduced gate line, which the judge
  quotes;  SJ-F2 and SJ-F3 carry no one line fix, so the code of the
  stage stands as the builders left it.  The judge renumbered this
  decision and the two below from SJ-D26 to SJ-D28, because the builders
  reached SJ-D42.
- SJ-D44 The SJ-G2 entry of this log quotes the numeric group lines of
  the final reproduced run and never a terse later run that omits them.
  The erase-neg group line is quoted at its zero count, which brief 3.3
  requires because the directory is empty and holds only
  `test/erase-neg/.gitkeep`.
- SJ-D45 The Stage K and Stage L hand-off carries the SJ-F2 fact as a
  build rule and not as a gate change:  wasm-opt and ENCODER-SUBSET are
  confirmed not to reject a wrong rec group split, so every new
  multi-member-group fixture needs a .wat golden that holds the `(rec`
  form.  No leg of dev/gates.sh moves at Stage J.

### Findings

- SJ-F1, medium, resolved by this log.  The builder hand-off quoted
  `PARSE-OK 88/88, CHECK-OK 57/57, ERASE-OK 57/57` for SJ-G2, which does
  not reproduce:  the tree reads `PARSE-OK 90/90`, `CHECK-OK 59/59` and
  `ERASE-OK 59/59`, and 59 files match `test/fixtures/*.kan`.  The stale
  figure was read before `mu-cata-depth.kan` and `mu-mutual-emit.kan`
  landed.  No committed file carries it;  the only `88/88` in the
  repository is the Stage I section of this file, where it is correct.
  The Gates section above holds the reproduced numbers (SJ-D44).
- SJ-F2, low, disclosed and carried into the hand-off.  SJ-M1 and SJ-M4
  are not caught by wasm-opt or by ENCODER-SUBSET.  On both mutation
  copies `wasm-opt --enable-gc --enable-reference-types
  --enable-tail-call --print` exited 0 with an empty stderr, node still
  answered 4, and `ENCODER-SUBSET OK` still printed.  The killer in both
  cases is the byte for byte golden compare in test/wasm.ml against
  `test/golden/mu-mutual-emit.wat`, the one golden of the 17 that holds a
  `(rec` form.  The remedy is the build rule of SJ-D45.
- SJ-F3, info, no edit.  M0-TIME is load sensitive on this host and is
  not a code defect.  The readings and their load averages are in the
  Gates section.  `M0_TIME_MS` stays 150.

### Hand-off notes for Stage K

- The encoder count.  `wasm/gc_encode.ml` is 237 lines of the 600 line
  encoder budget, from 216 at Stage J entry, so 363 lines are left for
  the array composite type and its three opcodes (SJ-D16,
  M1-PLAN.md:130).  The budget does not move (D-M1-7, correction C6);  a
  form above 363 lines is SJ-B3 at Stage K and a halt for the user.
- The erased rows the bignum representation must keep sound.  SPEC.md
  section 2.3 now holds two mu rows:  `In` at `Lan (SMu ..)` erases to
  `KTag (tid, the constructor index in declaration order, the runtime
  fields)`, with a tag and no payload for a constructor with no runtime
  field, and no index argument ever enters it;  `Elim` at `Lan (SMu ..)`
  erases to `KCase (tid, scrutinee, one branch for each constructor in
  declaration order)`, and a branch body that is the recursive call
  itself is `KTail`.  A branch binds one kernel binder for each runtime
  field in declaration order, the last field innermost (SJ-D25).  The two
  representation runtime of Stage K must keep both rows true for a Nat
  that is a bignum:  a field at the bignum representation is still one
  runtime field of the leg struct and still one branch binder.
- The tid text the array tid joins.  The family tid is `mu<NAME>` and
  carries no index.  The leg struct of constructor K is
  `leg<mu<NAME>,K,R1,...,Rn>`, one repr for each runtime field in
  declaration order, and `leg<mu<NAME>,K>` for a constructor with no
  runtime field (SJ-D5, SJ-D21, lib/erase.ml:211 and :219).  A mu type
  reprs as the union `mu<NAME>`, which is nominal and not structural
  (SJ-D22).  The array tid of Stage K joins that text and link.ml dedups
  by it.
- The measured depth of the general catamorphism.  The fixture
  `test/fixtures/mu-cata-depth.kan` runs at depth 4,095 and holds no
  `return_call`.  Both hosts answer 8191 at depth 8,191 and both fail at
  16,383:  node prints `Maximum call stack size exceeded` and wasmtime
  prints `call stack exhausted`.  The fixture depth is less than half of
  the smallest failing depth (SJ-D12, SJ-D39, RATIFICATIONS.md:80).
- The fixtures that left test/erase-neg.  Four files moved to
  `test/fixtures` and each gained a driver produced `.checked` golden and
  a driver produced `.erased` golden:  `mu-erase.kan`,
  `mu-rec-direct.kan`, `mu-rec-indexed.kan` and `mu-rec-mutual.kan`.
  Their four `.err` sidecars are deleted, none of the four defines
  `main`, so none has a `.wat` golden, and `test/erase-neg` now holds
  only `.gitkeep` and reads `ERASE-NEG-OK 0/0` (SJ-D8, SJ-D27, SJ-D28).
- The build rule for a new rec group fixture.  wasm-opt and
  ENCODER-SUBSET do not reject a wrong rec group split, so every new
  fixture with a multi-member group needs a `.wat` golden that holds the
  `(rec` form.  Today `test/golden/mu-mutual-emit.wat` is the only one of
  the 17 `.wat` goldens that holds it (SJ-F2, SJ-D45).
- The stage local gate.  SJ-G8 lives outside the repository with the
  100,000-deep fixture `mu-tail-100k.kan`.  Stage L owns dev/gates.sh and
  decides whether the leg joins the battery (M1-PLAN.md:230).

### Notes for the user, not a ruling

- Gates beyond the plan row.  The plan gives SJ-G1 to SJ-G7.  This stage
  ran SJ-G8 TAIL-DEPTH and SJ-G9 LOGS as well, which the stage brief adds
  on the Stage G, Stage H and Stage I precedent (SJ-D20).
- The encoder reading.  237 of 600 lines, 363 left for Stage K.
- The placement of the 100,000-deep fixture.  It stays out of
  test/fixtures and rides SJ-G8, because the kernel needs 4.11 s to
  reduce its expectation (SJ-D13, SJ-D40).
- The measured catamorphism depth.  4,095 in the fixture, 8,191 answered
  and 16,383 failing on both hosts (SJ-D12, SJ-D39).
- Builder work beyond the brief file list.  The defect fixes in
  bin/kanon.ml (SJ-D36) and test/wasm.ml (SJ-D37), the third fixture
  mu-mutual-emit (SJ-D41), and the `.gitkeep` and the split ERASE-NEG
  verdict that keep the empty directory alive (SJ-D27, SJ-D28).

### Staged review fixes (2026-09-06)

Review scope: the 36 staged Stage J paths, before commit.  Validation ran
in an isolated copy of that tree, with the original vendor tree read only.

- CI coverage blocker, fixed in test/main.ml: the empty ERASE-NEG exception
  accepted deletion of migrated positives.  Removing mu-erase.kan from
  fixtures made the original staged suite exit 0.  The new MIGRATED group
  requires all four replacements; the same mutation now reports the
  missing fixture, MIGRATED-OK 3/4, and exits 1.
- MEDIUM, fixed in lib/erase.ml: mu_group_tids published site-specific
  representations under one nominal family tid.  Checked eliminators for
  Box Nat and Box (Nat -> Nat) made emission exit 2 with "an application
  head is not a function".  Layouts now open family parameters as neutral
  variables in a fresh context.  This resolves and supersedes SJ-D29.
- MEDIUM, fixed in lib/erase.ml: mu_fields dropped a dependent payload
  instantiated at prod (), while its declaration layout and case branch
  retained a field.  The checked mu-dependent-layout fixture made emission
  exit 2 with "an argument list is shorter than its signature".  Payloads
  and branch slots now follow the same declaration layout.  A generic
  field instantiated at an erased type carries KErased as a placeholder.

Added mu-parameter-layout and mu-dependent-layout to the normal fixture
suite, with checked, erased and validated Wasm text goldens.  The first
covers Nat, function, tuple and empty tuple parameter instantiations.  The
second exercises constructors at Nat, empty tuple and function types, with
a trailing Nat field to check binder positions.  Node and Wasmtime answer
9 and 27 respectively, agreeing with the kernel expectations.

Validation: build 0 errors and 0 warnings; PARSE-OK 92/92, CHECK-OK 61/61,
ERASE-OK 61/61, NEG-OK 31/31, ERASE-NEG-OK 0/0, KNEG-OK 2/2, REC-OK 1/1,
MIGRATED-OK 4/4, SUITE-KERNEL OK; WASM-OK 19/19, SUITE-WASM OK.  The full
15-leg dev/gates.sh battery passed with GATES-OK.  M0-E2E returned 521;
M0-TIME median was 132.583 ms against 150 ms; TRUSTED-LINES remained
kernel=3993/4000 and encoder=237/600.  Existing goldens stayed unchanged.

Blockers: none remain from this review.  Merge verdict: merge with these
staged fixes, which make nominal constructor layouts consistent across
instantiations and preserve migrated test coverage.  No commit was made.

## M1 Stage K: arbitrary precision Nat and exact One (2026-09-06)

Status: PASS, all eleven Stage K gates and all four semantic mutations.
The user's agreement correction and explicit M0-spine freeze exception
are recorded in RATIFICATIONS.md rounds 2026-09-06 (d) and (e).
No commit or M1-EXIT is claimed; the commit remains a user step.

ROOT remains `/Users/oobi/Documents/kanon` at Stage J commit
`ac94fe36c7fc7d4013a00d3fa102666e2cafdd0a`.  The isolated implementation is
`/Users/oobi/Documents/gpt4/kanon-stage-k/work`; PREP denotes its parent.
The frozen tot pin and vendor are `8cf0b8bfbb574e344d8d489ba6fd6b81de4cf562`.
Earlier M0 and M1 log entries, denominators and R0 counts are unchanged.

### Decisions and implementation

| Id | Final decision and evidence |
| --- | --- |
| SK-D1 | Bignum is the total signed Zarith 1.14 boundary, pinned in dune-project and linked by lib/dune.  Decimal folding validates digits; narrowing checks representability.  Negative forged Nat literals and primitive operands are rejected.  PREP/naturals-check.sh passes 44 boundary checks. |
| SK-D2 | The closed LInt constructor carries Bignum.t.  Its consumers, printers and surface tokens are widened.  The carried literal delta is 15; no kernel term, shape or IR constructor is added. |
| SK-D3 | Nat decimals have no host-integer ceiling.  Universe, binder, leg and projection numbers use total bounded readers.  Exact add, truncated subtract, multiply, equality and less-than retain Bool leg 1 for true and 0 for false. |
| SK-D4 | Runtime Nat uses i31 through 1073741823, otherwise an immutable sign-1 struct holding little-endian base-32768 limbs.  Helpers promote before overflow, allocate fresh result arrays, trim high zero limbs and normalize small answers to i31.  The largest schoolbook intermediate is 1073741823. |
| SK-D5 | CArray and array.new/get/set/len are the complete encoder additions.  array.set is required to populate heterogeneous fresh limbs.  Shared operands are never stored into.  SPEC records exact encodings.  Binaryen's printed exact reference qualifier is structural syntax, with no new encoder instruction; the subset negative control still rejects i32.and. |
| SK-D6 | Internal large values remain exact.  The unchanged zero-argument i32 export traps only for an out-of-i31 final result, with driver exit 4 on kernel, Node, Wasmtime and both.  The focused runtime runner passes 20/20 observations. |
| SK-D7 | Quantity owns pure path intervals and retained dependencies from nonreturning paths.  One is exactly one use on every returning runtime path.  Runtime mode is separate from multiplicity; repeated type inference does not count as runtime use.  The carried quantity delta is 151 after the review round of 2026-09-06. |
| SK-D8 | Rules compose sequences, declared argument scaling and branch alternatives.  Runtime Zero scrutinee stamps are rejected; surface and eta-generated cases use One.  Explicit One scopes close in the kernel.  Eager let definitions count once; aliases carrying a linear resource may be used at most once.  Closure construction retains dependencies even when invocation cannot return. |
| SK-D9 | Five actual unary SMu sources each contain 1089 indexed Agreement witnesses for every pair from 0 through 32, 5445 total.  Every unary definition and observer avoids its tested primitive, and all axiom disclosures are empty. |
| SK-D10 | Python integer arithmetic independently supplies all 400 pairs per primitive from the approved 20-value set, 2000 total.  Kernel, Node and Wasmtime each produce 400 successful small observations per operation.  No general theorem or billion-node unary execution is claimed. |
| SK-D11 | All eleven Stage K gates and four mutations remain required.  The ordinary suite retains all 61 original positive sources unchanged.  No bound, denominator, opcode guard, expected result or pin is waived. |
| SK-D12 | The believed list retains every existing member and adds Bignum.  Substantive reuse and traversal factoring hold the measured total at 3997/4000; encoder is 246/600.  No trusted work moves into an unmeasured new module and no documentation is deleted to meet the bound. |
| SK-D13 | The byte-identical unary matrices move to test/agreement, with all ten goldens retained in test/golden.  The dedicated mandatory gate also performs their original surface roundtrips.  Repeating all 5445 witnesses six times in the general-suite benchmark exceeded its 120-second watchdog; the dedicated gate preserves coverage and restores the original benchmark's bounded role. |
| SK-D14 | The user explicitly approved the M1-PLAN.md:153 exception: "Please apply the spine correction."  The linear function is now the identity; its former addition occurs at the closed call site as natAdd (linear 8) 1.  Linear use remains covered, linearValue remains 9, and the active baseline returns 521.  No quantity, expected answer, bound or denominator changes. |
| SK-D15 | Review exposed type-only and erased-field/call/let closure captures plus application erasure trusting APt stamps.  Erasure now prunes captures from the actual erased body's free variables and remaps retained indices; application quantities come from checked function types.  The combined regression returns 58 on all four host settings. |

The trusted count starts at 3993.  Shared occurrence traversal and list
comparison recover 40 lines.  After the initial usage implementation and
Bignum integration, the count was 4054.  Shared closure/list comparison,
former inspection, binder-quantity diagnostics and global-head lookup
recover 55 lines.  Soundness fixes add 12.  Totality reuses its ordered
spend_all traversal and merges identical Lan/Ran arms (9 lines); shared
SPi former checking recovers another 5.  Final: 3997, a net increase of
4 over Stage J and 3 lines of headroom.  Encoder grows by 9 to 246.

### Gates and observed results

| Id | Command in WORK unless stated otherwise | Observed result |
| --- | --- | --- |
| SK-G1 BUILD | zsh dev/dunecho.sh build | PASS, zero errors and warnings; Zarith 1.14 installed and pinned. |
| SK-G2 CARRY | zsh dev/carry-check.sh | PASS; quantity 97, literal 15, every other carried delta unchanged. |
| SK-G3 SUITE-KERNEL | _build/default/test/main.exe test; zsh one-paths.sh | PASS; PARSE 120/120, CHECK 73/73, ERASE 73/73, NEG 47/47, KNEG 2/2, REC 1/1, MIGRATED 4/4.  Direct One checks 27/27 and surface path checks 22/22.  Five exhaustive positives are additionally required by SK-G5. |
| SK-G4 SUITE-WASM | _build/default/test/wasm.exe test _build/stage-k-wasm-standalone; zsh dev/nat-runtime.sh | PASS; WASM 29/29 and focused runtime 20/20.  Extra capture regression returns 58 on kernel, Node, Wasmtime and both. |
| SK-G5 AGREEMENT | zsh agreement.sh | PASS; all 5445 unary and 2000 full-range cases, 7445/7445.  Unary parser roundtrips and both checked/erased goldens are mandatory.  Independent expectations match all three execution hosts. |
| SK-G6 ENCODER-SUBSET | zsh dev/encoder-subset.sh | PASS after exact printer-type accounting; the real printed exact control passes and unlisted i32.and is rejected. |
| SK-G7 TRUSTED-LINES | zsh dev/trusted-lines.sh | PASS; kernel 3997/4000, encoder 246/600, Bignum included. |
| SK-G8 DENOMINATORS | zsh dev/gates.sh --leg denominators | PASS; frozen JSON and hash unchanged. |
| SK-G9 HOUSE | zsh dev/house.sh; git diff --check | PASS; all house checks and whitespace clean. |
| SK-G10 BASELINE | zsh dev/gates.sh | PASS, all 15 legs and GATES-OK on the first active run after the approved spine correction.  M0-E2E 521; M0-TIME 110.466 ms against 150 ms.  PREP/gate-evidence/baseline-approved-spine.out and .json retain exact output and unchanged source digests. |
| SK-G11 LOGS | python3 -P PREP/validate-stage-k-close.py | PASS; exactly one Stage K section in each M1 log, all eleven gate rows, fifteen decision rows, four mutation rows and the Stage L handoff.  All earlier log bytes remain unchanged. |

The final active baseline records BUILD 304.825 ms, CARRY 798.448 ms,
SUITE-KERNEL 218.659 ms, SUITE-WASM 6027.434 ms and M0-RATIO 1411.866 ms.
Its informational raw M0 ratio is 2.054.  The normalized M1 ratio remains
a Stage L obligation.  M0-TIME measures 110.466 ms median, 101.794 ms
minimum and 113.624 ms maximum, five runs, against the unchanged 150 ms
bound.  Load averages were 18.88/25.36/36.07.  No timing rerun was needed.

The previous active baseline failed AXIOMS and M0-E2E on the frozen
spine's invalid One use; M0-TIME reported BENCH-ERROR before timing.
Its other twelve legs passed.  The earlier ratio watchdog failure was
resolved by SK-D13.  Both historical failures remain in gate-evidence.

A fresh positive proposal copy at PREP/spine-proposal-check/work now
passes the unchanged full battery on its first attempt: all fifteen legs
PASS, GATES-OK, M0-E2E 521 and M0-TIME 110.636 ms against 150 ms.  Its
source manifest proves the spine patch was the only difference at that
validation time, before subsequent SPEC and log updates.  Results and
full output remain under PREP/spine-proposal-check.  The user's explicit
exception then authorized application and the passing active run above.

Evidence: PREP/gate-evidence, agreement-evidence, agreement-reference.json,
agreement-move.json, agreement-roundtrip-evidence.json, check-review,
one-final-validation.json, one-paths.log, one-mutation, mutations and
linearity-handoff.md.  The mutation section below records SK-M1 through
SK-M4 and their explicit failure observations.

### Review and Stage L handoff

Review corrected eager-let accounting, unreachable closure construction,
runtime Zero scrutinee stamps, SPi eta stamp consistency, unnecessary
runtime captures, and forged APt application erasure.  Each concrete
finding has a passing regression under PREP/check-review.  The encoder
printer qualifier has separate positive and negative reader controls.

Stage L must integrate PREP/agreement.py, agreement-roundtrip.ml/.sh,
agreement-reference.json and full-range/*.kan into its required permanent
agreement leg.  Persistent unary sources are test/agreement/*.kan;
their checked and erased goldens remain in test/golden.  The existing
ordinary fixture suite and all its original sources remain present.
Integrate the focused One runner at PREP/one-paths.ml/.sh and the runtime
runner currently at WORK/dev/nat-runtime.sh.  Keep both finite agreement
sets mandatory and retain mutation controls and exact negative sidecars.

No Stage K blocker remains.  PREP/spine-correction.md explains the
approved correction and its evidence.  Close copies and stages only
reviewed Stage K paths after checking the unchanged Stage J base.
Stage F remains committed; no optional Lean agreement theorem was added.

## Stage L (2026-09-06)

### Status and scope

IMPLEMENTED, VALIDATION PENDING.  The user requested continued kanon
development and staging all changes.  The entry is c418062, the committed
Stage K.  This stage adds the full M1 surface, executable feature ledger,
permanent agreement runners, M1 spine and 1,000-line corpus.  The native
collaboration workflow ran separate scope, surface, gate, example review,
surface review, gate review and isolated mutation tasks.

The full battery returned GATES-FAIL, with sixteen passing legs and three
open legs: M0-TIME, M0-RATIO and AGREEMENT.  This is not a Stage L PASS or
an M1-EXIT ratification.  The user retains commits and the M1-EXIT stamp.
The explicit request to stage all changes supersedes historical SL-B3's
clean-porcelain exit condition.  Concurrent main-tree metatheory changes
are preserved and included in staging; they are not part of this compiler
validation.  No kernel, encoder, M0 spine, pin or frozen denominator changed.

### Deliverables and decisions

- SL-D1: `mu ... :=` and constructor `| name binder* : result` sugar
  reuse the Stage G family tree. Constructor binders fold into the
  existing dependent arrow chain with their original quantities.
  `mu ... with` and `and` remain compatible.
- SL-D2: `mutual mu ... mu ... end` creates one family group and
  requires at least two members. Empty, singleton, unterminated and
  `and`-joined explicit mutual blocks are parser refusals. Three-member
  recursion is covered by `sl-mutual-three.kan`.
- SL-D3: `match` has a distinct `SMatch` surface node, accepts only
  constructor keys, and requires a mu scrutinee even with zero branches.
  It calls the existing fibered elaboration. Numeric `case` and Stage H
  constructor `case` retain their behavior.
- SL-D4: constructor branches accept Stage H quantity/name fields and
  typed binders, including mixtures. An optional type annotation is
  checked at a universe and compared by existing type conversion with
  the declared field type, in the context of preceding fields. The
  kernel still checks field quantities and branches.
- SL-D5: the printer writes `:=`, normalizes multi-family declarations
  to `mutual ... end`, keeps constructor types as expanded arrows, and
  preserves `case` versus `match` and typed field annotations. Parsed
  trees round-trip exactly.
- SL-D6: `nu` keeps `nu arrives at M2` in term and declaration positions.
  Match keeps the Stage H optional index clause and existing kernel
  motive requirement. `end` terminates mutual groups only; parentheses
  delimit nested match bodies before an outer branch.
- SL-D7: `test/sl_surface.ml` holds 20 permanent parser boundary,
  round-trip and sugar-equivalence checks. Run without arguments;
  success is exit 0 and final line `SL-SURFACE OK`. Parser negatives
  belong here because the existing kernel suite parses every negative.
- SL-D8: added two runtime fixtures with checked, erased and Wat goldens,
  plus three semantic negatives for collection matching and incorrect
  field annotations. Parent-authorized migration renames embedded
  `def mutual` and its lookup in `test/main.ml` to `mutualValue`, because
  `mutual` is now a required reserved word. Gates agent owns the other
  independent change in that file.
- SL-D9: SPEC sections 7 and 9 describe the new sugar and complete M1
  grammar, including retained recursive definitions and compatibility
  forms. Section 10 marks subsingleton elimination discharged by Stage
  H SH-G7 and `any` discharged by Stage D SD-D6, retaining milestone M1.
  Independent review amendment: section 7 explicitly maps `def rec` and
  recursive `and` groups through `Totality.guard_group`, `Order.translate`
  and checking of the translated `Elim` body before `Global.Def`
  installation, as M1-PLAN section 4 requires. The implementation was
  read at surface/elab.ml:1035, :1061 and :1062 and lib/order.ml:510;
  this amendment changes documentation only.

- SL-D10: M0-TIME uses the median of three medians of five, always prints the
  three BENCH lines, retains 150 ms and excludes wasm-opt as previously ruled.
- SL-D11: M0-RATIO is binding on the unrounded per-line value, with six decimal
  places displayed; its numerator is the median of five corpus checks.
- SL-D12: Record the 8138 checked pin lines in dated denominators-m1.json;
  validate the ruled 103.662 ms and line-count fields before dividing.
- SL-D13: M1-CORPUS times check, emit, validation, kernel observation and the
  both-host driver path together, including their repeated driver work. It
  requires exactly 1000 newline-terminated lines and the 713 ms bound.
- SL-D14: The permanent AGREEMENT leg always executes both finite sets,
  totaling 5445 unary and 2000 independent exact-arithmetic cases.
- SL-D15: Retain original agreement source/manifest equality checks, unary
  round trips, both goldens and all three full-range host observations.
- SL-D16: Key HOUSE allowances by relative path, enclosing top-level function
  and exact arm text, with one reason each; line movement grants no new site.
- SL-D17: Replace the three additional named fallthroughs with exhaustive
  unit guards while preserving their existing successful and error branches.
- SL-D18: POSITIVITY discovers each positive fixture containing a mu
  declaration and requires the direct, mutual and indexed originals, plus
  the exact named nonpositive negative diagnostic.
- SL-D19: The executable M1 ledger retains original source fixtures, appending
  small closed scalar observations only into generated .gatework copies.
- SL-D20: Every ledger observation checks, emits, validates and compares
  kernel with both hosts; exact checker negatives accompany its feature row.
- SL-D21: Empty-family large elimination is checked and erased before a
  closed scalar observation. It cannot be applied to a closed Void inhabitant,
  because none exists. The non-subsingleton and self-recursive Prop negatives
  separately pin the two required refusals.
- SL-D22: Each primitive also has a small typed unary witness, both runtime
  observations and a deliberately wrong witness with an exact sidecar.
- SL-D23: Keep the original 27 direct kernel and 22 surface One path cases
  mandatory in M1-SUITE, including all original exact quantity diagnostics.
- SL-D24: Keep the original 20 Nat runtime observations mandatory, including
  the independent oversized-export trap on all four driver host modes.
- SL-D25: M1-SUITE runs surface's durable SL-SURFACE regression executable and
  the parent-owned M1 spine, requiring at least 300 lines and its main promise.
- SL-D26: Write generated suite sources, Wasm, WAT and evidence under
  .gatework; permanent data includes only reviewed sources and exact sidecars.
- SL-D27: Preserve all existing watchdog ceilings; use SUITE for positivity,
  M1-SUITE and AGREEMENT and SLOW for the timed corpus leg.
- SL-D28: Force RUNS=5 for each benchmark and reject malformed BENCH output;
  Decimal arithmetic avoids a rounded ratio silently crossing the bound.
  All three timing legs report the observed one-minute load.
- SL-D29: Keep explicit bound arguments in the helper for isolated mutation
  controls, while the permanent battery always supplies its fixed constants
  and accepts no environment-based bound or sampling overrides.

- SL-D30: examples/m1-spine.kan has 396 lines and returns 599.  It carries
  every accepted M0 form and all required M1 forms without a postulate.
  Its five small typed agreement witnesses compare unary recursion with
  literal arithmetic.  Each wrong witness was independently rejected.
- SL-D31: test/corpus/m1-corpus.kan has exactly 1,000 lines and returns
  814: the complete spine's 599, a 5-by-5 arithmetic grid's 200, and six
  indexed vector copies' 15.  Every grid cell and copy reaches the export.
  Checked agreement witnesses are proof obligations, not padding.
  dev/gen-m1-corpus.py regenerates the corpus byte for byte.  Continuation
  lines retain their source indentation; no blank or comment padding is
  added to reach the prescribed size.
- SL-D32: checksum expressions form balanced trees.  The initial scratch
  experiment used 100 grid cells and chained partial-sum globals, causing
  repeated elaboration through those globals.  The final representative
  corpus keeps every prescribed feature.  The separate ratified 7,445-case
  agreement matrix and its original sources are unchanged.
- SL-D33: strengthen HOUSE to scan complete source text, because review
  reproduced valid multiline catch-all arms that the first line scanner
  missed.  The two allowances remain exact, function-specific and single-use.
- SL-D34: preserve every failed timing result.  No threshold, sampling
  count, watchdog, ratio normalization or agreement requirement is waived.
  High load prevents a quiet-machine verdict in this run.  Stage L and
  M1-EXIT remain open until the failed legs pass.
- SL-D35: copy only reviewed compiler deliverables after checking entry
  hashes against main.  Stage all main-tree changes as explicitly requested,
  including the independent metatheory work.  Do not commit or write RATIFY.

### Observed gates

The full battery used these unchanged bounds: M0-TIME 150 ms, M0-RATIO
2.000, M1-CORPUS 713 ms, kernel 4,000 lines and encoder 600 lines.

```text
LOAD BEFORE (74.99462890625, 68.26806640625, 49.6728515625)
PASS BUILD
PASS CARRY
PASS R0-COUNT
PASS R0-AUDIT
PASS SUITE-KERNEL
PASS SUITE-WASM
PASS ENCODER-SUBSET
PASS AXIOMS
PASS M0-E2E main=521
BENCH m0_e2e_1 median_ms=677.199 min_ms=309.302 max_ms=1485.977 runs=5
BENCH m0_e2e_2 median_ms=439.204 min_ms=353.436 max_ms=618.814 runs=5
BENCH m0_e2e_3 median_ms=432.310 min_ms=377.661 max_ms=571.466 runs=5
FAIL M0-TIME median_ms=439.204 bound_ms=150 load1=62.494 samples=3x5
BENCH m1_check_corpus median_ms=40.266 min_ms=33.296 max_ms=51.084 runs=5
MEASURE M0-RATIO kanon_ms=40.266 kanon_lines=1000 tot_ms=103.662 tot_lines=8138 ratio=3.161088 bound=2.000 load1=62.494
FAIL M0-RATIO kanon_ms=40.266 kanon_lines=1000 tot_ms=103.662 tot_lines=8138 ratio=3.161088 bound=2.000 load1=62.494
PASS TRUSTED-LINES
PASS DENOMINATORS
PASS HOUSE
PASS PIN sha=8cf0b8b
PASS POSITIVITY fixtures=22 negative=mu-nonpositive
PASS M1-CORPUS elapsed_ms=416.399 bound_ms=713 lines=1000 main=814 load1=62.494
PASS M1-SUITE ledger=16 focused-one=49 nat-runtime=20 surface=OK
FAIL AGREEMENT
MEASURE M0-RATIO tier=SLOW elapsed_ms=510.578 exit=1
LOAD AFTER (127.60986328125, 85.99951171875, 62.1220703125)
```

M0-TIME's three medians were 677.199, 439.204 and 432.310 ms; their
median was 439.204 ms.  M0-RATIO's corpus check median was 40.266 ms,
giving 3.161088 after the required per-line normalization.  Both failed
at one-minute load 62.494.  A quiet-machine regression verdict under
SL-B1 was not obtained.  M1-CORPUS passed at 416.399 ms, returning 814.

After all build and mutation tasks stopped, a standalone retry also
failed at load 63.640.  Its M0-TIME medians were 654.705, 567.048 and
432.928 ms, giving 567.048 ms.  Its M0-RATIO check median was 39.639 ms,
giving 3.111865.  These retries are retained in evidence/retry-2-time.log,
retry-2-ratio.log and retry-2.json.  No passing baseline is claimed.

AGREEMENT reached its unchanged 300-second SUITE watchdog and exited
124 after completing unary and full-range natAdd and natSub, 2,978 cases.
It did not finish all 7,445 cases.  Exact manifest regeneration and all
ten persistent source matrices passed comparison; that is source evidence,
not a replacement for completing execution.  The full result remains FAIL.

The kernel suite passed PARSE 127/127, CHECK and ERASE 76/76, NEG 51/51,
KNEG 2/2, REC 1/1 and MIGRATED 4/4.  The full Wasm golden suite passed.
M1-SUITE passed sixteen feature rows, all exact negative twins, 27 direct
and 22 surface One cases, 20 Nat runtime cases and 20 surface regressions.
New runtime fixtures return 42 and 3 on both hosts.  Independent surface
review also rejected ten adversarial parser, annotation and recursion probes.

### MEASURE table

```text
MEASURE M0-RATIO kanon_ms=40.266 kanon_lines=1000 tot_ms=103.662 tot_lines=8138 ratio=3.161088 bound=2.000 load1=62.494
MEASURE BUILD tier=SLOW elapsed_ms=3598.988 exit=0
MEASURE CARRY tier=MED elapsed_ms=2402.726 exit=0
MEASURE R0-COUNT tier=FAST elapsed_ms=665.852 exit=0
MEASURE R0-AUDIT tier=FAST elapsed_ms=248.324 exit=0
MEASURE SUITE-KERNEL tier=SUITE elapsed_ms=4203.299 exit=0
MEASURE SUITE-WASM tier=SUITE elapsed_ms=7125.111 exit=0
MEASURE ENCODER-SUBSET tier=FAST elapsed_ms=121.273 exit=0
MEASURE AXIOMS tier=MED elapsed_ms=77.868 exit=0
MEASURE M0-E2E tier=SLOW elapsed_ms=507.528 exit=0
MEASURE M0-TIME tier=SLOW elapsed_ms=11153.945 exit=1
MEASURE M0-RATIO tier=SLOW elapsed_ms=510.578 exit=1
MEASURE TRUSTED-LINES tier=FAST elapsed_ms=59.268 exit=0
MEASURE DENOMINATORS tier=MED elapsed_ms=99.927 exit=0
MEASURE HOUSE tier=MED elapsed_ms=391.917 exit=0
MEASURE PIN tier=FAST elapsed_ms=183.576 exit=0
MEASURE POSITIVITY tier=SUITE elapsed_ms=632.984 exit=0
MEASURE M1-CORPUS tier=SLOW elapsed_ms=568.765 exit=0
MEASURE M1-SUITE tier=SUITE elapsed_ms=16105.603 exit=0
MEASURE AGREEMENT tier=SUITE elapsed_ms=300037.444 exit=124
```

### Review and mutations

The surface review found no implementation defect.  Its missing structural
recursion sugar row was added to SPEC under SL-D9.  The gate review's
multiline catch-all finding was fixed and independently verified.  The
clean scanner passes; named, wildcard, typed and split-pipe multiline
controls fail.  HOUSE was rerun after the fix and passed.  The example
review's explicit agreement-witness and indentation findings were fixed.
All three required isolated mutations were caught; details are in the
Stage L mutation section.  They do not discharge a failing baseline leg.

### Handoff and evidence

Evidence root: /Users/oobi/Documents/gpt4/kanon-stage-l.  The entry manifest
is baseline.json; scope and workflow are in README.md; builder decisions
are in surface-result.md and gates-result.md; independent review is in
example-review.md, surface-review.md and gates-review.md.  The full output
and measurement state are evidence/battery-1.log and battery-1.json.
Mutation commands, exits and source hashes are under mutations/.

On a quiet machine, rerun the three open legs without changing constants:

```sh
zsh dev/gates.sh --leg time
zsh dev/gates.sh --leg ratio
zsh dev/gates.sh --leg agreement
```

Record their actual results before claiming Stage L PASS.  M1-EXIT still
requires the user commits, a green committed-tree battery and the user's
ratification.  F3 is closed for mu by the new spine; auto and nu remain
M2 work.  The optional Lean agreement theorem was not part of this stage.
