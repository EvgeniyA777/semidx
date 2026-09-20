---
title: "Java static call rule: three narrow gaps"
doc_type: "follow_up"
lifecycle: "completed"
status: "fixed"
agent_action: "historical_reference_only"
updated: "2026-09-20"
---

# Java Static Call Rule: Three Narrow Gaps

## Classification

`bug`

## Source

Found in the post-closure review of
[Plan 012](../plans/012_java_semantic_quality_without_query_regression.md),
recorded in its
[progress log](../reports/012_java_semantic_quality_without_query_regression_progress.md#post-closure-review-2026-09-20).
All three are inside the rule [ADR 009](../adr/009_java_static_calls.md)
decided and Plan 012 Stages 4 and 5 implemented.

They are grouped because they share a deferral reason and were fixed in one
change to `src/frontends/java.zig` and `src/frontends/java_members.zig`. None of
them was observed in the external sample; the first was then reproduced against
a real compiler, and the other two are reasoned from the code.

## Current Behavior

### 1. An on-demand static import is not a guard, so a false fact is reachable

`resolveType` declines a name a static import claims, which is ADR 009's
condition 4 and one of the reasons a receiver may not be read as a class. The
guard reads `unit.static_imported`, which is filled from `importedName`, and
`importedName` returns null as soon as it sees an `asterisk` child. So
`import static a.b.C.x;` poisons the name `x` and `import static a.b.C.*;`
poisons nothing.

A static-import-on-demand declaration brings accessible static **fields** into
scope for the whole compilation unit, and JLS 6.4.2 makes a variable win over a
type of the same name. So where `a.b.C` declares a static field whose name is
also the name of a class in the analyzed unit's package, and that field's type
declares a method of the invoked name, `Name.method()` means the field's method
and semidx records a `CALLS` fact naming the class's method instead.

This is the one finding in this entry that produces a **fact** Java does not
agree with, rather than a decline or a misleading explanation, and it was
confirmed against `javac` 17 rather than argued from the specification:

```java
// demo/Util.java     class Util   { public static String make() ... }
// demo/Holder.java   class Holder { public static Other Util = new Other(); }
// demo/Caller.java   import static demo.Holder.*;   ->  Util.make()
FIELD Holder.Util.make (instance)
```

The program compiles and calls `Other.make`, while semidx recorded a fact naming
`Util.make`. So this is not a fact about code Java refuses to compile; it is a
fact naming the wrong method of the wrong class in a working program.

A second probe settled how wide the guard has to be. Adding an explicit
`import lib.Util;` to the caller does not rescue the type: the answer is still
`FIELD Holder.Util.make`. A variable obscures a type however the type reached
the unit, so the guard cannot be narrowed to names that came from the unit's own
package.

### 2. A missing `java.static` label is reported as "is not static"

`Access` carries an explicit `unknown`, documented as "a real answer, not a
default", and `unknown` declines. `is_static` is a plain `bool`: `methodsOf`
sets it to `false` when the definition carries no `java.static` label, and
`externalStaticTarget` tests `!only.is_static` before it tests access.

The decline is right. The explanation is not: the reader is told
"`X.y` is not static, so naming it through the class is not a call Java
compiles", which asserts something about the source that the graph does not
know. Reachable when a Java definition was recorded by a producer that did not
write the label — a version skew, not an ordinary index.

### 3. Two reason families are effectively unreachable and unfixtured

`externalStaticTarget` can answer "the receiver names class `X`, whose current
shape this analysis did not read" and "class `X` carries no record of whether it
declares supertypes". Both require `membersFor` and `resolveType` to disagree
about a name, and both look it up in the same order — single-type import, then
the unit's own package — so neither is reachable by ordinary input. No fixture
in the static-call matrix asserts either, and Stage 7's external decomposition
does not list them: they are zero because the eight listed families sum to
4,624, not because they were counted.

Dead code that claims to be a distinct answer is a small thing, but the matrix
is ADR 009's executable form, and a family with no case behind it is exactly
what Stage 2 said a switch without cases would be.

## Resolution

Fixed as a narrowly scoped implementation of [ADR 009](../adr/009_java_static_calls.md),
whose condition 2 already required it: a binding a future frontend covers "still
poisons the name here", and condition 4 already named static imports among the
guards `resolveType` keeps intact. The implementation kept only the single-form
half of that guard.

1. **On-demand static import declines the receiver.** A unit that writes
   `import static a.b.C.*;` resolves no simple-name receiver, with its own
   reason. The decline is the whole unit because the names such an import binds
   cannot be enumerated: this frontend records no fields as definitions, so
   `C`'s static field names are absent from the graph even when `C` is indexed,
   and `C` is usually a dependency that is not indexed at all. That is the same
   shape as ADR 009's condition 3, which refuses a whole class because inherited
   fields are invisible.

   The guard is on the receiver, not on `resolveType`: a type position is not a
   place a variable can claim a name, so field and return types in such a unit
   resolve exactly as before. A non-static on-demand import (`import a.b.*;`)
   imports types only and changes nothing.

2. **`Static` is a tri-state beside `Access` and `Supertypes`.** A definition
   with no `java.static` label reads back as `unknown` and declines saying the
   modifier is unrecorded, instead of being read as `false` and reported as an
   instance method.

3. **The two unreachable families stay, with the agreement they rest on now
   pinned.** They guard against the projection and `resolveType` disagreeing
   about what a name reaches; a test asserts that both prefer a single-type
   import over the unit's own package, which is what makes the families
   unreachable. The branches carry a comment saying so.

### What It Costs

Recall, in an amount this repository cannot measure. `import static
org.junit.Assert.*` and `import static org.mockito.Mockito.*` are ordinary in
test sources, and [ADR 008](../adr/008_java_visibility_boundaries.md) lets a test
root read its module's main root, so some share of Plan 012's 139 measured facts
came from units this guard now declines. Plan 012 did not split its 139 by source
root, and re-measuring needs the external harness
[Follow-up 017](017_plan_012_external_evidence_reproducibility.md) owns.

The capability matrix records the direction of the change against the measured
number rather than quietly leaving 139 standing. The trade is the one §3 of the
constitution states: exactness does not mean coverage, and a wrong fact is an
architectural defect rather than a trade-off.

## Tests

- *an on-demand static import leaves every simple-name receiver unresolved* —
  with the same call in a neighbouring unit still a fact, so the decline is the
  import's doing, and with the importing unit's field type still resolving, so
  the guard is on receivers and not on type positions.
- *an on-demand import that is not static leaves the receiver alone* —
  `import lib.*;` imports types, so nothing is obscured.
- *a target with no static label declines as unrecorded, not as an instance
  method* — no input makes the current frontend omit the label, so the case a
  producer change would create is written into the graph directly.
- *the member projection resolves a receiver name in the same order resolveType
  does* — a single-type import beats the unit's own package in both.
- The 49 existing static-call matrix cases pass unchanged.
