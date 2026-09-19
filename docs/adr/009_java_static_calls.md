---
title: "Allow Java static calls through a class-name receiver"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-19"
---

# 009: Allow Java Static Calls Through A Class-Name Receiver

## Feature Or Dependency

The Java frontend records every invocation with a receiver as an unresolved
`CALLS` assertion whose designator is the invocation text, because it cannot
establish what the receiver is. That single reason accounts for 4,624 of 5,662
unresolved calls in the external sample.

[ADR 003](003_reject_name_match_assertions.md) rejects repository-wide name
matching as graph authority but leaves room for a frontend to resolve across
units when it applies language-correct evidence.
[ADR 006](006_allow_narrow_zig_member_definitions_and_local_import_calls.md) is
the precedent for a narrow cross-unit `CALLS` fact, and
[ADR 004](004_allow_java_same_package_type_resolution.md) with
[ADR 008](008_java_visibility_boundaries.md) already decide how a Java simple
name reaches another unit and how far it may reach.

This record decides one case inside that room: an invocation whose receiver is a
**class name**, such as `StringUtils.isNotEmpty(value)`. The implementation plan
is [012: Java Semantic Quality Without Query Regression](../plans/012_java_semantic_quality_without_query_regression.md),
whose Stage 0 measurement this record rests on.

## Evidence

Measured in
[Plan 012 Stage 0](../reports/012_java_semantic_quality_without_query_regression_progress.md)
against apache/dubbo at `df9c5e1` — 119 Maven modules, 4,050 Java source units —
over a sample of 1,200 definitions and 6,710 outgoing claims.

| Measurement | Count |
| --- | ---: |
| Receiver-qualified unresolved calls | 4,624 |
| Of those, receiver is a class name | 1,041 |
| Of those, exactly resolvable under the rule below | **135** |
| Blocked: receiver class is declared in no indexed unit | 382 |
| Blocked: the referring class has supertypes (ADR 004 guard) | 247 |
| Blocked: the class is outside the ADR 008 boundary | 113 |
| Blocked: the method name is overloaded in the target class | 74 |

Two facts shape the decision. First, this is the larger half of the receiver
problem that can be answered exactly: the instance-receiver subset, which needs a
method-body type environment, measured 63. Second, the obscuring rule below
costs nothing — all 135 satisfy its strictest form — so exactness here is not
bought with recall.

## Decision

The Java frontend may record a `CALLS` **fact** from a method to a method when
an invocation's receiver is a simple name and **every** condition below holds.
Any condition that is not established leaves the assertion unresolved, carrying
its designator, producer, freshness, and a reason naming the condition that
failed.

**The receiver is a type, not a value.**

1. The receiver expression is a single identifier. `this`, `super`, a literal, a
   field access, a chained call, a parenthesized or cast expression, and a
   qualified name such as `a.b.C` are not covered.
2. No binding introducer visible at the invocation declares that name: no formal
   or spread parameter, no local variable declarator, no field of the enclosing
   class, and no name introduced by an enhanced `for`, a `catch` parameter, a
   try-with-resources resource, a lambda parameter, or a type or record pattern.
   A binding that a future frontend covers still poisons the name here.
3. The enclosing top-level class declares no superclass and no interface, so no
   inherited field can obscure the name with a value the working copy cannot see.
4. The name resolves through the existing `resolveType` to exactly one current
   top-level Java class, with every one of its guards intact: type parameters,
   member types, static imports, non-class types declared in the unit,
   single-type imports, the unit's own package, and the
   [ADR 008](008_java_visibility_boundaries.md) visibility scope.
5. The invocation is not inside a class body declared in a method.

**The target is one declared static method.**

6. The target class declares exactly one method of the invoked simple name.
7. That method is `static`.
8. Its access is inside the covered subset: `public`, or any access when the
   target class is the top-level class enclosing the invocation.
9. The target class declares no superclass and no interface.

The recorded fact names that declared method. A Java `CALLS` fact established by
this record means the statically selected declared method, which for a static
method is the whole story: static methods are not dispatched.

Class shape and method modifiers are carried as **Java extension labels** on the
definitions the frontend already records — at minimum a class label stating
whether supertypes are declared, and method labels for covered access and
`static`. They are graph assertions produced by the Java frontend, visible as
extension data, and owned by `SPEC.md` and the capability matrix.

