# kanon

The [foundation audit](dev/FOUNDATION-AUDIT.md) records the current limits of
the strict Kan-only and Lean-parity claims, the conditional initiality proof,
and the indexed-vector runtime regression.

Kan extensions are the sole type former: every type in kanon is a left or
a right Kan extension of a diagram along a shape.

Status: M0 Stage E.  The skeleton, the closed term grammar, the carried
kernel leaves, the R0 counts, the lexer, the parser, the surface printer,
the evaluator, conversion, the checker, the elaborator, erasure, the
totality entry point, WasmGC emission and the `kanon run` driver are
built.

## Checking a file

`kanon check FILE` parses the file, elaborates every declaration to the
kernel grammar and checks it against the declarations before it.  It
prints nothing and exits 0 when the whole file checks, and prints one
line on stderr and exits 1 when it does not, so a caller reads stdout as
the answer alone.  `kanon check --print FILE` adds the checked form of
every entry to stdout, one `def NAME : TYPE := BODY` or `axiom NAME :
TYPE` line per declaration, in kernel terms and in declaration order;
the golden files under test/golden hold exactly that text.  `kanon
axioms FILE` prints what the file postulates, one name per line in
declaration order, and prints nothing for a file that postulates
nothing, so the trust base of a checked file is one command away.  A
missing file and an unknown command exit 64, which a caller tells from
the exit 1 of a file that does not check.

## Erasing a file

`kanon check --erased FILE` checks the file first and then prints the
erased program to stdout, in declaration order.  Erasure drops every
type, every proposition, every proof and every binder the checker
stamped `0`, so the printed program holds the runtime content alone.  A
declaration with no runtime content prints as `erased NAME`.  A
postulate with a runtime type prints as `axiom NAME : REPR`, which the
host must supply.  A definition prints as one `rec [TID; ..]` line, the
types it names, and then one `fun` line for each function it lifts and
one for its own function.  The golden files test/golden/NAME.erased
hold exactly that text, one beside every test/golden/NAME.checked, and
the ERASE group of the suite compares the two byte for byte.

## Emitting a module

`kanon emit FILE -o OUT.wasm --export NAME` checks the file, erases it
and writes one WasmGC module to OUT.wasm.  The argument order is fixed.
The named definition must be a `Nat` of arity zero:  the module exports
one function with no parameter and an i32 answer, which calls that
definition and reads the answer out of its i31.  The command prints
nothing and exits 0 on success.  A file that does not check exits 1, as
`kanon check` does.  A form the emitter refuses prints one
`kanon: emit: MESSAGE` line on stderr and exits 2;  the refusals are a
postulate with no body, a literal outside the range 0 to 1073741823, an
export that is not a `Nat` of arity zero, and the delayed forms that
arrive at M2.  A usage error and a directory that does not exist exit
64.

`node dev/run-node.mjs OUT.wasm NAME` runs the module with no import and
prints the answer in decimal.  It exits 0 with the answer, 1 with a
`trap: MESSAGE` line when the module traps, 2 with an `invalid: MESSAGE`
line when the engine refuses the module, and 64 on a usage error.  A
natural rides in an i31, so an answer above 1073741823 is a trap and not
a wrapped number.

```
_build/default/bin/kanon.exe emit test/fixtures/d01-lit-prims.kan \
  -o /tmp/d01.wasm --export main
node dev/run-node.mjs /tmp/d01.wasm main        # prints 17
_build/default/test/wasm.exe test               # the emission suite
zsh dev/encoder-subset.sh                       # the opcodes of SPEC.md
```

The emission suite reads every fixture that checks and defines `main`.
For each one it emits the module, assembles it with wasm-opt, compares
the text form with test/golden/NAME.wat byte for byte, takes the value
of `main` from the kernel alone and compares the answer of the node
runner with it.  It prints one `EMIT NAME OK` line per fixture, then
`WASM-OK P/T`, then `SUITE-WASM OK` or `SUITE-WASM FAIL`.  The modules
and their text forms land in `_build/wasm-suite`, or in the directory of
the second argument.

## Running a module

`kanon run FILE --export NAME [--host node|wasmtime|kernel|both]` checks
the file, erases it, emits one module that exports NAME and runs that
module.  The argument order is fixed, and any other shape is a usage
error.  The module goes to a temporary file, which leaves with its two
capture files when the run ends, so a run writes nothing into the tree.

```sh
kanon run test/fixtures/d06-closure-capture.kan --export main
kanon run test/fixtures/d06-closure-capture.kan --export main --host kernel
```

