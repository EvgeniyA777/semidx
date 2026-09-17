---
title: "Allow narrow Zig member definitions and local-import calls"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-17"
---

# 006: Allow Narrow Zig Member Definitions And Local-Import Calls

## Feature Or Dependency

[ADR 005](005_add_zig_frontend_and_local_mcp_preview.md) admitted the first Zig
frontend with deliberately narrow coverage: top-level functions, top-level
containers, and same-unit simple calls. That was enough for the first MCP
preview, but dogfooding on this repository now exposes two high-value gaps:

- many important implementation functions are declared directly inside
  top-level containers, such as `Server.handleLine`, and are currently reported
  as unsupported container members rather than definitions; and
- many calls from one Zig file to another go through a local relative
  `@import` alias, such as `protocol.writeString(...)`, and are currently
  unresolved designators.

[ADR 003](003_reject_name_match_assertions.md) rejects repository-wide name
matching as graph authority, but it explicitly leaves room for a frontend to
resolve across units when it applies language-correct evidence. This record
decides the narrow Zig dogfood case that Plan 006 will implement.

The implementation plan is
[006: Zig Dogfood Semantic Coverage](../plans/006_zig_dogfood_semantic_coverage.md).

## Decision

The Zig frontend may record a function declared directly inside a covered
top-level container as a `definition` when its identity can be established from
unit scope, language, role, name or signature when present, and containment
names. The identity must not be derived from byte ranges or tree-sitter node
ids.

The container definition may `DEFINES` the member function definition. Zig
container membership, container names, visibility, and construct details remain
Zig extension vocabulary or identity evidence; this decision admits no new
shared-core kind.

The frontend may analyze the body of such a member function under the same exact
narrow call rules as a covered top-level function. That permission does not
require Plan 006 to implement member body call analysis in the same stage as
member definitions; the plan may first expose member definitions and identity,
then add call facts in a later stage.

The Zig frontend may use a top-level declaration of the form
`const alias = @import("relative/path.zig");` as frontend-local analysis context
when the string names exactly one indexed Zig source unit under the same root.
The relative string is resolved lexically from the importing source unit's
directory, may use `.` or `..`, must stay under the indexed root, and must match
the indexed root-relative Zig path exactly, including case. Filesystem
case-folding, symlink resolution, or package search must not turn a non-exact
path into a match. The alias is not an entity and does not create a graph
relationship. No `module`, `IMPORTS`, package import, build graph, or public
import model is admitted by this decision.

Establishing such an alias means the dependent analysis read the provider source
unit. The analysis result must declare a dependency on that provider even when no
call through the alias resolves to a fact.

A qualified call `alias.foo(...)` may be recorded as a cross-unit `CALLS` fact
only when all of the following are true:

- `alias` was established by the local relative import rule above;
- the provider source unit is current and indexed;
- the provider declares exactly one current covered exported callable named
  `foo` in the provider file namespace;
- the target is a graph-established current `definition` fact; and
- the analysis result declared the provider dependency required by the alias
  rule.

For the first implementation, "exported callable" means a covered file-level
`pub fn` target. Extending that visibility rule to other Zig callable forms is
future coverage work and must preserve the same exactness, dependency, and
unresolved-case boundaries.

All other cases stay unresolved or unsupported, including package imports such
as `@import("std")`, missing or ambiguous providers, duplicate targets,
shadowed aliases, dynamic imports, value receiver calls such as `self.foo()`,
arbitrary member lookup such as `alias.Container.foo()`, dispatch, generic or
comptime-dependent resolution, nested containers, and unsupported visibility.

## Rationale

This decision is driven by dogfood value without turning dogfood convenience
into graph authority. A direct member function inside a top-level Zig container
is a program definition, not a retrieval chunk, when the frontend can establish
its containment and identity. Recording it as a `definition` lets repository map
and context tools answer useful questions about the implementation while still
keeping Zig-specific meaning in extensions.

Walking the body of a covered member function follows from the same reasoning:
the body is part of a covered callable definition. However, body walking is
implementation blast radius, not a reason to merge member identity and call
resolution into one stage. The ADR admits the architectural right; Plan 006
controls when each behavior lands.

For cross-unit calls, a relative `@import` alias is different from a
repository-wide name match. The provider unit is named by source syntax, the
path is resolved by a bounded exact rule, the target is selected from current
provider facts, and the dependent records that it read the provider even if the
specific call is still unresolved. The graph records the resulting `CALLS` fact
only when that evidence yields one exact target.