Nothing is read but the analyzed unit's source and graph facts about other
units. No build file is read, no build tool is executed, no network is used, and
no shared-core kind is introduced.

## Rationale

**Why a class-name receiver and not a value receiver.** A value receiver needs
the static type of an expression, which needs a lexical type environment over
method bodies. A class name needs no type inference at all: it is the same name
resolution `resolveType` already performs for field and return types. The
measurement says the cheap half is also the larger half, 135 against 63.

*Rejected: build the type environment first and take both.* That is the original
Plan 012 subject, and its own gate declined it at 63 against a required 100. It
remains [Follow-up 014](../followups/014_java_instance_receiver_calls.md).

**Why obscuring must be disproved rather than assumed.** Java lets a variable
obscure a type of the same name: where a local `foo` and a class `Foo` are both
in scope, `foo.m()` means the local. Reading a receiver as a class because a
class of that name exists would select a target by name, which is exactly the
failure [ADR 003](003_reject_name_match_assertions.md) rejects.

*Rejected: use the capitalization convention.* Class names are conventionally
capitalized, and the measurement shows the convention holds in practice. It is
still a style, not a language rule, and a graph that records facts cannot rest on
one. A `Runnable r` named `Handler` would produce a false fact and nothing in the
source would say so.

*Rejected: check only the enclosing method's bindings.* Fields obscure too, and
so do fields inherited from a supertype. The first is cheap to check; the second
is not visible when the supertype's source is absent, which is why condition 3
refuses the whole case instead. The measurement shows this costs nothing: every
one of the 135 already resolves its receiver through a `resolveType` path that
declines inside a class with supertypes.

**Why the target class may not declare supertypes.** A class that declares
exactly one method of a name may still inherit an overload of that name with
different parameter types, and Java would select between them by argument types,
which this record does not compute. A declared method also hides an inherited
static method, so the visible declaration is not evidence that it is the
selected one. Plan 012 Stage 0 measured whether the hierarchy could be closed in
source instead: of 210 such cases in the sample, **none** had a hierarchy fully
declared inside the indexed working copy — every one reached a JDK, framework or
dependency supertype.

*Rejected: resolve when the name is declared once in the target class regardless
of supertypes.* It is worth 211 in the sample, and it would be a guess in all of
them.

**Why `static` is required.** `ClassName.m()` where `m` is an instance method is
not a call Java compiles. Recording it would assert a relationship the language
does not have, and the frontend already knows the modifier by the time it
answers.

**Why the access subset is public plus the enclosing class.** Public is decidable
from the provider's own declaration and needs no knowledge of the caller.
Extending it to package-private and protected would also be decidable — both are
accessible within one package, and the package is already known exactly — but no
measurement supports the wider subset yet, and Plan 012's thresholds are stated
against the public count. The same-class case is added because it is free: a
class may reach its own private members, and both ends are in one unit.

*Rejected: admit package-private and protected now.* It widens the covered
subset ahead of evidence, and it would silently change Plan 012's Stage 7
denominator. A later plan may admit it with its own measurement.

**Why extension labels rather than re-reading provider source.** The frontend
contract does not expose another unit's bytes or parse tree to dependent
analysis, and adding that channel would make every lookup a parse. Labels put
the evidence where the graph already carries language-specific meaning, and they
keep the projection a projection: it may find candidates, but the fact exists
only where the frontend records it.

*Rejected: a shared-core kind for methods, signatures, or inheritance.*
[CORE.md](../../CORE.md) admits a kind on multi-language evidence, and this is
one language's question. Java method signatures stay part of Java method
definition identity.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Preserved. The frontend records a
   relationship it can establish, with its resolution, producer, evidence and
   freshness. The Java projection finds candidates; it never answers for the
   graph, and it re-reads graph facts before answering.
2. **Nodes as entities, not chunks.** Preserved. No entity kind is added. A
   static call is a relationship between two definitions that already exist;
   class shape and method modifiers are labels on those definitions, not nodes.
3. **Facts, unresolved and approximate stay distinct.** Strengthened. Every
   condition that fails produces a distinct unresolved reason — obscured name,
   no such class, outside the boundary, overloaded, non-static, inaccessible,
   target class has supertypes — instead of one reason for everything. No
   approximate assertion is introduced, and nothing that was a fact becomes one
   by a weaker rule.
4. **Stable semantic identity.** Preserved. Targets are existing Java method
   definitions identified as they already are. No identity is derived from byte
   ranges or tree-sitter node ids, and an edit that moves a method within its
   class does not change what the call names.
