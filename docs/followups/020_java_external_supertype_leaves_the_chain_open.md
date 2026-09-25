---
title: "A supertype with no indexed source leaves the chain open"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-25"
---

# A Supertype With No Indexed Source Leaves The Chain Open

## Classification

`coverage_gap`

## Source

Observed while a `v0.1.0-preview.4` preview user reviewed a small external Java
repository: nine files, twenty-nine definitions, no analysis failures and no
stale units. There is no committed report behind this entry, and the
observation is one repository, which is why the acceptance direction below
starts with a measurement rather than with a rule.

## Current Behavior

`resolveType` reads a simple type name in body position only when the chain
above the enclosing type is closed in indexed source and nothing that chain
reaches declares the name. `walkChain` in `src/frontends/java.zig` returns the
condition that left the chain open, and `chain.openWords` names it in the
decline: `chain.unresolved_here` for a supertype this unit writes and cannot
resolve, `chain.unresolved_above` for one further up.

A class that implements a JDK interface has an open chain, because the JDK
interface has no source in the working copy. Every simple type name in that
class body then stays unresolved, including a field whose type is a class this
repository declares. In the observed repository:

```java
class Producer implements Runnable {
    private final Storage storage;
    public void run() { storage.produce(); }
}
```

`Storage` and its single `produce()` are both indexed, and calls to
`Storage.produce()` from test units resolve to facts. The call above does not:
`Runnable` is unresolved, so an inherited member type named `Storage` is not
ruled out, so the receiver's declared type is not read as a type, so
[ADR 012](../adr/012_java_value_receiver_calls.md)'s value-receiver rule never
gets a target. The answer is exact and carries its reason. It is also the
repository's most obvious edge, and it is missing.

This is the behavior [Follow-up 013](013_java_supertype_guard_relaxation.md)
left in place on purpose. Its Required Tests pin it: "A class implementing an
interface with no source in the working copy keeps the current unresolved
answer." This entry does not reopen 013; it records what remains after it.

## Why Deferred

**It cannot be decided inside a follow-up.** Closing the chain over an external
type means reading a type's shape from something other than analyzed repository
source — a JDK image, class files, or a build classpath. That is a new input
kind and a new source of evidence, so it touches the constitution's definition
of a **fact** and the visibility scope
[ADR 008](../adr/008_java_visibility_boundaries.md) derived from source roots.
It needs an ADR answering the section 11 questions, not a plan built on this
entry.

**Weakening the guard instead is not available.** Treating an unknown supertype
as contributing nothing, or exempting a list of known JDK interfaces, converts
an honest unresolved answer into a name match, which
[ADR 003](../adr/003_reject_name_match_assertions.md) rejects. The list variant
also fails quietly on the first external supertype nobody listed.

**It is unmeasured.** [Plan 012](../plans/012_java_semantic_quality_without_query_regression.md)'s
promotion threshold is 50 references in the sample or 1% of sampled outgoing
claims, whichever is smaller, and one nine-file repository is not evidence
against it either way. Follow-up 013 was promoted on a measurement and is the
precedent.

**It is behind the current priority order.** `MEMORY.md` puts preview adoption
and MCP client-output evidence first, and names remaining Java gaps as one of
several candidates to be chosen by measured pain.

## Acceptance Direction

Measure before deciding anything:

- On a named clone at a named commit, count unresolved claims whose condition
  is `chain.unresolved_here` or `chain.unresolved_above`, where the link that
  left the chain open is a supertype no indexed unit in scope declares.
- Split that count by what the open supertype is: a JDK type, a third-party
  dependency, or a type inside the repository that the visibility boundary
  hides. The third group is [Follow-up 011](011_java_cross_module_visibility.md)
  and needs no external shape at all.
- Report how many of those claims would become facts if the chain closed, using
  the rule as written rather than a model of it.

Only above the threshold, write the ADR. Whatever it admits, the shape it
admits is already fixed by [ADR 011](../adr/011_java_hierarchy_from_indexed_source.md)
D6: an external shape may rule a name out and must never be selectable as a
target, so no external member can become the target of a fact.

Not in scope here, and not to be folded in: non-simple receivers such as
`new X(...).run()`, and overload resolution over external generic APIs. Both are
boundaries [Follow-up 014](014_java_instance_receiver_calls.md) named when it
closed, and each needs its own evidence.

## Required Tests

- A class implementing an interface with no shape evidence keeps the current
  unresolved answer, with the same condition named. This is Follow-up 013's test
  and must not regress.
- With shape evidence available, a member type declared by an external supertype
  keeps the name unresolved.
- With shape evidence available, no external member is ever recorded as the
  target of a fact.
- Shape evidence that is absent, ambiguous, or unreadable keeps the unresolved
  answer rather than assuming the external type declares nothing.
- The same repository indexed without the external evidence source produces the
  same answers as today, so a result never depends silently on what is installed
  on the machine that ran the index.