Keeping the alias outside the graph prevents this narrow Zig mechanism from
becoming a hidden `module` or `IMPORTS` admission. The graph stores the
definition and call facts; the temporary alias context is an analyzer-side aid
rebuilt from source and current graph facts.

The initial rule is intentionally smaller than Zig's full namespace, container,
method, import, package, comptime, and dispatch semantics. Those are future
coverage or admission questions, not implied by this decision.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Preserved. The graph records new facts
   only when the Zig frontend establishes them from covered Zig syntax and
   current graph facts; no text-derived search establishes a relationship.
2. **Nodes as entities, not chunks.** Preserved. Member functions become
   `definition` entities with containment evidence, not text ranges or chunks.
3. **Facts, unresolved, and approximate stay distinct.** Preserved. Covered
   member definitions and exact local-import calls are facts; ambiguity,
   unsupported constructs, missing providers, and receiver/member lookup outside
   coverage stay unresolved or unsupported. No approximate assertion is created.
4. **Stable semantic identity.** Preserved. Member identity is based on unit
   scope, language, role, name or signature when present, and containment names,
   never on tree-sitter node ids or byte ranges. Body edits preserve identity
   where correspondence is established; renames or containment changes make
   identity loss observable.
5. **Incrementality and consistent observation.** Preserved. Established local
   import aliases and cross-unit call facts require provider dependency
   declarations so provider changes can invalidate dependents, including when a
   previously unresolved call becomes resolvable after an exported function is
   added. Consumers continue to query published snapshots.
6. **Language frontends preserve meaning.** Preserved. Zig containment,
   visibility, import-alias evidence, and unsupported cases stay in Zig
   frontend behavior and extension vocabulary. No new core kind is admitted.
7. **Consumers do not define the model.** Preserved. The change is driven by
   frontend-established Zig evidence and dogfood fixtures, not by MCP or agent
   convenience deciding graph truth.
8. **Local operation without mandatory source-data transmission.** Preserved.
   The analysis runs locally over indexed source units and current graph state,
   with no external service or outbound source-derived data requirement.

## Consequences

- Plan 006 may change `Server.handleLine`-style declarations from unsupported
  constructs into current `definition` facts with container identity evidence.
- Plan 006 may later walk those member bodies under the same narrow call rules
  as covered top-level functions without requiring another architectural
  decision.
- Plan 006 may change a covered `alias.foo(...)` call through a relative local
  `@import` from an unresolved designator into a current cross-unit `CALLS` fact
  when the provider and target are uniquely established.
- Every established local import alias must declare its provider dependency,
  even when a call through that alias stays unresolved. Every cross-unit `CALLS`
  fact produced under this decision must use such a dependency, and provider
  edits must not leave stale facts answering as current.
- This decision does not admit `module`, `IMPORTS`, package imports, arbitrary
  namespace/member lookup, receiver resolution, dispatch, nested-container
  semantics, generic/comptime resolution, persistence, stable schemas, or a
  semantic contract version.
- Capability documentation must state the exact implemented Zig subset and the
  remaining false negatives.

## Verification Evidence And Planned Checks

Plan 006 must add tests proving:

- direct member functions inside covered top-level Zig containers become
  `definition` facts with container identity evidence;
- body edits preserve member identity, while renames or containment changes make
  identity loss observable;
- nested container declarations and unsupported member shapes remain unsupported
  or unresolved rather than confirmed absent;
- member bodies, when analyzed, use the same exact narrow call rules as covered
  top-level functions and leave receiver or arbitrary member calls unresolved;
- a relative local `@import` alias resolves only by exact lexical path
  normalization from the importing unit directory, rejects root escapes and
  case-mismatched paths, declares a provider dependency, and can support an exact
  `alias.foo(...)` cross-unit `CALLS` fact to one current exported provider
  callable;
- missing units, package imports, non-exported targets, duplicate targets,
  shadowed aliases, dynamic imports, and unsupported visibility stay unresolved
  with explanations;
- provider removals, renames, additions, and relevant export changes reanalyze
  dependents and exclude stale facts from default current queries; and
- no result introduces `module`, `IMPORTS`, approximate assertions, source text
  by default, or a non-null semantic contract version.