There are four host words.  `node` runs the module through
`dev/run-node.mjs`, and `wasmtime` runs it through
`dev/run-wasmtime.sh`.  Each runner prints the answer in decimal on
stdout and exits 0, prints `trap: TEXT` on stderr and exits 1, or prints
`invalid: TEXT` on stderr and exits 2.  `kernel` runs no module.  It
reduces the exported global with the evaluator, the oracle that the
emission suite trusts.  `both` runs node and then wasmtime and compares
the two answers, and `both` is the default when `--host` is absent.

The driver finds the two runners beside the executable, at the root four
directories above `_build/default/bin/kanon.exe`.  A runner that is not
at that root is a usage error that names the file it wants.

The answer alone goes to stdout, so a caller reads one decimal number.
Every diagnosis goes to stderr, as one line:  `kanon: run: HOST trap:
TEXT`, `kanon: run: HOST invalid: TEXT`, `kanon: run: trap on both
hosts`, or `kanon: run: hosts disagree: node OUTCOME wasmtime OUTCOME`,
where an outcome is the value or the word `trap`.

The exit codes are these.  0 is an answer, and the hosts that ran agree
on it.  1 is a file that does not check.  2 is an emission the wasm back
end refuses, or a host that refuses the module.  3 is two hosts that
disagree.  4 is a trap, on one host, on both hosts, or in the kernel,
where a value outside the i31 range is the trap that the module raises.
64 is a usage error, a missing file or a missing runner.

## The spine

`examples/m0-spine.kan` is the M0 spine.  It postulates nothing, so
`kanon axioms examples/m0-spine.kan` prints nothing and exits 0.  Its
`main` is a `Nat` of arity zero, and the kernel, node and wasmtime all
answer `521`.

```sh
kanon run examples/m0-spine.kan --export main --host kernel
kanon run examples/m0-spine.kan --export main --host both
```

The file holds every row of the emission table of SPEC.md section 8.1:
the five prims, where `natSub` stops at zero and `natEq` and `natLt`
answer the two leg sum that a case reads back into a `Nat`;  a chain of
tail calls through a helper of arity two;  a pair built and projected on
both sides;  a three leg tuple built and projected;  a sum with two
payload free legs and two payload legs, cased on every leg, beside a
case that writes `as x return T`;  a closure with a parameter capture
and a closure with a let bound capture, each stored in a pair and
applied later;  a partial application under the arity and an application
over it;  a call through a function parameter, which reaches the generic
`apply<k>`;  the erased polymorphic identity used at `Nat`;  a nested
let with a case inside it;  the annotation form;  the literals;  and a
function over the empty sum, which carries the `unreachable` row without
a trap, because `main` never calls it.

It holds every production of the surface grammar of SPEC.md section 9
that M0 accepts.  The `(1 x : Nat)` binder is its own first witness,
because no fixture writes one.  The three words `auto`, `mu` and `nu`
are refusals at M0, so the spine omits them.  A comment block at the top
of the file names the row and the production of every definition, and
the line `-- main is 521` is the promise that the M0-E2E leg reads.

## The closure ABI

A function with a known name and a known arity is called through its own
typed signature, where each parameter and the answer keeps the runtime
type of its erased repr.  Every other head is a closure.  A closure is
one struct of three immutable fields:  the arity as an i32, the code as
a function reference, and the environment as an eq reference, which
holds a struct of the captures or a tagged zero when there is no
capture.  The code of a closure has the generic signature `fn<n>`, where
the environment, every argument and the answer are eq references, so one
wrapper joins the two conventions:  it reads the captures out of the
environment, casts each capture and argument to its typed form, and tail calls the
typed code.  A call whose arity the caller does not know goes through
the helper `apply<k>`, which reads the arity out of the closure:  an
equal arity is a tail call of the code, a smaller arity calls the code
and applies the arguments that are left to the answer, and a larger
arity builds a partial application that holds the closure and the
arguments so far.

Pairs, tuples and closure environments store their runtime fields as eq
references, and sum payloads use eq references too.  Field reads cast to
the checked type.  This keeps aggregate layouts compatible when an erased
type parameter is instantiated.  Cases retain their checked sum type,
so a sum returned through a generic call still has its branch information.

## Layout

