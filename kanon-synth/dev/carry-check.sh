#!/bin/zsh
# dev/carry-check.sh
# Re-diffs every carried file against the vendored tot pin and compares the
# line count with the table in dev/CARRIED.md.  Prints one row per carried
# file, then CARRY-OK or CARRY-FAIL.  Exits 1 on any FAIL.
#
# SA-D7: the root comes from this script's own path, so a copy of the
# repository under a scratch directory checks itself.

set -u

chpwd_functions=()
unfunction chpwd 2>/dev/null

ROOT=${0:A:h}/..
CARRIED=$ROOT/dev/CARRIED.md
VENDOR=$ROOT/vendor/tot
# The work directory sits under the repository root, not under the system
# temp directory, so the script needs no writable path outside the tree it
# checks.  .gitignore holds it.
WORK=$ROOT/.gatework/carry
rm -rf $WORK
mkdir -p $WORK
fail=0
seen=""

rg -N '^\| lib/' -- $CARRIED > $WORK/rows

while IFS= read -r row; do
  file=$(print -r -- "$row" | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}')
  origin=$(print -r -- "$row" | awk -F'|' '{gsub(/^ +| +$/, "", $3); print $3}')
  want=$(print -r -- "$row" | awk -F'|' '{gsub(/^ +| +$/, "", $4); print $4}')

  if [[ ! -f $ROOT/$file ]]; then
    print -r -- "CARRY $file MISSING FAIL"
    fail=1
    continue
  fi

  if ! git -C $VENDOR show $origin > $WORK/orig 2>/dev/null; then
    print -r -- "CARRY $file ORIGIN-MISSING FAIL"
    fail=1
    continue
  fi

  got=$(diff $WORK/orig $ROOT/$file | /usr/bin/wc -l | tr -d ' ')
  head1=$(head -1 $ROOT/$file)
  hdr=BAD
  if [[ $head1 == '(* carried from tot '*' delta: '*'*)' ]]; then
    hdr=OK
  fi

  if [[ $got == $want && $hdr == OK ]]; then
    print -r -- "CARRY $file diff=$got expected=$want OK"
  else
    print -r -- "CARRY $file diff=$got expected=$want header=$hdr FAIL"
    fail=1
  fi
  seen="$seen $file"
done < $WORK/rows

# A carried file with no row in the table is a FAIL too, so a carry cannot
# hide by leaving the table alone.
for f in $ROOT/lib/*.ml $ROOT/lib/*.mli; do
  rel=lib/${f:t}
  if head -1 $f | rg -q '^\(\* carried from tot '; then
    if [[ " $seen " != *" $rel "* ]]; then
      print -r -- "CARRY $rel NO-ROW FAIL"
      fail=1
    fi
  fi
done

rm -rf $WORK

if [[ $fail -eq 0 ]]; then
  print -r -- "CARRY-OK"
  exit 0
fi
print -r -- "CARRY-FAIL"
exit 1
