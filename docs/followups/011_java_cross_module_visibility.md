---
title: "Java cross-module visibility"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-18"
---

# Java Cross-Module Visibility

## Classification

`coverage_gap`

## Source

The part of [Follow-up 003](003_java_classpath_boundaries.md) that
[ADR 008](../adr/008_java_visibility_boundaries.md) deliberately did not close.
See [Plan 010 progress](../reports/010_java_resolution_boundaries_progress.md).

## Current Behavior

A Java source unit resolves same-package and single-type-import names only inside
its own Java source root, plus the one directional exception of a test source
root reading its module's main source root. Two modules that share a package and
where one declares a dependency on the other are a case Java permits and semidx
leaves unresolved. The reference carries its designator and says the name is
declared in a source root the unit cannot see.

## Why Deferred

ADR 008 chose not to read build descriptors. Recovering these references means
interpreting `pom.xml` inheritance, `dependencyManagement`, property
interpolation, and profiles — where a misread invents a dependency that does not
exist, which is the same class of false fact Plan 010 removed. Gradle offers no
data to read at all, because its build files are programs.

Measured against apache/dubbo at `df9c5e1`: 5 of 336 cross-unit reference facts
(1.5%) were cross-module and permitted by the declared dependency graph, all of
them a test class reading a main class of a module its `pom.xml` depends on. Of
the ordered source-root pairs that share a package, 64 cross modules with a
declared dependency and 184 cross modules with none, so any rule here must be
directional and evidence-based rather than permissive.

## Acceptance Direction

A future plan may admit cross-root visibility when it can establish the
dependency from evidence it can read without executing a build, and when it
states what an unreadable, ambiguous, or partially understood descriptor does —
which must be to leave the reference unresolved. If that evidence cannot be had
honestly for a build system, that build system's repositories keep the current
behavior rather than receiving a guess.

This is also the natural place to reconsider whether a shared-core `module` kind
is justified, since a second language would then have a comparable question.
[CORE.md](../../CORE.md) owns that admission and it is not implied by this entry.

## Required Tests

- A declared dependency between two modules sharing a package permits resolution
  in the declared direction only.
- A module pair with no declared dependency stays unresolved in both directions.
- An unreadable, ambiguous, or unrecognized build descriptor leaves every
  cross-root reference unresolved rather than widening or narrowing silently.
- The Plan 010 boundary tests continue to pass unchanged.
