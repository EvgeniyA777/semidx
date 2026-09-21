---
title: "Establish the Java type hierarchy from indexed source"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-21"
---

# 011: Establish The Java Type Hierarchy From Indexed Source

## Feature Or Dependency

The Java frontend declines two large families of name because a supertype could
give the name another meaning, and it cannot check whether one does. A class
definition records *whether* it declares supertypes and never *which*, and a
top-level interface is not a definition at all — it raises
`unsupported_construct` and keeps its name only as a name that claims a name.

This record decides that the hierarchy becomes evidence the graph holds, and
what may then be concluded from it. It is the decision behind
[Plan 014](../plans/014_java_receiver_coverage.md), whose Stage 1 implements D1
and D2 and whose Stages 2 and 3 implement D3 to D8. It is the precondition
[Follow-up 013](../followups/013_java_supertype_guard_relaxation.md) names for
itself and [Follow-up 014](../followups/014_java_instance_receiver_calls.md)
names for both.

## Evidence

[Plan 014 Stage 0](../reports/014_java_receiver_coverage_progress.md#stage-0-price-both-halves-on-the-clone),
measured on apache/dubbo at `df9c5e1`, 4,050 Java source units, 26,509
definitions, whole graph rather than a sample. The claim families come from the
graph; the hierarchy is read from source, because the graph does not hold it.

| Measurement | Count |
| --- | ---: |
| Unresolved references the supertype guard declined | 8,083 |
| Unresolved call receivers the same guard declined | 6,206 |
| Of those 14,289, whose declared chain is closed in indexed source | **4,738** |
| Of those 4,738, whose chain reaches at least one interface | **3,628** (76.6%) |
| Top-level interfaces declared in source | 617, against 3,337 classes |
| Declared supertype links | 2,448, of which 1,647 in an interface position |
| Supertype links reaching an indexed declaration | 1,398, of which **856 an interface** |

Two readings of that table decided this record.

**The guard is not wrong; the evidence was never recorded.** Before any chain is
walked, over 61% of the supertype links that resolve at all resolve to an
interface. A plan that left interfaces as diagnostics would convert 1,110 of the
14,289 claims — 7.8% — and would have spent a chain walk, a projection, and a
dependency fan-out to get there.

**The walk is cheap on real Java.** No chain on the clone reaches depth 5, none
visits more than seven types, not one declares a cycle, and not one hits a depth
cap. The largest reader set a single type would owe a reanalysis is 33 units in
a 4,050-unit repository.

## Decision

The letters are Plan 014's, kept so the plan and this record name the same
things. D1 and D2 are implemented in the plan's Stage 1; D3 to D8 in its
Stages 2 and 3; D11 constrains all of them.

**D1 — An interface is a definition; an enum, a record, and an annotation type
are not.** An `interface_declaration` at the top level becomes a definition with
role `interface` and the labels a class carries — `java.construct`,
`java.package`, and `java.supertypes`, the last from its `extends` list by the
same `declared` | `none` rule. Its method declarations become definitions with
role `method` exactly as a class's do. The other three type declarations keep
their `unsupported_construct` diagnostic and keep claiming their names, because
none of them can appear in a supertype chain and admitting them would widen this
frontend into general Java type coverage without answering the question
interfaces answer.

Everything that reads a top-level type reads both roles: the package projection
exports an interface, the class-shape projection reports one, and `resolveType`
resolves a simple name to one under exactly the
[ADR 004](004_allow_java_same_package_type_resolution.md) and
[ADR 008](008_java_visibility_boundaries.md) conditions it already applies to a
class. No precondition is added and none is relaxed.

**D2 — An interface method's implicit modifiers are recorded as Java defines
them.** A method declared in an interface body with no access modifier is
`public`, not package-private, and `default` and `abstract` change neither
`java.access` nor `java.static`. Recording the absent modifier literally would
say something false about the source and would make every interface method look
inaccessible to [ADR 009](009_java_static_calls.md)'s access check, silently
suppressing the coverage D1 is for.

An interface's constants are a field for the obscuring rule and nothing else:
they are collected so a receiver name one of them claims is read as a value
(JLS 6.4.2), they keep their `unsupported_construct` diagnostic, and no
reference is emitted for their types. That is a coverage boundary, recorded
rather than implied.

**D3 — A declared supertype is a recorded reference.** Each `superclass`,
`interfaces`, and `extends_interfaces` type node emits a `references`
relationship from the declaring type's entity, resolved through the unchanged
`resolveType` in the **declaring** unit's scope, with its own evidence and
range. That is the only correct place to resolve it: what `Foo` means in a
supertype position is decided by the imports and package of the unit that wrote
it, never by the unit that later walks the chain.

**D4 — The hierarchy is closed, or the name stays unresolved.** A chain is
closed when every supertype reference on every reachable type is a current fact
naming a current Java class or interface inside the ADR 008 boundary. An
unresolved supertype, a stale or failed provider, a target that is not a class
or interface, an absent class-shape record, or a depth-cap hit leaves the chain
open, and the answer stays exactly what it is today, naming which condition
failed.

**D5 — Depth is capped and cycles are detected.** The walk carries a visited set
and a hard depth cap of 16. Hitting either is a decline with its own
explanation. A declared cycle is legal syntax and an illegal program; semidx
answers it with an unresolved claim, never with a fact and never with a hang.

**D6 — The chain rules out; it never selects.** Walking the chain answers one
question: does any reachable type declare a member type of this name, or a
method of this invoked name. If none does, the guard's reason has been disproved
and the existing rules decide as they already do. If one does, the name stays
unresolved. No inherited member is ever named as a target.

**D7 — Reading a chain declares a dependency on every type in it.** The
class-grained aspect in `java_members` gains the declared supertype set, so a
supertype edit changes the aspect of the type that declares it, and a reader
that walked a chain is hinted for every type it visited, not only for the one it
started at.

**D8 — The relaxation applies to both sides of the guard.** References and
receiver names are declined by one condition and are relaxed by one test, with
their distinct explanations preserved on both the success and the failure path.

**D11 — No new category and no new authority.** No approximate assertion, no
ranking, no name matching, no normalization. A chain walk is evidence gathering
over recorded facts, not a match.

## Rationale

**An interface is a declaration by every test this project applies.** It is a
program construct, not a text segment; it has a name a simple name can mean; it
declares methods a call can select; and it can declare supertypes. The only
reason it was not a definition is that the first Java slice covered classes.
Leaving it out was a coverage decision that has now been measured, and the
measurement says it is the dominant one.

**The evidence is recorded before the guard is touched, and that order is the
decision.** The alternative — relax the guard and accept a name match where the
hierarchy is unknown — is what [ADR 003](003_reject_name_match_assertions.md)
rejects, and it is why Follow-up 013 stayed deferred through two plans. D3 makes
the hierarchy a claim with its own resolution, so an open chain is *visible* as
an unresolved supertype rather than as an absence, and D4 can then be a test
over facts rather than an assumption about them.

**A chain that rules out cannot become a chain that selects.** D6 is the line
between this record and a type system. Establishing that no reachable type
declares a name is a negative answer over recorded facts; naming the inherited
member a call reaches is a positive answer that needs overload resolution,
dispatch, and generics this frontend does not have. The first is admitted, the
second stays unresolved and says so.

**The rejected alternative is reading the provider's source.** A unit's analysis
could parse its supertypes' files and answer every question directly. It is
rejected for the reason `java_members` exists: it would make every lookup a
parse, put a second reader of Java syntax in the pipeline, and make a unit's
claims depend on bytes its own analysis never received. The projection carries
graph facts and decides nothing; this record extends its vocabulary and does not
change its nature.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Preserved. Every new definition and
   every supertype claim is an assertion in the graph with its own producer,
   evidence, and resolution. The chain walk reads recorded claims and the
   class-shape projection, never source text of another unit, and no answer
   comes from outside the graph.
2. **Nodes as entities, not chunks.** Preserved. An interface and its methods
   are program constructs; a supertype link is a relationship between two
   entities, not a text range promoted to a node. Ranges stay projections that
   locate evidence.
3. **Facts, unresolved and approximate stay distinct.** Preserved, and this is
   the clause D4 and D11 serve. A supertype that does not resolve stays
   unresolved with its own explanation, which is what makes an open chain
   observable. The guard lifts only where every link is a current fact; every
   other outcome keeps today's answer and names the condition that failed. No
   approximate assertion is introduced, and no unresolved claim is presented as
   a fact.
4. **Stable semantic identity.** Preserved. Identity evidence for an interface
   is the same shape a class's is — unit scope, language, role, name, signature,
   empty container path — and its methods carry the interface name in
   `container_path`, so a body edit, a move inside the file, or a rename of the
   file leaves correspondence intact. Nothing derives identity from a supertype
   claim, so a hierarchy edit cannot break it.
5. **Incrementality and consistent observation.** This is the clause that costs
   something, and it is answered with numbers rather than with an assurance.

   A relaxed name depends on every type in the chain it walked, so an edit to
   any of them must reanalyze the reader. The channel already exists: the
   class-grained `Aspect` in `java_members` separates "this type appeared,
   disappeared, or changed whether it declares supertypes" from a method-grained
   change, and a reader is hinted per `Class.method` pair. D7 widens the aspect
   to carry the declared supertype set and widens the hint to every type a walk
   visited. Nothing new is invented; a hint is still a superset re-read from the
   graph before it is used, and a hinted unit that no longer walks that chain
   costs a pass and changes no claim.

   The fan-out this buys was measured before it was accepted. On apache/dubbo no
   chain reaches depth 5, no walk visits more than seven types, and the largest
   number of distinct reader units a single type would owe is 33 out of 4,050 —
   an interface named `Prioritized`. Propagation stays bounded by the existing
   budget and continues to report exhaustion as a diagnostic rather than
   silently.

   Termination is not left to the shape of real code: D5 caps depth at 16 and
   carries a visited set, so a declared cycle answers unresolved instead of
   hanging, and a pathological hierarchy declines instead of running away.
   Consistent observation is untouched: a query still reads one published
   snapshot, and a walk happens inside one analysis pass over facts published
   before it.
6. **Language frontends preserve meaning.** This is the clause D1 and D2 serve.
   What an interface is, what `default` means, what an unmodified interface
   method's access is, and what may appear in a supertype chain are Java's
   questions, and they are answered in the Java frontend's own extension labels.
   The shared core learns that a definition exists and that one entity
   references another; it never learns what an `interface_declaration` is. No
   core kind, no inheritance kind, and no new relationship kind is added — a
   supertype is an ordinary `references` claim.
7. **Consumers do not define the model.** Preserved. No MCP tool's arguments,
   result shape, cursors, or budgets change. Interfaces appear in results
   because they are definitions, not because a tool learned about them, and no
   part of D1 to D8 was chosen because a query could render it more easily.
8. **Local operation without mandatory source-data transmission.** Preserved.
   Everything is read from the working copy by the same local parse and the same
   in-memory graph. No build descriptor, classpath, module, or jar is read, no
   network call is made, and evidence text stays behind `--allow-evidence-text`
   as before.

## Consequences

- Java coverage gains a definition kind. A repository whose API surface is
  largely interfaces stops reporting that surface as a diagnostic: on
  apache/dubbo that is 617 top-level declarations and their methods.
- A name that used to decline as a non-class type this frontend does not cover
  now resolves when an interface of that name is in scope. That is coverage, not
  a defect, and every move is counted: on the fixture corpus, with the frontend
  changed and no fixture added, definitions, assertions, facts, unresolved,
  approximate and diagnostics are all identical to the values pinned before this
  record.
- The `unsupported_construct` diagnostic for a top-level interface disappears.
  The ones for enum, record, and annotation type declarations stay, and a member
  interface keeps the treatment every other member type has.
- An interface method with no access modifier is recorded `public`, so ADR 009's
  access check admits `Interface.staticMethod()` on the same terms it admits a
  class's. An interface's instance method still declines as not static.
- `entity_roles` for the Java frontend becomes `class`, `interface`, `method`,
  and the coverage note says what is now covered. Both are content of an
  existing field; no result shape changes.
- Stages 2 and 3 of Plan 014 add supertype claims and the walk. Each is gated on
  a measurement, and a failed gate ends that sequence rather than being argued
  past.

## What This Record Does Not Enable

- **No inherited member is ever selected.** `super.m()` and a call to a method a
  type inherits stay unresolved. D6 admits ruling out and nothing else.
- **No enum, record, or annotation type becomes a definition.** They keep their
  diagnostic and keep claiming their names.
- **No generic, array, wildcard, or `var` receiver type is admitted.** A
  supertype that is not a simple name leaves its chain open.
- **No build system enters.** Build descriptors, classpaths, modules, and jars
  stay out, as in Plan 012.
- **No name matching becomes graph authority.** ADR 003 stands as written, and a
  closed chain is evidence gathering, not a match.
- **No core kind, no inheritance kind, no new index, no published contract, no
  persistence, and no version bump.** `semantic_contract_version` stays `null`.

## Verification Evidence And Planned Checks

Delivered with D1 and D2:

- A test pins an interface definition, its role, its container path, its
  `java.construct`, `java.package` and `java.supertypes` labels, that it defines
  its three methods and not its constant, and that an interface extending
  another records `declared`.
- A test pins the implicit modifiers: an unmodified method and a `default`
  method are `public` and not static, a `static` method is static, and a
  `default` body's unqualified call to its own type's only method of that name
  is a fact.
- A test proves a top-level interface raises no `unsupported_construct` while
  enum, record, and annotation type declarations still do, and that a member
  interface is not admitted and still claims its name.
- A test proves `Interface.staticMethod()` resolves under ADR 009's existing
  conditions through both the same package and a single-type import, that an
  interface instance method declines as not static, that a missing method
  declines as missing, and that an interface with `extends` declines under the
  target-supertype rule.
- A test proves a simple name reaches an interface another unit declares in the
  same package, declares the dependency that keeps that fact current, and
  declines across a source-root boundary with ADR 008's own words.
- A test proves an interface constant obscures a receiver name exactly as a
  class field does.
- A test over the fixture corpus re-pins definitions, assertions, facts,
  unresolved, approximate and diagnostics, with the delta accounted for claim
  family by claim family.
- `zig build test-core`, `zig build test`, `zig build test-mcp`,
  `zig build dogfood`, and `zig fmt --check build.zig src tests` all pass.

Planned with D3 to D8, in Plan 014 Stages 2 and 3:

- A superclass and an interface list are recorded as references with their
  ranges, and an unresolved supertype keeps the type's chain open.
- The hierarchy projection reports a closed chain, an open chain, a cycle, and a
  depth-capped chain, each with its own reason.
- A fully indexed hierarchy resolves the name; an interface with no source in
  the working copy does not; a member type of the name anywhere in the chain
  does not; a cycle does not and does not hang.
- Adding a supertype anywhere in a walked chain reanalyzes the reader and
  removes a stale fact.
- The Plan 010 and ADR 008 boundary tests pass unchanged, and no claim outside
  the guard family changes resolution.
