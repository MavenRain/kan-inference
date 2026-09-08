#!/bin/zsh
# dev/house.sh:  the HOUSE gate (SD-G11) as an executable command.
#
# Usage:  zsh ROOT/dev/house.sh [ROOT]
#
# The gate has five legs.  Legs 1, 2, 4 and 5 must print nothing, leg 3
# must print exactly one line.  The script prints one verdict line per
# leg, then HOUSE OK and exit 0, or HOUSE FAIL and exit 1.
#
# SD-D21:  the em-dash leg of the brief is written with the exclusion
# globs '!vendor/**' and '!_build/**'.  ripgrep 15.1.0 on this machine
# does not honor that form:  it still reads vendor/tot, so the leg was
# reported clean while it had never excluded the vendor tree.  The
# forms '!vendor' and '!**/vendor/**' are honored, and this script uses
# both.  The pattern is written as a unicode escape, so that the file
# that checks for the character does not hold one.
set -u

root=${1:-${0:A:h:h}}
fail=0

emdash=$'\u2014'
pat_house='raise |failwith|assert |exception |List\.nth|\.\('
pat_state='\bref\b|\bmutable\b|Array\.|Hashtbl|Buffer\.'
pat_bool='true ->|false ->'

report_empty () {
  local name=$1 out=$2
  if [[ -z $out ]]; then
    print -r -- "HOUSE $name OK"
  else
    print -r -- "HOUSE $name FAIL"
    print -r -- "$out"
    fail=1
  fi
}

# Leg 1: no exception, unapproved catch-all, List.nth or unsafe index.
# SL-D16: allow entries identify a function and exact arm, so line shifts
# cannot authorize another catch-all or invalidate the two ruled sites.
leg1=$(rg -n -- $pat_house $root/lib $root/surface $root/bin $root/test $root/wasm)
named=$(python3 -P $root/dev/house-catchalls.py $root 2>&1)
named_code=$?
if [[ $named_code -ne 0 && -z $named ]]; then
  named="named catch-all scan failed with exit=$named_code"
fi
if [[ -n $named ]]; then
  leg1="${leg1}${leg1:+$'\n'}${named}"
fi
report_empty "no-exception" "$leg1"

# Leg 2:  no mutable state in the kernel or the encoder, except the one
# disclosed SD-D18 buffer site inside wasm/gc_encode.ml.
leg2=$(rg -n -- $pat_state $root/lib $root/wasm)
marker=$(rg -n -- 'SD-D18\.' $root/wasm/gc_encode.ml | head -1 | awk -F: '{print $1}')
if [[ -z $leg2 ]]; then
  leg2_bad=""
else
  leg2_bad=$(print -r -- "$leg2" | awk -F: -v f="$root/wasm/gc_encode.ml" -v m="$marker" \
    'NF && !(m != "" && $1 == f && $2 > m && $2 <= m + 12)')
fi
report_empty "no-mutable-state" "$leg2_bad"

# Leg 3:  exactly one catch site in the repository (SD-D14).
leg3=$(rg -n -- '\btry\b' $root/lib $root/surface $root/bin $root/test $root/wasm)
leg3_n=$(print -r -- "$leg3" | rg -c -- '.' || true)
if [[ $leg3_n == 1 ]]; then
  print -r -- "HOUSE one-catch-site OK"
  print -r -- "$leg3"
else
  print -r -- "HOUSE one-catch-site FAIL"
  print -r -- "$leg3"
  fail=1
fi

# Leg 4:  no bool match.
leg4=$(rg -n -- $pat_bool $root/wasm $root/test $root/bin)
report_empty "no-bool-match" "$leg4"

# Leg 5:  no em-dash outside the vendor tree and the build tree.
leg5=$(rg -n \
  --glob '!vendor' --glob '!**/vendor/**' \
  --glob '!_build' --glob '!**/_build/**' \
  -e $emdash $root)
report_empty "no-em-dash" "$leg5"

if [[ $fail == 0 ]]; then
  print -r -- "HOUSE OK"
  exit 0
fi
print -r -- "HOUSE FAIL"
exit 1
