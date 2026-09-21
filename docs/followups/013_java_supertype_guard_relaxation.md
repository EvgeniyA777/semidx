---
title: "Java supertype guard relaxation"
doc_type: "follow_up"
lifecycle: "completed"
status: "fixed"
agent_action: "historical_reference_only"
updated: "2026-09-21"
---

# Java Supertype Guard Relaxation

## Resolution

**Fixed** by [Plan 014](../plans/014_java_receiver_coverage.md) Stages 1 to 4,
under [ADR 011](../adr/011_java_hierarchy_from_indexed_source.md).

The guard now lifts wherever the chain above the enclosing type is closed in
indexed source and nothing that chain reaches declares the name. It lifts on all
three of its sides, and each asks about what its own decline was about: a member
type for a reference, a field for a receiver, a method for an unqualified call.

What made that possible is what this entry said would have to come first. The
hierarchy is recorded: a top-level interface is a definition (D1), every
declared supertype is a `references` claim resolved in its declaring unit's
scope (D3), and a projection walks those claims with a visited path and a depth
cap of 16 (D4, D5). The chain rules out and never selects (D6), so no inherited
member is ever named as a target.

Measured on the same clone at the same commit, `apache/dubbo` at `df9c5e1`:

| | Before | After |
| --- | ---: | ---: |
| Unresolved references the guard declines | 8,083 | **6,064** |
| Unresolved call receivers it declines | 6,206 | **4,403** |
| Unqualified invocations it declines | 4,049 | **3,251** |
| `enclosing_supertypes` reason family | 6,206 | **0** |
| `unqualified_supertypes` reason family | 4,049 | **0** |

4,898 claims left the guard's families. **1,690 became facts** — 661 references,
198 receivers, 831 unqualified calls. 243 kept their unresolved answer because a
type the chain reaches claims the name, which is the rule doing its work. The
remaining 3,208 decline for the condition the guard used to come before, almost
always a name no indexed unit in scope declares.

This entry predicted 13 safely convertible references in a 1,200-definition
sample, scaling to about 554 whole-graph, and named interfaces as the dominant
blocker at 218 of 335. Both held: Plan 014 Stage 0 measured 3,628 of 4,738
closable claims as interface-dependent, and the realized 1,690 is three times
the pre-interface forecast.

The invalidation question this entry attached came with it and was measured
before the relaxation was accepted. No chain on the clone reaches depth 5 or
visits more than six types, and the largest number of reader units a single type
would owe a reanalysis is 37 out of 4,050. Reading a chain declares a dependency
on every unit in it, and a reader is hinted for every type its walk visited.

Two findings this entry did not anticipate are recorded in the
[Plan 014 progress log](../reports/014_java_receiver_coverage_progress.md):
a closed chain answers the guard and nothing else, so most claims that lose the
guard meet the next condition rather than becoming facts; and upkeep had to
learn to converge, because reanalysis can now change what a later reader sees.

## Classification

`coverage_gap`

## Source

Measured in
[Plan 012 Stage 0](../reports/012_java_semantic_quality_without_query_regression_progress.md#supertype-guard-opportunity),
which measured the guard's opportunity and, by
[Amendment 1](../plans/012_java_semantic_quality_without_query_regression.md#amendment-1-from-instance-receivers-to-static-calls),
left it out of that plan. It originates in
[ADR 004](../adr/004_allow_java_same_package_type_resolution.md)'s preconditions
as [Plan 010](../reports/010_java_resolution_boundaries_progress.md) applied
them.

## Current Behavior

`resolveType` in `src/frontends/java.zig` declines to resolve a simple type name
beyond its own unit when the enclosing class declares a superclass or any
interface, because an inherited member type could give the name another meaning.
The reference stays unresolved with the explanation "the enclosing class has
supertypes, and a member type it may inherit under this name is not resolved".

The same guard is what stops a class-name receiver from resolving inside such a
class, so it blocks calls as well as references.

## Why Deferred

The guard is correct, and lifting it without hierarchy evidence would trade an
honest unresolved answer for a name match, which
[ADR 003](../adr/003_reject_name_match_assertions.md) rejects.

Lifting it safely needs the enclosing class's hierarchy to be closed in indexed
source, and that is rare. Measured on apache/dubbo at `df9c5e1`, over a sample
of 1,200 definitions and 6,710 outgoing claims:

| Measurement | Count |
| --- | ---: |
| Unresolved references declined by the guard | 335 |
| Of those, would resolve to exactly one class if the guard were simply lifted | 38 |
| Of those, whose enclosing class hierarchy is **closed in indexed source** | 13 |
| Enclosing class implements interfaces, so the hierarchy is open | 218 |
| Superclass itself has supertypes | 56 |
| Superclass has no source in the working copy | 12 |

Static calls tell the same story from the call side: 247 class-name receivers in
that sample resolve to nothing only because the referring class has supertypes.

**Re-measured after Plan 012 Stage 5**, on the same clone at the same commit,
whole-graph this time rather than sampled, and with the implementation that
resolves static calls rather than a model of it. Every count below is identical
before and after the change
([method](../reports/012_java_semantic_quality_without_query_regression_progress.md#stage-6-follow-up-discipline)):

| Whole-graph measurement | Before Stage 5 | After Stage 5 |
| --- | ---: | ---: |
| Unresolved references declined by the guard | 8,083 | 8,083 |
| Unresolved calls whose receiver name the guard blocks | 6,206 | 6,206 |

Nothing this guard blocks moved, and nothing new entered its subset: the static
rule declines inside a class with supertypes before it asks anything else, so it
can neither convert these nor add to them. The sampled convertibility figures
above therefore still stand as the acceptance input, and a future plan does not
need to re-derive them.

Plan 012's own follow-up threshold was 50 references in the sample or 1% of
sampled outgoing claims, whichever is smaller. Both the convertible count (38)
and the safely convertible count (13) fall below it, so this is recorded as a
future input rather than promoted into a plan.

## Acceptance Direction

A future plan may relax the guard only where it can establish the hierarchy from
indexed source:

- every superclass in the chain resolves to a current Java class inside the
  [ADR 008](../adr/008_java_visibility_boundaries.md) visibility boundary;
- no interface and no unknown or non-class supertype leaves the hierarchy open;
- cycles are detected and leave the name unresolved;
- every reachable class in the chain is checked for a member type of the
  referenced name, and for a method of the invoked name when the guard is lifted
  for calls;
- any unsupported member type, missing provider, stale provider, or out-of-scope
  provider keeps the current unresolved answer.

The invalidation question comes with it: a relaxed name depends on every class
in the chain, so a supertype edit anywhere in it must reanalyze the reader.
Measure that cost before accepting the relaxation, because the dependency fan-out
is larger than the same-package case Plan 010 measured.

Interfaces are the dominant blocker at 218 of 335, so a plan that cannot resolve
interface hierarchies will convert very little. Decide that first.

## Required Tests

- A class whose whole hierarchy is indexed, with no member type of the name in
  any reachable class, resolves the name.
- A class implementing an interface with no source in the working copy keeps the
  current unresolved answer.
- A member type of the name declared anywhere in the reachable chain keeps the
  name unresolved.
- A cycle in the declared hierarchy keeps the name unresolved and does not hang.
- Adding a supertype to any class in the chain reanalyzes the reader and removes
  a stale fact.
- The Plan 010 and ADR 008 boundary tests continue to pass unchanged.
