---
title: "A unit path change does not reanalyze the unit"
doc_type: "follow_up"
lifecycle: "completed"
status: "fixed"
agent_action: "historical_reference_only"
updated: "2026-09-20"
---

# A Unit Path Change Does Not Reanalyze The Unit

## Classification

`bug`

## Source

Found in the post-closure review of
[Plan 012](../plans/012_java_semantic_quality_without_query_regression.md),
recorded in its
[progress log](../reports/012_java_semantic_quality_without_query_regression_progress.md#post-closure-review-2026-09-20).

The defect originates in [ADR 008](../adr/008_java_visibility_boundaries.md),
which made a unit's **path** a semantic input by deriving the Java source root
from it. [ADR 009](../adr/009_java_static_calls.md) widened what the path
decides from type references to `CALLS` facts.

## Current Behavior

A move is treated as "contents did not change, so nothing is re-read". The
`.renamed` branch of `Index.applyScan` only calls `setSourceUnitPath`
(`src/root.zig`), and `Dependencies.propagate` uses its seeds as the exclusion
set, so the moved unit is never in `affected` (`src/core/dependencies.zig`).
`Upkeep.captureBefore` and `Upkeep.recordAnalysis` are called for removals and
for analyses, never for renames, so neither the package-export channel nor the
class-shape aspect channel sees a move.

That was correct while analysis depended only on a unit's bytes. It is not
correct now: `sourceRoot` and `sharesScope` in `src/frontends/java.zig` read the
path, and both a `REFERENCES` fact (ADR 004/008) and a `CALLS` fact (ADR 009)
exist or not because of it.

Reproduced against the implementation at `6a47ba5`, with a temporary test over
the `Tree` fixture helper:

```
module/src/main/java/lib/Util.java    package lib; public static String make()
module/src/main/java/lib/Caller.java  package lib; void covered() { Util.make(); }
                                      => CALLS fact naming Util.make

mv Caller.java -> other/src/main/java/lib/Caller.java
rescan: renamed=1 analyzed=0
after the move: the same relationship is still resolution = fact
```

`other/src/main/java/lib` is a different Java source root, so `sharesScope`
returns false and the call must be unresolved. The static-call matrix asserts
exactly that for `Outsider` written at that very path
(`tests/vertical_slice_test.zig`, the "source root this unit can see" case), so
the graph now answers the same question two different ways depending on whether
the file arrived there by a move.

Two directions, with different symptoms:

- **The reader moves.** Stale **fact**: a `CALLS` or `REFERENCES` fact survives
  across a visibility boundary the unit can no longer cross. This is the
  serious one — it presents as an established relationship.
- **The provider moves into scope.** Stale **unresolved**: a rename touches
  neither `changed_packages` nor `changed_shapes`, and a reader whose claim is
  unresolved has no dependency to be found by, so nothing wakes it. A false
  negative only.

The moved unit's own claims are also computed against its old path until
something else edits it.

The current behavior is pinned by an existing test that asserts the absence of
reanalysis on a move ("Nothing inside the file moved, so nothing was re-read",
`tests/vertical_slice_test.zig`). That assertion has to change with the fix.

## Why It Was Deferred

It is a write-path change, outside the scope Plan 012 was executing, and it
predates that plan. It also needed a decision rather than a patch, which the
resolution below records.

## Resolution

A move is now a semantic change when, and only when, the unit lands in another
**directory**.

The directory is the right test rather than the path, and it is not a Java
rule: a Java source root is the unit's directory with its package directories
stripped, and a Zig local import resolves against the same directory, so two
paths that share a directory are read identically by every frontend here. A
file renamed in place therefore still re-reads nothing, which is what the move
path was built for.

Three parts:

- **The moved unit is reanalyzed.** `propagate` uses its seeds as the exclusion
  set, so a unit that moves is never in `affected` and had to be scheduled
  explicitly. It is analyzed after every other unit in the batch, because it
  resolves names against whatever the batch established.
- **Everything it exposes is marked changed.** No before/after comparison can
  see a move: a class keeps its package, its name, its methods and their
  modifiers wherever the file sits. So the package-export and class-shape
  channels are marked outright rather than compared, which reaches the readers
  whose claim is unresolved and who therefore have no dependency to be found by.
- **All the moves in one batch share one step.** Every path is set before any
  moved unit is analyzed, so each of them already read the final places of all
  of them. Numbering them in sequence made each one owe the ones analyzed before
  it a second pass for a change none of them could see — measured at 6 reanalyses
  where 4 are owed, and fixed.

### What It Costs

A move costs the units that moved plus the readers their visibility change can
reach. Measured on a five-unit tree where three units move out of one package:
4 reanalyses — the three that moved and the one reader of them — and one
`invalidated`. A unit in another package that declares nothing in theirs and
imports nothing from them is not touched.

At repository scale a directory rename is therefore proportional to the
directory and its readers, not to the repository, but it is no longer free. That
is the honest price of the path being an input to analysis.

## Tests

- *a caller moved out of its provider's source root loses the fact it recorded*
  — the call is a fact before the move and carries ADR 008's out-of-scope reason
  after it.
- *a provider moved into the reader's source root turns its unresolved call into
  a fact* — the reader is not edited and declared no dependency, so only the
  move's own channel can reach it.
- *moving a directory costs the units in it and the readers they reach* — the
  measurement above.
- *renaming a file inside its own directory re-reads nothing* — the case the
  move path exists for.
- *moving a file preserves the unit and everything inside it* — updated: it now
  asserts that exactly the moved unit is re-read, and still asserts every
  identity guarantee it did before.
