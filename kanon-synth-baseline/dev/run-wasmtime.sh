#!/bin/zsh
# dev/run-wasmtime.sh FILE.wasm NAME
#
# The Stage E wasmtime runner.  It calls one exported function of one
# module through wasmtime and prints the i32 answer in decimal, with the
# contract of dev/run-node.mjs.
# Exit codes.  0 is an answer on stdout, 1 is a trap, 2 is a module the
# engine refuses and 64 is a usage error.  The trap line and the invalid
# line go to stderr, so stdout holds the answer alone and the driver
# reads a diagnosis as the first stderr line.  The experimental warning
# that wasmtime writes about --invoke never reaches the caller.

set -u

# The startup files add a chpwd hook that reads an unset parameter.
chpwd_functions=()
unfunction chpwd 2>/dev/null

warn='using `--invoke` with a function that returns values is experimental'

if [[ $# -ne 2 ]]; then
  print -u2 -r -- "usage: zsh dev/run-wasmtime.sh FILE.wasm NAME"
  exit 64
fi

file=$1
name=$2
work=${TMPDIR:-/tmp}
out=$(mktemp "$work/kanon-wasmtime-out.XXXXXX")
err=$(mktemp "$work/kanon-wasmtime-err.XXXXXX")

clean () {
  rm -f -- "$out" "$err"
}
trap clean EXIT INT TERM

# "status" is read only in zsh, so the exit code carries another name.
wasmtime run -C cache=n --invoke "$name" "$file" > "$out" 2> "$err"
code=$?

# The trap text follows "wasm trap: ";  the invalid text is the first
# stderr line that is not the warning.
hit=$(rg -N -m 1 -- 'wasm trap: ' "$err")
first=$(rg -N -F -v -- "$warn" "$err" | rg -N -m 1 -- '\S')

if [[ $code -eq 0 ]]; then
  cat "$out"
  exit 0
elif [[ $code -eq 134 || -n $hit ]]; then
  if [[ -n $hit ]]; then
    print -u2 -r -- "trap: ${hit#*wasm trap: }"
  else
    print -u2 -r -- "trap: $first"
  fi
  exit 1
else
  print -u2 -r -- "invalid: $first"
  exit 2
fi
