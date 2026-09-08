#!/usr/bin/env python3
"""Permanent finite agreement evidence, approved 2026-09-06 (d)."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
DATA = HERE / "agreement-data"
BASE = """mu N : Type 0 with
| zero : N
| succ : N -> N

def Bool : Type 0 := sum ((prod () : Type 0), (prod () : Type 0))
def yes : Bool := inj 1 of 2 ()
def no : Bool := inj 0 of 2 ()
"""
ADD = "def rec uAdd : N -> N -> N := fun (n : N) (m : N) => case n as x in N return N with | zero => m | succ p => succ (uAdd p m)\n"
SUB = "def rec uSub : N -> N -> N := fun (n : N) (m : N) => case n as x in N return N with | zero => zero | succ p => (case m as y in N return N with | zero => n | succ q => uSub p q)\n"
MUL = "def rec uMul : N -> N -> N := fun (n : N) (m : N) => case n as x in N return N with | zero => zero | succ p => uAdd m (uMul p m)\n"
EQ = "def rec uEq : N -> N -> Bool := fun (n : N) (m : N) => case n as x in N return Bool with | zero => (case m as y in N return Bool with | zero => yes | succ q => no) | succ p => (case m as y in N return Bool with | zero => no | succ q => uEq p q)\n"
LT = "def rec uLt : N -> N -> Bool := fun (n : N) (m : N) => case n as x in N return Bool with | zero => (case m as y in N return Bool with | zero => no | succ q => yes) | succ p => (case m as y in N return Bool with | zero => no | succ q => uLt p q)\n"
OBS_ADD = "def rec observe : N -> Nat := fun (n : N) => case n as x in N return Nat with | zero => 0 | succ m => (case m as y in N return Nat with | zero => 1 | succ p => let r : Nat := observe m in natSub (natMul 2 r) (natSub r 1))\n"
OBS_OTHER = "def rec observe : N -> Nat := fun (n : N) => case n as x in N return Nat with | zero => 0 | succ m => natAdd 1 (observe m)\n"
OPS = {
    "natAdd": (ADD, OBS_ADD, "uAdd", "Nat", lambda a, b: a + b),
    "natSub": (SUB, OBS_OTHER, "uSub", "Nat", lambda a, b: max(0, a - b)),
    "natMul": (ADD + MUL, OBS_OTHER, "uMul", "Nat", lambda a, b: a * b),
    "natEq": (EQ, "", "uEq", "Bool", lambda a, b: a == b),
    "natLt": (LT, "", "uLt", "Bool", lambda a, b: a < b),
}
VALUES = [0, 1, 2, 2**15 - 1, 2**15, 2**15 + 1,
          2**30 - 2, 2**30 - 1, 2**30, 2**30 + 1,
          2**31 - 1, 2**31, 2**31 + 1, 2**62 - 1, 2**62,
          2**64 - 1, 2**64, 10**100 - 1, 10**100, 10**100 + 1]


def family(ty):
    return (f"mu Agreement : (0 a : {ty}) -> (0 b : {ty}) -> Type 0 with\n"
            f"| same : (0 a : {ty}) -> Agreement a a\n")


def unary_source(primitive):
    definition, observer, unary, ty, _ = OPS[primitive]
    if primitive in definition + observer:
        raise ValueError("unary oracle calls the tested primitive")
    source = BASE + definition + observer + family(ty)
    source += "def n0 : N := zero\n"
    source += "".join(f"def n{i} : N := succ n{i - 1}\n" for i in range(1, 33))
    for a in range(33):
        for b in range(33):
            observed = f"({unary} n{a} n{b})"
            if ty == "Nat":
                observed = "(observe " + observed + ")"
            source += (f"def agree{a * 33 + b} : Agreement {observed} "
                       f"({primitive} {a} {b}) := same {observed}\n")
    return source


def oracle_cases(primitive):
    operation = OPS[primitive][4]
    return [{"primitive": primitive, "left": str(a), "right": str(b),
             "expected": operation(a, b) if primitive in ("natEq", "natLt")
             else str(operation(a, b))} for a in VALUES for b in VALUES]


def full_source(primitive, cases):
    ty = OPS[primitive][3]
    source = BASE.split("def Bool", 1)[1]
    source = "def Bool" + source + "def Unit : Type 0 := prod ()\n" + family(ty)
    for i, row in enumerate(cases):
        expected = row["expected"]
        literal = ("yes" if expected else "no") if ty == "Bool" else expected
        value = f"({primitive} {row['left']} {row['right']})"
        source += f"def agree{i} : Agreement {value} {literal} := same {value}\n"
        condition = value if ty == "Bool" else f"(natEq {value} {literal})"
        zero, one = ("0", "1") if ty == "Nat" or expected else ("1", "0")
        source += (f"def test{i} : Nat := case {condition} as x return Nat "
                   f"with | 0 (u : Unit) => {zero} | 1 (u : Unit) => {one}\n")
    total = "0"
    for i in reversed(range(len(cases))):
        total = f"(natAdd test{i} {total})"
    source += f"def main : Nat := {total}\n"
    return source


def expected_files(root):
    rows = []
    for primitive in OPS:
        cases = oracle_cases(primitive)
        rows.append(("unary", primitive, root / "test" / "agreement" /
                     f"agreement-{primitive}.kan", unary_source(primitive), 1089))
        rows.append(("full-range", primitive, DATA / "full-range" /
                     f"reference-{primitive}.kan", full_source(primitive, cases), 400))
    return rows


def manifest(root):
    return {"ruling": "2026-09-06 (d)",
            "oracle": "Independent Python integer arithmetic, no Zarith or emitted code",
            "unary_operands": list(range(33)), "full_range_operands": list(map(str, VALUES)),
            "unary_cases": 5445, "full_range_cases": 2000, "total_cases": 7445,
            "cases": [row for primitive in OPS for row in oracle_cases(primitive)],
            "files": [{"kind": kind, "primitive": primitive, "name": path.name,
                       "count": count, "sha256": hashlib.sha256(src.encode()).hexdigest()}
                      for kind, primitive, path, src, count in expected_files(root)]}


def command(argv, log, timeout=300, input_text=None):
    started = time.monotonic()
    try:
        proc = subprocess.run(list(map(str, argv)), capture_output=True, text=True,
                              timeout=timeout, input=input_text)
        row = {"command": list(map(str, argv)), "exit": proc.returncode,
               "stdout": proc.stdout, "stderr": proc.stderr}
    except subprocess.TimeoutExpired as failure:
        def decoded(value):
            return value.decode(errors="replace") if isinstance(value, bytes) else value or ""
        row = {"command": list(map(str, argv)), "exit": None, "timeout_seconds": timeout,
               "stdout": decoded(failure.stdout), "stderr": decoded(failure.stderr)}
    row["seconds"] = round(time.monotonic() - started, 6)
    if input_text is not None:
        row["stdin_sha256"] = hashlib.sha256(input_text.encode()).hexdigest()
    log.append(row)
    return row


def verify(root, only, mutation, out):
    report = {"ruling": "2026-09-06 (d)", "status": "FAIL", "rows": []}
    out.mkdir(exist_ok=True, parents=True)
    actual_manifest = json.loads((DATA / "agreement-reference.json").read_text())
    if actual_manifest != manifest(root):
        raise ValueError("reference manifest changed or has incomplete coverage")
    kanon = root / "_build" / "default" / "bin" / "kanon.exe"
    passed = 0
    selected = 0
    for kind, primitive, path, src, count in expected_files(root):
        if only and kind != only:
            continue
        selected += count
        row = {"kind": kind, "primitive": primitive, "cases": count, "commands": []}
        report["rows"].append(row)
        source_ok = path.is_file() and path.read_text() == src
        # Mutation mode still executes the checker on the selected altered source.
        if not path.is_file() or (not source_ok and not mutation):
            row["error"] = "missing or changed source matrix"
            row["pass"] = False
        else:
            roundtrip_ok = True
            if kind == "unary":
                parsed = command(["zsh", HERE / "agreement-roundtrip.sh", root],
                                 row["commands"], input_text=path.read_text())
                roundtrip_ok = parsed["exit"] == 0 and parsed["stdout"].strip() == "ROUNDTRIP OK"
            check = command([kanon, "check", "--print", path], row["commands"])
            axioms = command([kanon, "axioms", path], row["commands"])
            ok = roundtrip_ok and check["exit"] == 0 and axioms["exit"] == 0 and axioms["stdout"].strip() == ""
            if kind == "unary" and ok:
                checked = root / "test" / "golden" / (path.stem + ".checked")
                erased = root / "test" / "golden" / (path.stem + ".erased")
                erased_result = command([kanon, "check", "--erased", path], row["commands"])
                ok = (checked.is_file() and checked.read_text() == check["stdout"]
                      and erased.is_file() and erased_result["exit"] == 0
                      and erased.read_text() == erased_result["stdout"])
            for i, result in enumerate(row["commands"]):
                if len(result.get("stdout", "")) > 4096:
                    capture = out / f"{kind}-{primitive}-{i}.stdout"
                    capture.write_text(result["stdout"])
                    result["stdout_path"] = str(capture)
                    result["stdout"] = ""
            if kind == "full-range" and ok:
                for host in ("kernel", "node", "wasmtime"):
                    observed = command([kanon, "run", path, "--export", "main", "--host", host], row["commands"])
                    ok = observed["exit"] == 0 and observed["stdout"].strip() == str(count) and ok
            row["pass"] = ok and (source_ok or mutation)
        if row["pass"]:
            passed += count
        print(f"AGREEMENT {kind} {primitive} {count if row['pass'] else 0}/{count} "
              f"{'OK' if row['pass'] else 'FAIL'}", flush=True)
        (out / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    complete = not only and selected == 7445 and passed == selected
    report.update(passed=passed, selected=selected, status="PASS" if complete else "FAIL")
    filename = "results.json" if not only else only + "-results.json"
    (out / filename).write_text(json.dumps(report, indent=2) + "\n")
    print(f"AGREEMENT {'OK' if complete else 'PARTIAL' if only and passed == selected else 'FAIL'} {passed}/{selected}", flush=True)
    return 0 if passed == selected and (complete or only) else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=HERE.parent)
    parser.add_argument("--generate", action="store_true")
    parser.add_argument("--only", choices=["unary", "full-range"])
    parser.add_argument("--mutation", action="store_true")
    parser.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    if args.generate:
        for _, _, path, source, _ in expected_files(args.root):
            path.parent.mkdir(exist_ok=True, parents=True)
            path.write_text(source)
        (DATA / "agreement-reference.json").write_text(json.dumps(manifest(args.root), indent=2) + "\n")
        print("GENERATED: 5445 unary witnesses and 2000 independent full-range cases")
        return 0
    evidence = args.evidence or args.root / ".gatework" / "agreement"
    return verify(args.root, args.only, args.mutation, evidence)


if __name__ == "__main__":
    raise SystemExit(main())
