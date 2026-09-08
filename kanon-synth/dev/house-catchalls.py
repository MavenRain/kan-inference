#!/usr/bin/env python3
"""Check every simple OCaml catch-all against the two ruled function sites."""

from pathlib import Path
import re
import subprocess
import sys


def check(root):
    allowed = {}
    for row in (root / "dev/house-allow.txt").read_text().splitlines():
        fields = row.split("\t")
        if len(fields) != 4 or not all(fields):
            raise ValueError("HOUSE allow entries need path, function, arm and reason")
        path, function, arm, reason = fields
        key = (path, function)
        if key in allowed:
            raise ValueError("HOUSE allow entry is duplicated")
        allowed[key] = arm
    if set(allowed) != {("bin/host.ml", "of_exit"), ("bin/kanon.ml", "dispatch")}:
        raise ValueError("HOUSE allowlist must contain exactly the two D-M1-10 sites")
    result = subprocess.run(
        ["rg", "--files", "lib", "surface", "bin", "test", "wasm",
         "--glob", "*.ml", "--glob", "*.mli"], cwd=root,
        capture_output=True, text=True, check=True)
    # Cover a bare identifier, a wildcard and a parenthesized typed binder.
    catchall = re.compile(r"\|\s*(?:([a-z_][A-Za-z0-9_']*)|"
                          r"\(\s*([a-z_][A-Za-z0-9_']*)\s*(?::[^)]+)?\))\s*->")
    declaration = re.compile(r"^let\s+(?:rec\s+)?([a-z_][A-Za-z0-9_']*)\b", re.MULTILINE)
    used = set()
    bad = []
    for relative in result.stdout.splitlines():
        source = (root / relative).read_text()
        declarations = list(declaration.finditer(source))
        for match in catchall.finditer(source):
            if (match.group(1) or match.group(2)) in {"true", "false"}:
                continue
            preceding = [opening for opening in declarations if opening.start() < match.start()]
            function = preceding[-1].group(1) if preceding else None
            start = source.rfind("\n", 0, match.start()) + 1
            stop = source.find("\n", match.end())
            line = source[start:stop if stop >= 0 else len(source)]
            number = source.count("\n", 0, start) + 1
            key = (relative, function)
            if key in allowed and line.strip() == allowed[key] and key not in used:
                used.add(key)
            else:
                bad.append(f"{relative}:{number}:{line}")
    for key in allowed.keys() - used:
        bad.append(f"HOUSE stale allow entry: {key[0]}:{key[1]}")
    print("\n".join(bad), end="\n" if bad else "")
    return 1 if bad else 0


if __name__ == "__main__":
    try:
        raise SystemExit(check(Path(sys.argv[1]).resolve()))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"HOUSE named catch-all scan failed: {error}")
        raise SystemExit(1)
