---
title: "Allow Java same-package type resolution"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-14"
---

# 004: Allow Java Same-Package Type Resolution

## Feature Or Dependency

`semidx` currently resolves Java references only inside the analyzed source
unit. A Java class in `package demo` naming `Helper` therefore records an
unresolved designator even when another Java source unit in the same repository
declares `package demo; class Helper`.

[ADR 003](003_reject_name_match_assertions.md) rejected repository-wide name
matching as graph assertions, but explicitly left open a frontend applying its
language's scoping rules. This record decides that narrow case for Java
top-level types.

## Decision

The Java frontend may record a cross-unit `REFERENCES` fact from a Java
definition to a Java top-level class definition in another source unit when all
of the following are true:

- the referencing unit has an explicit package declaration;
- the reference is a simple unqualified type name;
- the current Java repository context contains exactly one current top-level
  class definition with the same package and simple name;
- the target definition is a current fact produced by the Java frontend; and
- the analysis result records the provider source unit it read, so later
  changes can invalidate the dependent.

This does not admit `module` or `IMPORTS`. The Java package remains
language-specific evidence in the Java extension vocabulary, and the package
binding table is an analyzer-side projection rebuilt from current graph state.
No package entity, module entity, import relationship, public contract, or
consumer surface is introduced by this decision.

Ambiguous matches, missing package declarations, missing providers, stale
providers, and unsupported Java constructs remain unresolved or diagnosed. They
must not be recorded as facts.

## Rationale

This relationship is established by Java scoping rules, not by a repository-wide
string search. The decisive evidence is the package declaration in the referring
unit, the package declaration and top-level class declaration in the provider
unit, and uniqueness within the current Java package binding context.

Keeping the package binding table outside the graph prevents this narrow Java
mechanism from becoming a shared-core `module` model by accident. The graph
stores the resulting relationship and its dependency because those are semantic
claims. The temporary lookup structure that found the provider is a projection:
it can be rebuilt from the graph's current Java facts and carries no authority
of its own.

The initial rule is intentionally smaller than Java's full resolution semantics.
It does not model imports, nested classes, default-package lookup, classpath
symbols, overloads, inheritance, or method dispatch. Those are future coverage
or admission questions, not implied by this decision.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Preserved. The graph records a
   relationship only when a Java frontend establishes it from source-derived
   Java semantics; the package lookup projection only finds the current
   provider candidate.
2. **Nodes as entities, not chunks.** Preserved. The target is an existing
   `definition` entity, not a text range or search hit.
3. **Facts, unresolved, and approximate stay distinct.** Preserved. Unique
   same-package type resolution is a fact; ambiguity and absence remain
   unresolved, and no approximate assertion is created.
4. **Stable semantic identity.** Preserved. The target entity keeps its graph id
   across established edits, and a lost provider identity makes dependent
   reanalysis observable rather than silently retargeting stale facts.
5. **Incrementality and consistent observation.** Preserved. The decision
   requires dependency declarations and package-export invalidation so cross-unit
   facts can be maintained incrementally.
6. **Language frontends preserve meaning.** Preserved. Java package semantics
   stay in the Java frontend and Java extension vocabulary; no shared-core kind
   is widened to mean "Java package".
7. **Consumers do not define the model.** Preserved. The change is driven by a
   frontend establishing Java meaning, not by a search or agent-context
   consumer wanting more edges.
8. **Local operation without mandatory source-data transmission.** Preserved.
   The binding context is built locally from indexed source and existing graph
   state.

## Consequences

- The repository-scale Java fixture can change from unresolved `Helper` to a
  current `REFERENCES` fact targeting the `Helper` definition.
- The Clojure repository-scale fixture remains unchanged; this decision says
  nothing about namespace resolution.
- A new frontend/analyzer context contract is needed because the Java frontend
  currently sees one source unit and can target only local batch entities or
  designators.
- Adding, removing, renaming, or changing the package of a Java top-level class
  must invalidate affected Java units in that package, including units whose
  previous reference was unresolved because the provider did not exist yet.
- Coarse unit-to-unit dependencies may over-invalidate when a provider unit's
  implementation body changes. That is acceptable for this first cross-unit
  producer, and a finer invalidation rule can be introduced later without
  changing this decision.

## Verification Evidence And Planned Checks

The implementation plan is
[003: Java Package Type Resolution](../plans/003_java_package_type_resolution.md).
It must add tests proving:

- same-package Java top-level type references resolve across source units as
  facts;
- cross-package or ambiguous same-name references remain unresolved;
- provider edits, removals, and additions reanalyze affected dependents;
- unrelated packages are not reanalyzed by a package export change; and
- every new cross-unit fact remains attributable to the Java producer and does
  not create `module`, `IMPORTS`, or approximate assertions.
