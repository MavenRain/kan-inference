/-
Copyright (c) 2026 Onyeka Obi.  All rights reserved.
Released under MIT OR Apache 2.0 license.

The disclosure driver of gate SF-G4 and the initiality developments.
It prints the four syntax theorem reports followed by the public
initiality and initial-chain results. The report is
disclosure and not a zero-axioms gate: `propext`, `Classical.choice` and
`Quot.sound` are the three admissible names.

Run it with
`lake +leanprover/lean4:v4.33.0-rc1 --dir META env lean META/Axioms.lean`.
-/

import KanonMeta

open KanonMeta

#print axioms bc_lan_spi
#print axioms bc_ran_spi
#print axioms bc_lan_scoll
#print axioms bc_ran_scoll

#print axioms Initiality.projection_fold
#print axioms Initiality.elim
#print axioms Initiality.fold_eq_section
#print axioms Initiality.elim_beta

#print axioms InitialChain.polyMap_id
#print axioms InitialChain.polyMap_comp
#print axioms InitialChain.roll_on_leg
#print axioms InitialChain.fold_comm
#print axioms InitialChain.hom_on_leg
#print axioms InitialChain.chainInitial
#print axioms InitialChain.chainElim
#print axioms InitialChain.chainElim_beta

#print axioms ChainColimit.cocone
#print axioms ChainColimit.isColimit
#print axioms ChainColimit.initialOfPreserves

#print axioms NatConstruction.natPreserves
#print axioms NatConstruction.recursiveInitial

#print axioms LinearConstruction.preserves
#print axioms LinearConstruction.recursiveInitial
#print axioms VectorConstruction.recursiveInitial
#print axioms VectorConstruction.copy_eq
