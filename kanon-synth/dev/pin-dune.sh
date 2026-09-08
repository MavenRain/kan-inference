#!/bin/zsh
# dev/pin-dune.sh ARGS...
# Runs dune from the zxcaml-p1 opam switch inside the tot pin worktree.
# Every dune call at Stage 0 goes through this runner, for example:
#   zsh /Users/oobi/Documents/kanon/dev/pin-dune.sh build
# The pin sources are never edited.

set -u

# The user shell startup files add a chpwd hook that reads an unset parameter.
# Under set -u that hook fails and cd inherits its non-zero status, so the hooks
# are cleared before the cd.  Timing stays honest: no hook runs in a timed call.
chpwd_functions=()
unfunction chpwd 2>/dev/null

export PATH=/Users/oobi/.opam/zxcaml-p1/bin:$PATH
cd /Users/oobi/Documents/kan-lang-tot-pin || exit 3
exec dune "$@"
