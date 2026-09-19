---
title: "Java classpath boundaries"
doc_type: "follow_up"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-18"
---

# Java Classpath Boundaries

## Classification

`semantic_limitation`

## Source

Recorded as the main residual risk after Plan 003 added Java same-package
top-level type resolution.

See
[Plan 003 progress](../reports/003_java_package_type_resolution_progress.md#residual-risk).

## Current Behavior

Java same-package type resolution treats the indexed repository as one
classpath. If two build modules contain the same Java package name, a type in
one module can resolve to a class from another module as a `REFERENCES` fact.

## Why Deferred

Plan 003 intentionally admitted same-package resolution without adding `module`,
`IMPORTS`, build graph modeling, or classpath entities to the shared core. Those
questions need their own decision and evidence.

## Decision Record Reminder

When Java cross-unit work resumes, resolve this boundary before widening
same-package facts. This is the next preferred Java ADR candidate because the
current behavior can otherwise produce false facts across independent modules
that happen to share a package name. Java single-type imports are useful, but
they are lower priority than deciding how classpath or module visibility enters
resolution evidence.

## Acceptance Direction

A future Java resolution plan should choose how semidx represents or receives
classpath boundaries before widening same-package facts. It may stay in Java
extension vocabulary if no shared-core kind is justified; adding a shared-core
`module` or `IMPORTS` requires the normal CORE/SPEC admission evidence.

## Required Tests

- Two independent Java roots share a package and class name without becoming
  one visible package by default.
- A declared dependency between roots permits same-package resolution only in
  the allowed direction.
- Ambiguous or unavailable classpath data leaves references unresolved rather
  than selecting by repository-wide name.
- Existing one-package fixtures from Plan 003 still resolve.

## Resolution

Closed by [ADR 008](../adr/008_java_visibility_boundaries.md) and
[Plan 010](../plans/010_java_resolution_boundaries.md) Stages 3 and 4. A Java
unit's visibility scope is its derived source root, so the indexed repository is
no longer treated as one classpath, and a name declared outside the scope is an
unresolved assertion that says so.

All four required tests are implemented in `tests/vertical_slice_test.zig` and
`src/frontends/java.zig`:

- two independent roots sharing a package and class name do not become one
  visible package — `two source roots sharing a package do not become one
  visible package`;
- a declared dependency permits resolution in the allowed direction only — `a
  test source root reads its module's main source root, and not the other way
  round`, where the declared dependency semidx recognizes is the standard
  directory layout's test-to-main relationship;
- ambiguous or unavailable boundary data leaves references unresolved — `a path
  that does not spell its declared package resolves nothing and offers nothing`
  and `ambiguity inside one shared scope stays unresolved and still says it is
  ambiguous`;
- Plan 003 one-package fixtures still resolve — unchanged and passing.

One part is deliberately not closed. Cross-module visibility that a build
descriptor would establish stays unresolved, because ADR 008 declined to read
build descriptors. It is split into
[Follow-up 011](011_java_cross_module_visibility.md) with its own evidence and
required tests.

Measured on apache/dubbo at `df9c5e1`, the behavior this entry warned about
occurred zero times before the fix: the rule's other preconditions decline far
more often than they fire, so the defect was latent rather than active. It was
real nonetheless, and reproducible in two directories with no build file at all.
