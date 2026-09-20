---
title: "A unit path change does not reanalyze the unit"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
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

## Why Deferred

It is a write-path change, outside the scope Plan 012 was executing, and it
predates that plan. It also needs a decision rather than a patch: whether a path
change is modelled as an edit of the unit, or as its own `Upkeep` step that
captures exports and aspects around `setSourceUnitPath`. The first is simpler
and costs a reanalysis per moved file; the second keeps a pure directory rename
cheap but adds a third channel to reason about.

The cost matters at scale: a directory rename in a large repository moves
thousands of units at once, and reanalyzing all of them is the opposite of what
the move path was built to avoid.

Whether languages other than Java have path-dependent analysis today should be
checked rather than assumed — the Zig frontend resolves local imports by
relative path — and the fix should be stated for the general case, not for Java
alone.

## Acceptance Direction

A plan may take this up when it decides:

- what makes a path change semantically relevant. Reanalyzing on every rename is
  correct and expensive; reanalyzing only when the derived Java source root
  changes is cheap and language-specific. A general rule — the frontend declares
  whether its analysis reads the path — keeps the core out of language business.
- that the moved unit itself is reanalyzed, not only its dependents. Seeds are
  excluded from `propagate`, so this needs an explicit step.
- that a move runs through `Upkeep`, so the package-export and class-shape
  channels see it and hinted readers whose claim is unresolved are reached.
- what a mass rename costs, measured, before the rule is accepted.

## Required Tests

- A caller moved out of its provider's Java source root loses the `CALLS` fact
  and keeps the unresolved reason ADR 008 gives for an out-of-scope class.
- The same for a `REFERENCES` fact to a same-package class.
- A provider moved into the reader's source root turns the reader's unresolved
  call into a fact without the reader being edited.
- A move that does not change the derived source root reanalyzes nothing, and
  the identity guarantees of the current rename tests still hold.
- A rename of a directory holding many units is measured, and the cost is
  recorded rather than assumed.