5. **Incrementality and consistent observation.** Preserved, and it is the part
   this record most constrains. A resolved cross-unit call declares a provider
   dependency, and the class-shape channel must reach readers when the provider's
   method set, method access, `static` modifier, or declared supertypes change —
   including readers whose call is currently unresolved and would become a fact.
   The projection depends only on each unit's own contents, so one round settles.
6. **Language frontends preserve meaning.** Preserved. Obscuring, `static`,
   access and class shape are Java rules, expressed as Java extension vocabulary.
   They are not promoted into the shared core on one language's evidence.
7. **Consumers do not define the model.** Preserved. No MCP tool shape,
   argument, cursor, budget or contract version changes. New outcomes surface
   through existing relationship, resolution, producer, freshness and extension
   fields; the labels are visible because extension data already is.
8. **Local operation without mandatory source-data transmission.** Preserved.
   Every input is the working copy and the in-memory graph. No build execution,
   no dependency resolution, no network, at index or query time.

## Consequences

- Calls such as `StringUtils.isNotEmpty(value)` become `CALLS` facts where the
  utility class is visible under ADR 008, so `semidx_references incoming` on a
  static utility method starts answering the question it exists for.
- The same call stays unresolved, with a reason that says which condition failed,
  when the class is a dependency, the method is overloaded or non-static, the
  class or method is out of the covered subset, or the referring class has
  supertypes.
- Java definitions carry new extension labels, which adds bytes to every Java
  definition item at `detail=full`. Budget semantics do not change; what a given
  budget fits does, and Plan 012 Stage 7 owes that measurement.
- The write path gains a class-shape invalidation channel with reader hints. It
  may over-invalidate; it must not under-invalidate, and its cost is part of the
  refresh budget.
- The capability matrix must state the covered case precisely: static target, no
  dispatch, no hiding, no overloads, public or same-class access, target class
  without supertypes, and instance receivers still unresolved.

## What This Record Does Not Enable

It does not resolve instance receivers, `super`, chained receivers, class
literals, or `new Type().m()` — that is
[Follow-up 014](../followups/014_java_instance_receiver_calls.md). It does not
relax the supertype guard or traverse a type hierarchy — that is
[Follow-up 013](../followups/013_java_supertype_guard_relaxation.md). It does not
resolve static imports used as bare names, scoped receivers such as
`a.b.C.m()`, static field reads, constructor calls, or field references. It does
not admit overload resolution by argument type, method hiding, inheritance, or
dynamic dispatch. It does not read build descriptors or cross a module boundary,
leaving [Follow-up 011](../followups/011_java_cross_module_visibility.md)
untouched, and it does not widen ADR 004's or ADR 008's preconditions. It admits
no shared-core kind. It says nothing about Clojure or Zig.

## Verification Evidence And Planned Checks

Implemented by [Plan 012](../plans/012_java_semantic_quality_without_query_regression.md)
Stages 2 through 5, which must prove:

- a call to a unique public static method of a class with no supertypes resolves
  when the class is supplied by the same unit, the same source root, a
  standard-layout test-to-main root, and a single-type import;
- the same call stays unresolved when the method is non-static, overloaded,
  missing, or outside the covered access subset, each with its own reason;
- the same call stays unresolved when the target class declares a superclass, and
  separately when it declares an interface;
- a receiver name declared by any binding introducer — parameter, spread
  parameter, local (including a declaration after the call), field, enhanced
  `for`, `catch` parameter, resource, lambda parameter, type pattern, record
  pattern — leaves the call unresolved, and says the name is bound;
- a call inside a class with supertypes stays unresolved even when a class of
  that name exists, because an inherited field could obscure it;
- a call inside a class body declared in a method stays unresolved;
- a receiver class outside the ADR 008 boundary stays unresolved and keeps that
  boundary's own explanation;
- a provider edit that adds, removes, overloads, or changes the access or
  `static` modifier of the target method reanalyzes the caller and changes only
  the affected claim;
- a provider edit that adds a declared supertype turns an existing fact into an
  unresolved assertion, and removing one makes an unresolved call eligible
  again;
- per-invocation lookup work is bounded by class and method candidates rather
  than by repository size, and Plan 011's anchored query work bound still holds;
- no MCP tool contract changes, proved by the existing `zig build test-mcp` and
  `zig build preview-gate` lanes.
