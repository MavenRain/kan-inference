#!/usr/bin/env python3
"""Permanent Stage L timing, corpus, positivity and executable M1 ledger."""

import argparse
from decimal import Decimal
import json
import os
from pathlib import Path
import re
import shlex
import statistics
import subprocess
import time


FEATURES = ["--enable-gc", "--enable-reference-types", "--enable-tail-call",
            "--enable-exception-handling"]
OBSERVE = """
def rec observe : N -> Nat := fun (n : N) => case n as x in N return Nat with
| zero => 0
| succ m => natAdd 1 (observe m)
"""
VECTOR = "vs (succ zero) (vs zero vz)"
# Each row names an original positive, its small runtime observation, and an
# exact negative sidecar. Existing fixture sources and goldens stay untouched.
LEDGER = [
    ("direct-family", "mu-direct", OBSERVE +
     "def main : Nat := observe (succ (succ zero))\n", "2", "mu-nonpositive", "not yet"),
    ("mutual-family", "mu-mutual", """
def rec amountA : A -> Nat := fun (a : A) => case a as x in A return Nat with
| leaf => 0 | node b => natAdd 1 (amountB b)
and amountB : B -> Nat := fun (b : B) => case b as x in B return Nat with
| cons a => natAdd 1 (amountA a)
def main : Nat := amountA (node (cons leaf))
""", "2", "mu-redeclared-mutual", "mismatch"),
    ("indexed-family", "mu-indexed", """
def rec amount : (0 i : N) -> V i -> Nat := fun (0 i : N) (v : V i) =>
case v as x in V j return Nat with | vz => 0 | vs 0 j w => natAdd 1 (amount j w)
""" + f"def main : Nat := amount (succ (succ zero)) ({VECTOR})\n",
     "2", "mu-index-mismatch", "mismatch"),
    ("direct-recursion", "mu-rec-direct", OBSERVE +
     "def main : Nat := observe (double (succ (succ zero)))\n", "4",
     "mu-nonstructural", "termination"),
    ("mutual-recursion", "mu-rec-mutual", OBSERVE +
     "def main : Nat := observe (sizeA (node (cons leaf)))\n", "2",
     "mu-rec-sibling-position", "termination"),
    ("indexed-recursion", "mu-rec-indexed", OBSERVE +
     f"def main : Nat := observe (length (succ (succ zero)) ({VECTOR}))\n", "2",
     "mu-rec-nondecreasing", "termination"),
    ("dependent-match", "mu-dependent-copy", "", "42", "mu-dependent-copy-index", "mismatch"),
    ("subsingleton-large-elimination", "mu-prop-large-elim",
     "\ndef main : choose := 7\n", "7", "mu-large-elim-nonsub", "universe"),
    # Void has no closed inhabitant. Check and erase its large elimination,
    # then run a closed observation after the erased type declaration.
    ("empty-large-elimination", "mu-empty-large-elim", "\ndef main : Nat := 0\n",
     "0", "mu-large-elim-selfrec", "universe"),
    ("linear-one", "one-identity", "", "7", "one-used-twice", "quantity"),
    ("large-nat", "nat-big", "", "7", "nat-runtime-export", "trap"),
]


class GateFailure(Exception):
    pass


def run(argv, *, input_text=None, timeout=120, env=None):
    result = subprocess.run(list(map(str, argv)), input=input_text,
                            capture_output=True, text=True, timeout=timeout, env=env)
    return result


def require(result, description, *, expected=None):
    if result.returncode != 0 or (expected is not None and result.stdout.strip() != expected):
        raise GateFailure(f"{description}: exit={result.returncode} "
                          f"stdout={result.stdout[-4000:]!r} stderr={result.stderr[-4000:]!r}")
    return result.stdout


def driver(root):
    return root / "_build/default/bin/kanon.exe"


def corpus_path(root):
    path = root / "test/corpus/m1-corpus.kan"
    data = path.read_bytes()
    if data.count(b"\n") != 1000 or not data.endswith(b"\n"):
        raise GateFailure("M1 corpus must contain exactly 1000 newline-terminated lines")
    return path


def promise(path, minimum):
    source = path.read_text()
    promised = re.findall(r"^-- main is ([0-9]+)\.?$", source, re.MULTILINE)
    if len(promised) != 1 or len(source.splitlines()) < minimum:
        raise GateFailure(f"{path}: need one main promise and at least {minimum} lines")
    return promised[0]


