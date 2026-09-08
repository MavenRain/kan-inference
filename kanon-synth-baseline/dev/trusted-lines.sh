#!/bin/zsh
# dev/trusted-lines.sh [ROOT]
# The TRUSTED-LINES leg of the gate battery (Stage E, brief 3.5.1).
# Example:
#   zsh /Users/oobi/Documents/kanon/dev/trusted-lines.sh
#
# The trust base of a checked file is the kernel and the encoder.  The
# kernel is eight files:  shape.ml, term.ml, rules.ml, check.ml,
# value.ml, eval.ml, conv.ml and totality.ml.  The encoder is one file,
# wasm/gc_encode.ml, which writes the bytes of the module.  M0 holds the
# kernel at 4,000 lines and the encoder at 600, so the base stays small
# enough for one reader to audit. (ruling round 2026-09-06 (c))
#
# The line prints the two counts against their bounds:
#   TRUSTED-LINES kernel=2305/4000 encoder=216/600 OK (ruling round 2026-09-06 (c))
#
# SA-D7: the root comes from this script's own path when no argument is
# given, so a copy of the repository under a scratch directory measures
# itself.  wc and awk do the reading;  grep, sed and find are never
# called.

set -u

# The user shell startup files add a chpwd hook that reads an unset
# parameter.  Under set -u that hook fails, so the hooks are cleared.
chpwd_functions=()
unfunction chpwd 2>/dev/null

root=${1:-${0:A:h}/..}

kernel_bound=4000
encoder_bound=600

kernel_files=(
  $root/lib/shape.ml
  $root/lib/term.ml
  $root/lib/rules.ml
  $root/lib/check.ml
  $root/lib/value.ml
  $root/lib/eval.ml
  $root/lib/conv.ml
  $root/lib/totality.ml
  # M1 Stage G, brief 3.10 and SG-D12:  the two files the mu shape adds
  # join the believed list and the two budgets above do not move.
  $root/lib/positivity.ml
  $root/lib/global.ml
  # M1 Stage I, brief 3.10 and SI-D15:  the file that holds the
  # structural order and the certificate joins the believed list and the
  # two budgets above do not move.
  $root/lib/order.ml
  # Stage K SK-D1: the arbitrary precision host boundary is believed.
  $root/lib/bignum.ml
)
encoder_file=$root/wasm/gc_encode.ml

# wc -l over more than one file ends with a total row, which awk reads.
kernel_out=$(wc -l $kernel_files)
kernel_code=$?

encoder_out=$(wc -l < $encoder_file)
encoder_code=$?

if [[ $kernel_code -ne 0 || $encoder_code -ne 0 ]]; then
  print -r -- "trusted-lines: a trusted file is missing under $root"
  print -r -- "TRUSTED-LINES FAIL"
  exit 1
fi

kernel=$(print -r -- "$kernel_out" | awk 'END { print $1 }')
encoder=$(print -r -- "$encoder_out" | awk '{ print $1 }')

line="TRUSTED-LINES kernel=$kernel/$kernel_bound encoder=$encoder/$encoder_bound"

if [[ $kernel -le $kernel_bound && $encoder -le $encoder_bound ]]; then
  print -r -- "$line OK"
  exit 0
fi

print -r -- "$line FAIL"
exit 1
