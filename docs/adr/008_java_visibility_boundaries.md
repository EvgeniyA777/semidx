---
title: "Bound Java same-package resolution to a derived source root"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-18"
---

# 008: Bound Java Same-Package Resolution To A Derived Source Root

## Feature Or Dependency

[ADR 004](004_allow_java_same_package_type_resolution.md) lets the Java frontend
resolve a simple type name to a top-level class another source unit declares in
the same explicit package. It says nothing about which units are allowed to see
each other, so the rule treats every indexed Java unit as one classpath.

[Follow-up 003](../followups/003_java_classpath_boundaries.md) records the
consequence: two build modules that contain the same package name can resolve
into each other as a `REFERENCES` fact, which is a false fact under constitution
section 3. This record decides what establishes that two Java source units share
a visibility scope, and what happens when the evidence is absent.

## Evidence

Measured in [Plan 010 Stage 1](../reports/010_java_resolution_boundaries_progress.md)
against apache/dubbo at `df9c5e1` — 119 Maven modules, 4,050 Java source units —
and against a two-directory reproduction.

The defect is real. Two directory trees with no build file and no relationship,
each holding one class in package `demo`, produce a `fact` from one to the other.

The defect is also latent rather than active: of 336 cross-unit reference facts
in that repository, 170 join units in one source root, 161 join a test source to
a main source of the same module, 5 cross a module boundary their own `pom.xml`
declares a dependency across, and **none** is a resolution a Java compiler would
reject. ADR 004's other preconditions decline far more often than they fire, so
the rule rarely reaches far enough to be wrong. This record therefore removes a
trap, not a measured harm, and the count on one external repository cannot be
its proof.

Two layout measurements decide the rule below. In all 4,050 units, **zero** have
a path that disagrees with their declared package, so a source root is derivable
from layout alone. And of the ordered source-root pairs that share a package,
472 are the `main`/`test` pair of one module directory, 64 cross modules with a
declared dependency, and 184 cross modules with none.

## Decision

A Java source unit's **source root** is the prefix of its repository-relative
path that remains once the path spelled by its declared package and its file name
are removed from the end. `dubbo-common/src/main/java/org/apache/dubbo/rpc/Foo.java`
declaring `package org.apache.dubbo.rpc` has source root
`dubbo-common/src/main/java`. A unit whose path does not end that way, and a unit
with no explicit package declaration, has **no** source root.

Two Java source units share a visibility scope when either holds:

1. **Same root.** They have the same derived source root.
2. **Standard-layout test root.** The referring unit's source root is
   `<base>/src/test/<lang>` and the provider unit's source root is
   `<base>/src/main/<lang>`, for the same `<base>` and the same `<lang>`. This
   direction only.

Rule 2 is directional and is the only cross-root visibility this record grants.
A main source never resolves into a test source. Nothing else crosses a root.

The Java frontend applies ADR 004 unchanged inside that scope. Outside it,
nothing changes about how a reference is recorded: it stays an unresolved
assertion carrying its designator, its producer, and its freshness, exactly as a
reference to a type with no source in the working copy does.

In every one of these cases the reference is **unresolved**, never a
name-selected fact:

- the referring unit has no source root, because its path does not spell its
  declared package;
- the provider candidate has no source root;
- the two units' roots are different and rule 2 does not hold;
- the roots are the same but more than one current top-level class of that simple
  name is declared in the package there, which is ADR 004's existing ambiguity
  case, unchanged.

Nothing is read but the unit path and the package declaration already parsed from
the source. No build file is read, no build tool is executed, and no network is
used. `module`, `IMPORTS`, package entities, module entities, and classpath
entities are not introduced; the source root is Java extension vocabulary held in
the analyzer's projection, and the shared-core roster is untouched.

## Rationale

**Why the source root, and not the build module.** Java's own language rule is
that the directory hierarchy mirrors the package name, and every Java build tool
in common use enforces it. That makes the source root the one boundary that can
be derived from source organization alone, with no build descriptor and no
guessing — measured at 4,050 of 4,050 units in the probe repository. A Maven
module is a stronger notion of the same boundary, but reading it means
interpreting `pom.xml` inheritance, `dependencyManagement`, property
interpolation, and profiles, and a misread there would invent a dependency that
does not exist. That trades a false fact we can remove for a false fact we would
have to maintain. Gradle is worse: its build files are programs, not data.

**Why rule 2 exists at all.** Without it, the boundary would discard 161 of the
336 cross-unit facts the probe repository currently establishes — nearly half —
and they are true. `<base>/src/test/java` reading `<base>/src/main/java` is the
Maven Standard Directory Layout, which Gradle's Java plugin adopts unchanged; it
is a directory-structure convention, recognized by shape, not a build file read
as data. The direction matters and is not symmetric: main sources are compiled
without test sources on the classpath, so a main source resolving into a test
source is exactly the kind of claim this record exists to refuse.

