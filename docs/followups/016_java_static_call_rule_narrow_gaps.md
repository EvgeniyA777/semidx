---
title: "Java static call rule: three narrow gaps"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
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

They are grouped because they share a deferral reason and would be fixed in one
change to `src/frontends/java.zig` and `src/frontends/java_members.zig`. None of
them was observed in the external sample; each is reasoned from the code and the
language rules.

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
agree with, rather than a decline or a misleading explanation. The construction
is contrived — a field named like a class — but ADR 009 states the standard it
fails: a binding a future frontend covers "still poisons the name here".

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

## Why Deferred

None of the three changes what the rule answers on real source: the external
sample shows zero calls in families 2 and 3, and family 1 needs a field named
like a class. Plan 012 is closed and its evidence stands. They are recorded
rather than fixed on the spot because the first needs a decision, not just a
patch: an on-demand static import names a scope, not a member, so semidx cannot
know which names it binds without reading `a.b.C`, and the honest options are to
decline every simple-name receiver in a unit that has one, or to read the
imported class's static field names from the graph the way class shape is
already read.

The second and third are small and safe, but they belong with the first so the
matrix is extended once.

## Acceptance Direction

A plan or a direct implementation task may take this up when it decides:

- how an on-demand static import is handled. Declining every simple-name
  receiver in such a unit is exact and cheap and costs recall in a common
  construct; reading the imported class's static field names as graph facts is
  exact and needs a fourth thing on the class-shape channel. Measure the recall
  cost on the Plan 012 sample before choosing.
- whether `Supertypes` and `Access` gain a peer for `static` — a tri-state whose
  `unknown` declines with its own reason — or whether the reason text is simply
  ordered so an unlabelled method is reported as unrecorded rather than as
  non-static.
- whether the two unreachable families become fixtured cases or are removed. If
  they are kept, the matrix must contain input that reaches them; if they are
  removed, the decline they cover must still exist somewhere.

## Required Tests

- A unit with `import static a.b.C.*;` where `C` declares a static field named
  like a class in the unit's package leaves `Name.method()` unresolved, saying
  which condition failed.
- The single-static-import case keeps answering as it does today.
- A method definition carrying no `java.static` label leaves a class-qualified
  call unresolved with a reason that says the modifier is unrecorded, not that
  the method is an instance method.
- Every reason family the rule can answer has at least one case in the
  static-call matrix, or the family is gone.
- The 49 existing static-call matrix cases pass unchanged.