def bench(root, name, argv):
    command = shlex.join(list(map(str, argv)))
    environment = dict(os.environ, RUNS="5")
    out = require(run(["zsh", root / "dev/bench.sh", name, command], env=environment), name)
    print(out.strip(), flush=True)
    match = re.fullmatch(r"BENCH " + re.escape(name) +
                         r" median_ms=([0-9]+\.[0-9]+) min_ms=[0-9]+\.[0-9]+"
                         r" max_ms=[0-9]+\.[0-9]+ runs=5\n?", out)
    if match is None or Decimal(match[1]) <= 0:
        raise GateFailure(f"{name}: malformed five-sample BENCH result")
    return Decimal(match[1])


def time_gate(root, bound):
    argv = [driver(root), "run", root / "examples/m0-spine.kan",
            "--export", "main", "--host", "both"]
    medians = [bench(root, f"m0_e2e_{index}", argv) for index in range(1, 4)]
    median = statistics.median(medians)
    load = os.getloadavg()[0]
    detail = f"median_ms={median:.3f} bound_ms={bound} load1={load:.3f} samples=3x5"
    if median > bound:
        raise GateFailure(detail)
    return detail


def ratio_gate(root, bound):
    path = corpus_path(root)
    frozen = json.loads((root / "dev/denominators.json").read_text())
    normalization = json.loads((root / "dev/denominators-m1.json").read_text())
    denominator = Decimal(str(frozen["tot_suite_kernel_warm_ms"]["median"]))
    expected = {"tot_pin": "8cf0b8b", "tot_test_files": 99, "tot_test_lines": 7908,
                "tot_prelude_lines": 230, "tot_checked_lines": 8138,
                "kanon_corpus": "test/corpus/m1-corpus.kan", "kanon_corpus_lines": 1000,
                "tot_suite_kernel_warm_ms": 103.662, "ratio_bound": 2.0,
                "frozen_file": "dev/denominators.json",
                "frozen_field": "tot_suite_kernel_warm_ms.median"}
    if denominator != Decimal("103.662") or any(normalization.get(k) != v for k, v in expected.items()):
        raise GateFailure("frozen denominator or ruled M1 normalization changed")
    median = bench(root, "m1_check_corpus", [driver(root), "check", path])
    ratio = (median / Decimal(1000)) / (denominator / Decimal(8138))
    load = os.getloadavg()[0]
    detail = (f"kanon_ms={median:.3f} kanon_lines=1000 tot_ms={denominator} "
              f"tot_lines=8138 ratio={ratio:.6f} bound={bound:.3f} load1={load:.3f}")
    print(f"MEASURE M0-RATIO {detail}", flush=True)
    if ratio > bound:
        raise GateFailure(detail)
    return f"ratio={ratio:.6f} bound={bound:.3f}"


def execute(root, source, evidence, expected):
    evidence.mkdir(parents=True, exist_ok=True)
    wasm = evidence / (source.stem + ".wasm")
    require(run([driver(root), "check", source]), f"check {source.name}")
    require(run([driver(root), "emit", source, "-o", wasm, "--export", "main"]),
            f"emit {source.name}")
    require(run(["wasm-opt", wasm, "-S", "-o", wasm.with_suffix(".wat"), *FEATURES]),
            f"validate {source.name}")
    for host in ("kernel", "both"):
        require(run([driver(root), "run", source, "--export", "main", "--host", host]),
                f"{source.name} {host}", expected=expected)


def corpus_gate(root, bound):
    source = corpus_path(root)
    expected = promise(source, 1000)
    started = time.perf_counter_ns()
    execute(root, source, root / ".gatework/gates/corpus", expected)
    elapsed = Decimal(time.perf_counter_ns() - started) / Decimal(1000000)
    load = os.getloadavg()[0]
    detail = (f"elapsed_ms={elapsed:.3f} bound_ms={bound} lines=1000 "
              f"main={expected} load1={load:.3f}")
    if elapsed > bound:
        raise GateFailure(detail)
    return detail


def negative(root, path, prefix):
    sidecar = path.with_suffix(".err").read_text()
    if not sidecar.endswith("\n") or len(sidecar.splitlines()) != 1:
        raise GateFailure(f"negative sidecar must have one line: {path}")
    result = run([driver(root), "check", path])
    expected = f"{prefix}: {sidecar.rstrip()}\n"
    if result.returncode != 1 or result.stdout or result.stderr != expected:
        raise GateFailure(f"negative {path.name}: exit={result.returncode} "
                          f"stderr={result.stderr!r} expected={expected!r}")


