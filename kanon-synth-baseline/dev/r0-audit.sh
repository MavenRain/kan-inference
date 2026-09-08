#!/bin/zsh
# dev/r0-audit.sh [ROOT]
# The R0-AUDIT leg of the gate battery (Stage E, brief 3.5.1).  Example:
#   zsh /Users/oobi/Documents/kanon/dev/r0-audit.sh
#
# R0 is the shape row that M0 carries.  The five shape names of
# lib/shape.ml stay inside the four files that own them:  shape.ml
# declares them, rules.ml holds the rule pack, pp.ml prints them and
# erase.ml reads them.  Under wasm/ only emit.ml names a shape.  A hit
# anywhere else is a shape that leaked into the checker, the evaluator,
# conversion or the encoder, which R0 forbids at M0.
#
# SD-D29:  ripgrep reads a glob that stands after the pattern as a path,
# so every --glob stands before the pattern and the pattern rides behind
# -e.
#
# SA-D7: the root comes from this script's own path when no argument is
# given, so a copy of the repository under a scratch directory audits
# itself.  rg does the reading;  grep, sed and find are never called.

set -u

# The user shell startup files add a chpwd hook that reads an unset
# parameter.  Under set -u that hook fails, so the hooks are cleared.
chpwd_functions=()
unfunction chpwd 2>/dev/null

root=${1:-${0:A:h}/..}
pattern='SColl|SMu|SNu|SPar|SPi'

if [[ ! -d $root/lib || ! -d $root/wasm ]]; then
  print -r -- "r0-audit: cannot read $root/lib and $root/wasm"
  print -r -- "R0-AUDIT FAIL"
  exit 1
fi

lib_hits=$(rg -n \
  --glob '!shape.ml' --glob '!rules.ml' --glob '!pp.ml' --glob '!erase.ml' \
  -e $pattern $root/lib)

wasm_hits=$(rg -n --glob '!emit.ml' -e $pattern $root/wasm)

if [[ -z $lib_hits && -z $wasm_hits ]]; then
  print -r -- "R0-AUDIT OK"
  exit 0
fi

if [[ -n $lib_hits ]]; then
  print -r -- "$lib_hits"
fi

if [[ -n $wasm_hits ]]; then
  print -r -- "$wasm_hits"
fi

print -r -- "R0-AUDIT FAIL"
exit 1
