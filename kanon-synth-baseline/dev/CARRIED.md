# Carried files

Each file below comes from tot at the sha in PIN.  The first line of each
file names its origin and its delta.  The count is the number of lines
that `diff` prints between `git -C vendor/tot show ORIGIN` and the file.
dev/carry-check.sh recomputes every count and fails when one differs.

| file | origin | diff lines |
| --- | --- | --- |
| lib/level.ml | 8cf0b8b:lib/level.ml | 2 |
| lib/level.mli | 8cf0b8b:lib/level.mli | 2 |
| lib/quantity.ml | 8cf0b8b:lib/quantity.ml | 151 |
| lib/literal.ml | 8cf0b8b:lib/literal.ml | 15 |
| lib/global.ml | 8cf0b8b:lib/global.ml | 196 |
| lib/budget.ml | 8cf0b8b:lib/budget.ml | 2 |
| lib/budget.mli | 8cf0b8b:lib/budget.mli | 2 |

A count of 2 is the carry header line and nothing else.

lib/literal.ml is at 15 because Stage K widens the existing LInt payload
to Bignum.t, updates its dependency comment and uses arbitrary precision
equality (SK-D2). Both literal constructors remain unchanged.

lib/quantity.ml is at 151. Stage B adds One and its arithmetic arms;
Stage K adds pure usage intervals, sequential addition, multiplicity
scaling, alternative joins and captured dependencies from nonreturning
paths (SK-D7/D8). The checker discharges explicit One binders exactly
once, with affine ownership for implicit aliases of linear resources.
The review round of 2026-09-06 adds a doc comment above each of the
sixteen new functions and takes the upper bound of a nonreturning path
from its reads, which moves the count from 97 to 151.

lib/global.ml is at 196.  It drops the Ind and Ctor entries with their
views, because the recursive shapes arrive at M1, and Stage B re-adapts
the Prim entry with prim_of, find_prim and initial.  initial holds Nat at
Type 0 and the five primitives of lib/prim.ml at the types of SB-D8.
Stage G adds the family record and the families table for the mu shape
at lib/global.ml:61-79, so the count moves from 164 to 196.  The move
is ruling round 2026-09-06 (c) of RATIFICATIONS.md, decision SG-D28.
