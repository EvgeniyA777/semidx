---
title: "Java classpath boundaries"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-17"
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
