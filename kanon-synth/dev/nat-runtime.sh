#!/bin/zsh
# Stage K focused runtime assertions and export-boundary observations.
# Usage: zsh dev/nat-runtime.sh [ROOT] [EVIDENCE_DIRECTORY]
set -u
chpwd_functions=()
unfunction chpwd 2>/dev/null
root=${1:-${0:A:h}/..}
root=${root:A}
evidence=${2:-$root/.gatework/nat-runtime}
driver=$root/_build/default/bin/kanon.exe
mkdir -p "$evidence" || exit 1

cases=(nat-big:7 nat-runtime-edges:32 nat-runtime-capture:19 nat-runtime-mu:23 nat-runtime-export:trap)
hosts=(kernel node wasmtime both)
passed=0
total=0
failed=0
for item in $cases; do
  fixture=${item%%:*}
  expected=${item#*:}
  wasm=$evidence/$fixture.wasm
  "$driver" emit "$root/test/fixtures/$fixture.kan" -o "$wasm" --export main \
    > "$evidence/$fixture.emit.out" 2> "$evidence/$fixture.emit.err"
  code=$?
  if [[ $code -ne 0 ]]; then
    print -r -- "NAT-RUNTIME FAIL emit $fixture exit=$code"
    failed=1
    continue
  fi
  /opt/homebrew/bin/wasm-opt "$wasm" -S -o "$evidence/$fixture.wat" \
    --enable-gc --enable-reference-types --enable-tail-call --enable-exception-handling \
    > "$evidence/$fixture.validate.out" 2> "$evidence/$fixture.validate.err"
  code=$?
  if [[ $code -ne 0 ]]; then
    print -r -- "NAT-RUNTIME FAIL validate $fixture exit=$code"
    failed=1
    continue
  fi
  for host in $hosts; do
    (( total += 1 ))
    "$driver" run "$root/test/fixtures/$fixture.kan" --export main --host "$host" \
      > "$evidence/$fixture.$host.out" 2> "$evidence/$fixture.$host.err"
    code=$?
    answer=$(<"$evidence/$fixture.$host.out")
    diagnostic=$(<"$evidence/$fixture.$host.err")
    if [[ $expected == trap && $code -eq 4 && -z $answer && $diagnostic == *trap* ]] \
       || [[ $expected != trap && $code -eq 0 && $answer == $expected ]]; then
      (( passed += 1 ))
      print -r -- "NAT-RUNTIME OK $fixture $host exit=$code expected=$expected"
    else
      print -r -- "NAT-RUNTIME FAIL $fixture $host exit=$code expected=$expected actual=[$answer]"
      failed=1
    fi
  done
done
if [[ $failed -eq 0 && $passed -eq 20 && $total -eq 20 ]]; then
  print -r -- "NAT-RUNTIME OK $passed/$total"
  exit 0
fi
print -r -- "NAT-RUNTIME FAIL $passed/$total"
exit 1
