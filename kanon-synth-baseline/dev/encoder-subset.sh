#!/bin/zsh
# dev/encoder-subset.sh [ROOT]
# The ENCODER-SUBSET gate leg of M0 Stage D (SD-D11).  Example:
#   zsh /Users/oobi/Documents/kanon/dev/encoder-subset.sh /Users/oobi/Documents/kanon
#
# The allowlist is read from SPEC.md section 8:  every backticked token of
# the seven instruction rows, and nothing else.  The reading is every word
# after an opening parenthesis of every test/golden/*.wat, less the words
# that build a module rather than run in it.  A word outside the
# allowlist fails the gate, so a new opcode is visible in a diff of the
# table before it is visible anywhere else.
#
# SA-D7: the root comes from this script's own path when no argument is
# given, so a copy of the repository under a scratch directory checks
# itself.  rg and sort do the reading;  grep, sed and find are never
# called.

set -u

chpwd_functions=()
unfunction chpwd 2>/dev/null

root=${1:-${0:A:h}/..}
spec=$root/SPEC.md
golden=$root/test/golden

if [[ ! -f $spec ]]; then
  print -- "encoder-subset: cannot read $spec"
  print -- "ENCODER-SUBSET FAIL"
  exit 1
fi

# The words that build a module or name a type, which no instruction row
# lists and no encoder emits as an opcode.
#
# SD-D24: "drop" is in this list and is not an opcode of gc_encode.ml.
# The text form is the print of a binary module, and the printer writes
# "drop" around a value that stays on the stack in front of an
# "unreachable".  The case dispatch of SD-D5 leaves the scrutinee there
# when no leg casts, so the word is the printer's, not the encoder's.
# Stage K: Binaryen prints inferred reference types as (ref (exact $N)).
# "exact" is a printer type qualifier; gc_encode.ml adds no encoding for it.
structural=(
  module type rec struct field func param result local export elem declare
  ref mut sub final then else i32 i64 eq i31 any none nofunc null extern array
  drop exact
)

work=${TMPDIR:-/tmp}/kanon-encoder-subset.$$
mkdir -p $work

# The allowlist includes the Stage K array row and its stores.
rg -N '^\| (control|calls|locals|numeric|references|structs|arrays) \|' -- $spec \
  | rg -o '`[^`]+`' \
  | tr -d '`' \
  | sort -u > $work/allow.txt

print -l -- $structural | sort -u > $work/structural.txt
sort -u $work/allow.txt $work/structural.txt > $work/known.txt

# The reading: the first word after every opening parenthesis.
cat $golden/*.wat \
  | rg -o '\([a-zA-Z0-9_.]+' \
  | tr -d '(' \
  | sort -u > $work/words.txt

comm -23 $work/words.txt $work/known.txt > $work/bad.txt

count=$(wc -l < $work/bad.txt | tr -d ' ')
allowed=$(wc -l < $work/allow.txt | tr -d ' ')

if [[ $allowed -lt 1 ]]; then
  print -- "encoder-subset: SPEC.md section 8 lists no instruction"
  print -- "ENCODER-SUBSET FAIL"
  rm -rf $work
  exit 1
fi

if [[ $count -gt 0 ]]; then
  cat $work/bad.txt
  print -- "ENCODER-SUBSET FAIL"
  rm -rf $work
  exit 1
fi

print -- "ENCODER-SUBSET OK"
rm -rf $work
exit 0
