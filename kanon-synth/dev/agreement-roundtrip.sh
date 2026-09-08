#!/bin/zsh
set -eu
prep=${0:A:h}
work=${1:-"$prep/.."}
exec /Users/oobi/.opam/zxcaml-p1/bin/ocaml \
  -I /Users/oobi/.opam/zxcaml-p1/lib/zarith zarith.cma \
  -I "$work/_build/default/lib" \
  -I "$work/_build/default/lib/.kanon_kernel.objs/byte" kanon_kernel.cma \
  -I "$work/_build/default/surface" \
  -I "$work/_build/default/surface/.kanon_surface.objs/byte" kanon_surface.cma \
  "$prep/agreement-roundtrip.ml"