```
dune-project        (lang dune 3.24) (name kanon)
PIN                 the vendored tot sha
SPEC.md             the closed grammar, the R0 counts, the sugar table
vendor/tot/         git submodule, checked out at PIN
lib/                library kanon_kernel
surface/            library kanon_surface
wasm/               library kanon_wasm: gc_encode.ml, link.ml, emit.ml
bin/kanon.ml        driver: check | emit | run | axioms | spec-count
bin/host.ml         the three hosts that kanon run reaches
examples/           m0-spine.kan, the M0 spine
test/               main.ml, wasm.ml, sys_io.ml, fixtures/*.kan,
                    golden/*.checked, golden/*.erased, golden/*.wat,
                    neg/*.kan
dev/                the runners, the gate scripts and the logs
```

## Build and test

The OCaml toolchain is in the zxcaml-p1 opam switch, which is not on the
default PATH.  Two runner scripts add it and set the root, so you can call
them from any directory:

```
zsh dev/dunecho.sh build          # build, warnings are errors
zsh dev/dune.sh clean             # remove _build
zsh dev/carry-check.sh            # the carried files match the pin
zsh dev/r0-count.sh               # spec-count agrees with SPEC.md
zsh dev/encoder-subset.sh         # the goldens hold no opcode past SPEC.md
zsh dev/house.sh                  # the house rules over lib, bin, test, wasm
zsh dev/r0-audit.sh               # no shape name outside its four files
zsh dev/trusted-lines.sh          # the kernel and the encoder line bounds
zsh dev/gates.sh                  # the whole gate battery, every leg
_build/default/test/main.exe test               # the kernel suite
_build/default/test/wasm.exe test               # the emission suite
```

Each script finds the repository root from its own path, so a copy of the
tree builds and checks itself.

## Gates

`zsh dev/gates.sh` runs the whole M0 battery.  Every leg prints one
`PASS LEG` line, or one `FAIL LEG` line and then the output that the leg
captured.  BUILD is the one leg that ends the run when it fails, because
every later leg reads the build it makes.  Every other leg runs even
when an earlier leg failed, so one run names every failing leg.  The
fifteen legs, in order:

```
BUILD            dev/dunecho.sh build prints 0 errors, 0 warnings
CARRY            the carried files still match the pin
R0-COUNT         kanon spec-count agrees with SPEC.md
R0-AUDIT         no shape name outside the four files that own it
SUITE-KERNEL     test/main.exe prints SUITE-KERNEL OK
SUITE-WASM       test/wasm.exe prints SUITE-WASM OK
ENCODER-SUBSET   the goldens hold no opcode past SPEC.md section 8
AXIOMS           b08 discloses Bit and the spine discloses nothing
M0-E2E           check, emit, wasm-opt, kernel and both hosts on the spine
M0-TIME          the median of the spine's run stays under the bound
M0-RATIO         this kernel suite against tot's warm kernel suite
TRUSTED-LINES    the kernel eight and the encoder stay under their bounds
DENOMINATORS     dev/denominators.json matches its sha256 row
HOUSE            the house rules over lib, surface, bin, test and wasm
PIN              PIN, vendor/tot and the pin worktree name one sha
```

Three legs carry a value in the verdict line:  `PASS M0-E2E main=521`,
`PASS M0-TIME median_ms=X bound_ms=150` and `PASS M0-RATIO ratio=R`.

After the last leg the script prints the MEASURE block, one line per leg
in the same order:

```
MEASURE BUILD tier=SLOW elapsed_ms=159.862 exit=0
```

The tier is the hang ceiling that the leg runs under, one of FAST, MED,
SLOW and SUITE, and `elapsed_ms` comes from the zsh clock, which
resolves microseconds.  The script then prints `GATES-OK` and exits 0,
or `GATES-FAIL` and exits 1.

The M0-TIME bound is 150 ms.  The variable `M0_TIME_MS` near the top of
dev/gates.sh holds it.  The timed command is the driver's whole run path
over the spine, that is check, erase, emit, node and wasmtime;  wasm-opt
is a step of M0-E2E and stays outside the timing.

M0-RATIO is informational at M0.  It divides the median of this tree's
kernel suite by the median of tot's warm kernel suite, which
dev/denominators.json holds at 103.662 ms.  The leg fails on a bench
error or on a denominator it cannot read, never on the value.

Work files live under `.gatework/gates/`, which .gitignore holds.

## Carried code

lib/level.ml, lib/level.mli, lib/quantity.ml, lib/literal.ml,
lib/global.ml, lib/budget.ml and lib/budget.mli come from tot at the sha
in PIN.  Each starts with a comment line that names its origin and its
delta.  dev/CARRIED.md holds the diff line count for each one, and
dev/carry-check.sh recomputes them.

## License

MIT OR Apache-2.0.  See LICENSE-MIT and LICENSE-APACHE.
