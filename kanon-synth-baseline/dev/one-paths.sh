#!/bin/zsh
set -eu
chpwd_functions=()
unfunction chpwd 2>/dev/null || true
prep=${0:A:h}
root=${1:-$prep/..}
export PATH=/Users/oobi/.opam/zxcaml-p1/bin:$PATH
ocaml -I /Users/oobi/.opam/zxcaml-p1/lib/zarith \
  -I "$root/_build/default/lib/.kanon_kernel.objs/byte" \
  -I "$root/_build/default/lib" zarith.cma kanon_kernel.cma "$prep/one-paths.ml"
python3 -P - "$root" <<'PY'
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
driver = root / '_build/default/bin/kanon.exe'
positives = ['identity', 'branches', 'fields', 'shadowing', 'recursive', 'unreachable-capture']
negatives = ['used-twice', 'unused', 'zero-only', 'many-consumer', 'missing-branch',
             'tuple-duplication', 'let-duplication', 'closure-duplication',
             'shadowed-unused', 'field-unused', 'annotation-only',
             'scrutinee-branch', 'recursive-leg', 'unreachable-closure', 'eager-alias',
             'unreachable-capture']
rows = []
for directory, names, code in [('fixtures', positives, 0), ('neg', negatives, 1)]:
    for name in names:
        source = root / 'test' / directory / ('one-' + name + '.kan')
        result = subprocess.run([str(driver), 'check', str(source)],
                                text=True, capture_output=True, timeout=30)
        expected = '' if code == 0 else 'quantity: ' + source.with_suffix('.err').read_text().strip()
        good = result.returncode == code and result.stderr.strip() == expected
        rows.append(good)
        print(f"ONE-PATH {name} {'OK' if good else 'FAIL'} exit={result.returncode} expected={code} stderr={result.stderr.strip()!r}")
print(f"ONE-PATHS {sum(rows)}/{len(rows)} {'OK' if all(rows) else 'FAIL'}")
sys.exit(0 if all(rows) else 1)
PY