**Why absence yields unresolved and not a fallback.** This is
[ADR 003](003_reject_name_match_assertions.md) applied to the boundary. If
semidx cannot establish that two units see each other, selecting a target by
repository-wide name is the failure ADR 003 rejected, and no amount of
convenience makes it a fact. Unresolved with an intact designator is the honest
answer and is already distinguishable from confirmed absence and from an
unsupported construct.

**What this costs.** The 5 cross-module facts in the probe repository — test
classes reading a main class of a module their `pom.xml` depends on, in a shared
package — become unresolved. That is 1.5% of the current cross-unit facts, and
losing them is the price of not reading build descriptors. It is recorded as
residual risk and split into its own follow-up rather than absorbed silently.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Preserved. The boundary narrows which
   assertions a frontend may establish as facts. No consumer, index, or
   projection gains authority, and the graph keeps recording the relationship —
   as unresolved where the boundary is not established.
2. **Nodes as entities, not chunks.** Preserved. No entity is created, removed,
   or redefined. A source root is a property computed from a unit's path and
   package, never a node.
3. **Facts, unresolved, and approximate stay distinct.** Strengthened; this is
   the record's purpose. A class of assertion currently presented as a fact
   without being established becomes unresolved, carrying its designator and the
   reason. No approximate assertion is introduced: an unestablished boundary
   yields no claim, not a low-confidence one.
4. **Stable semantic identity.** Preserved. Entity identity is unaffected; only
   whether a relationship's target is an entity or a designator changes. A unit
   moved between source roots reanalyzes under ADR 004's existing dependency
   invalidation.
5. **Incrementality and consistent observation.** Preserved. The source root is
   derived per unit from data the analyzer already has when it analyzes that
   unit, so it costs no extra pass, and the existing provider-dependency
   declaration continues to invalidate dependents. Because the boundary only ever
   removes candidates, it cannot widen the set of units a change invalidates.
6. **Language frontends preserve meaning.** Preserved, and this is the clause
   that decides against a shared-core kind. The source root expresses a Java
   rule — that the directory hierarchy mirrors the package — and means nothing
   in Clojure or Zig. Admitting it to the core would flatten a language-specific
   meaning into a common kind on the evidence of one language, which
   [CORE.md](../../CORE.md) forbids. It stays Java extension vocabulary, and the
   `module` admission question stays open for a plan with multi-language
   evidence.
7. **Consumers do not define the model.** Preserved. Nothing here is motivated by
   an MCP tool shape, a response budget, or an agent's convenience; no tool
   result shape changes, and the new outcomes surface through the existing
   resolution, designator, and freshness fields.
8. **Local operation without mandatory source-data transmission.** Preserved. The
   boundary is computed from the working copy alone: no build execution, no
   dependency resolution, no network, at index or query time.

## Consequences

- The minimal reproduction — two roots sharing a package with no relationship —
  becomes an unresolved assertion naming its designator.
- A main source that resolved into a test source of the same module becomes
  unresolved. The probe repository has no such fact today; the guard is what
  keeps it that way.
- Cross-module same-package references become unresolved even where a build tool
  would permit them, losing 5 facts in the probe repository.
- A repository that does not follow the standard directory layout, or whose
  layout disagrees with its package declarations, resolves nothing beyond each
  unit. It degrades to ADR 004's pre-cross-unit behavior rather than guessing.
- A unit with no explicit package declaration is unchanged: it resolved nothing
  beyond itself before this record and still does.
- The Java capability matrix entry must state the boundary in terms a user can
  act on, because the unresolved dependency edge is now two distinct things — a
  target with no source here, and a target with source here that this unit may
  not see.

## What This Record Does Not Enable

It does not admit a shared-core `module` or `IMPORTS`; those remain
[CORE.md](../../CORE.md)'s open questions. It does not read `pom.xml`,
`build.gradle`, `settings.gradle`, `module-info.java`, or any other build or
module descriptor, and it does not license a later plan to do so without its own
record. It does not widen ADR 004's preconditions: the supertype, member-type,
type-parameter, import, and ambiguity guards are untouched, and a name that fails
any of them is still unresolved inside a shared scope. It does not add Java
imports, qualified names, nested classes, inheritance, type hierarchy, method
call resolution, or field and member references. It says nothing about Clojure or
Zig.

## Verification Evidence And Planned Checks

Implemented by [Plan 010](../plans/010_java_resolution_boundaries.md) Stage 3,
which must prove:

- two independent source roots sharing a package and a simple class name do not
  become one visible package, and the reference is unresolved with its designator
  intact;
- a test source root resolves into its module's main source root, and the main
  source root does not resolve into the test source root — the same two units,
  one direction each;
- a unit whose path does not spell its declared package has no source root,
  contributes nothing to another unit's scope, and resolves nothing beyond
  itself;
- ambiguity inside one shared scope stays unresolved and keeps saying it is
  ambiguous;
- the Plan 003 one-package fixtures under `fixtures/repository-scale/java/demo/`
  still resolve unchanged;
- a cross-boundary unresolved reference keeps its designator, producer, and
  freshness, and stays distinguishable from confirmed absence and from an
  unsupported construct;
- the probe repository's cross-module false-fact count stays zero, which it
  already is, so this is a regression check rather than the proof.
