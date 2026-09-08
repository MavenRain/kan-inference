#!/bin/zsh
# dev/dune.sh ARGS...
# Runs dune from the zxcaml-p1 opam switch with the root at this repository.
# Use it for clean and exec.  Use dev/dunecho.sh for build.  Example:
#   zsh /Users/oobi/Documents/kanon/dev/dune.sh clean
#
# SA-D7: the root comes from this script's own path, never from a literal,
# so a copy of the repository under a scratch directory builds itself.

set -u

# The user shell startup files add a chpwd hook that reads an unset parameter.
# Under set -u that hook fails and cd inherits its non-zero status, so the hooks
# are cleared before the cd.
chpwd_functions=()
unfunction chpwd 2>/dev/null

export PATH=/Users/oobi/.opam/zxcaml-p1/bin:$PATH
cd ${0:A:h}/.. || exit 3
exec dune "$@"