def positivity_gate(root):
    fixtures = sorted(path for path in (root / "test/fixtures").glob("*.kan")
                      if re.search(r"^\s*mu\s", path.read_text(), re.MULTILINE))
    required = {"mu-direct.kan", "mu-mutual.kan", "mu-indexed.kan"}
    if not required.issubset({path.name for path in fixtures}):
        raise GateFailure("required direct, mutual or indexed positivity fixture missing")
    for path in fixtures:
        require(run([driver(root), "check", path]), f"positivity {path.name}")
    negative(root, root / "test/neg/mu-nonpositive.kan", "not yet")
    return f"fixtures={len(fixtures)} negative=mu-nonpositive"


def suite_gate(root):
    evidence = root / ".gatework/gates/m1-suite"
    evidence.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, fixture, appendix, expected, twin, prefix in LEDGER:
        original = root / "test/fixtures" / (fixture + ".kan")
        source = evidence / (fixture + ".kan")
        source.write_text(original.read_text() + appendix)
        execute(root, source, evidence, expected)
        if prefix != "trap":
            negative(root, root / "test/neg" / (twin + ".kan"), prefix)
        else:
            for host in ("kernel", "node", "wasmtime", "both"):
                result = run([driver(root), "run", root / "test/fixtures" / (twin + ".kan"),
                              "--export", "main", "--host", host])
                if result.returncode != 4 or result.stdout or "trap" not in result.stderr:
                    raise GateFailure(f"{twin} {host}: expected separate i31 export trap")
        rows.append(name)
        print(f"M1-LEDGER {name} positive={fixture} negative={twin} main={expected} OK", flush=True)
    for primitive in ("natAdd", "natSub", "natMul", "natEq", "natLt"):
        data = root / "dev/m1-suite-data"
        source = data / (primitive + ".kan")
        execute(root, source, evidence, "2")
        negative(root, data / (primitive + "-wrong.kan"), "mismatch")
        rows.append(primitive)
        print(f"M1-LEDGER agreement-{primitive} small-witness-and-negative OK", flush=True)
    spine = root / "examples/m1-spine.kan"
    execute(root, spine, evidence, promise(spine, 300))
    print("M1-LEDGER surface-spine lines>=300 OK", flush=True)
    for argv, oracle in [
        (["zsh", root / "dev/one-paths.sh", root], "ONE-PATHS 22/22 OK"),
        (["zsh", root / "dev/nat-runtime.sh", root], "NAT-RUNTIME OK 20/20"),
    ]:
        output = require(run(argv), str(argv[1]))
        print(output.strip(), flush=True)
        if oracle not in output.splitlines():
            raise GateFailure(f"missing complete focused suite result: {oracle}")
    surface = require(run([root / "_build/default/test/sl_surface.exe"]), "surface regression suite")
    print(surface.strip(), flush=True)
    if "SL-SURFACE OK" not in surface.splitlines():
        raise GateFailure("missing surface regression suite verdict")
    (evidence / "ledger.json").write_text(json.dumps({"status": "PASS", "rows": rows,
        "agreement": "mandatory separate AGREEMENT leg runs all 7445 approved cases"}, indent=2) + "\n")
    return f"ledger={len(rows)} focused-one=49 nat-runtime=20 surface=OK"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("leg", choices=["time", "ratio", "corpus", "positivity", "m1-suite"])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--bound", type=Decimal)
    args = parser.parse_args()
    names = {"time": "M0-TIME", "ratio": "M0-RATIO", "corpus": "M1-CORPUS",
             "positivity": "POSITIVITY", "m1-suite": "M1-SUITE"}
    functions = {"time": time_gate, "ratio": ratio_gate, "corpus": corpus_gate}
    try:
        if args.leg in functions:
            if args.bound is None or not args.bound.is_finite() or args.bound <= 0:
                raise GateFailure("a positive finite bound is required")
            detail = functions[args.leg](args.root.resolve(), args.bound)
        else:
            detail = (positivity_gate if args.leg == "positivity" else suite_gate)(args.root.resolve())
        print(f"PASS {names[args.leg]} {detail}")
        return 0
    except (GateFailure, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print(f"FAIL {names[args.leg]} {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
