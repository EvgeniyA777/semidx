---
title: "Java receiver coverage through indexed hierarchies"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "reference_for_context"
updated: "2026-09-20"
---

# 014: Java Receiver Coverage Through Indexed Hierarchies

## Goal

Convert the two Java families semidx declines most often, and convert them only
where the graph can establish the answer from indexed source: a name the
enclosing class's supertypes block
([Follow-up 013](../followups/013_java_supertype_guard_relaxation.md)), and a
call through a value receiver
([Follow-up 014](../followups/014_java_instance_receiver_calls.md)).

Measured on apache/dubbo at `df9c5e1`, whole graph, 4,050 Java units and 26,509
definitions
([Plan 012 progress](../reports/012_java_semantic_quality_without_query_regression_progress.md#stage-6-follow-up-discipline)):

| Family | Count |
| --- | ---: |
| Unresolved references declined by the supertype guard | 8,083 |
| Unresolved calls whose receiver name the same guard blocks | 6,206 |
| Unresolved calls whose receiver is a simple name a binding declares | 55,127 |
| Unresolved calls whose receiver is not a simple name | 21,132 |
| Java `CALLS` facts the graph holds, after Plan 012 | 2,214 |

[Plan 013](013_unresolved_mentions_from_the_callee_anchor.md) made those claims
reachable from the name they wrote. None of them is a fact, and this plan is
about the subset that can honestly become one.

**The finding that shapes the plan.** The hierarchy those guards protect against
is not in the graph at all:

- A class definition records *whether* it declares supertypes
  (`java.supertypes` = `declared` | `none`,
  [java.zig:639-660](../../src/frontends/java.zig#L639-L660)) and never *which*.
- A type reference is emitted for a field type and a method return type only
  ([java.zig:785](../../src/frontends/java.zig#L785),
  [java.zig:805](../../src/frontends/java.zig#L805)). The `superclass` and
  `interfaces` children of a class header are read for the boolean and for
  nothing else, so no supertype is a recorded claim.
- A Java interface is not a definition. `interface_declaration` at the top level
  raises `unsupported_construct` and the name is kept only as a name that claims
  a name (`other_types`,
  [java.zig:894](../../src/frontends/java.zig#L894)).

And interfaces are where the guard's opportunity sits: **218 of 335** sampled
guard declines are blocked because the enclosing class implements an interface.
So the hierarchy is open today for a reason that has nothing to do with the
guard being right — the evidence has never been recorded. This plan records the
evidence first and relaxes the guard second, and stops at a gate if the
evidence does not pay for the machinery.

Admitting interfaces is worth something on its own, before any relaxation: on an
interface-heavy Java repository a large part of the API surface is currently a
diagnostic rather than a definition, so it cannot be found, outlined, or
referenced at all.

## Product Principle

When a stage offers a choice, decide in this order:

1. **Exactness beats recall.** A new edge is a fact under §3 or it is not made.
   A relaxed guard that guesses is worse than the guard.
2. **Evidence before relaxation.** No guard is lifted before the evidence it
   needs is a recorded claim in the graph and has been measured there.
3. **A gate is a stop, not a speed bump.** Plan 012 stopped itself at its own
   Stage 0 and changed subject; that is the standard this plan is held to. Each
   of the three gates below has a number, and a failed gate ends the stage
   sequence it guards.
4. **The habit loop must stay usable.** Interfaces add definitions and
   supertypes add relationships. The Plan 011 work bounds and the
   `semidx_context depth=2` latency are acceptance criteria, not hopes.
5. **Unresolved reasons are product output.** A widened rule must not collapse
   distinct declines into one. Every condition that fails says which one it was.
6. **No Java build system enters by accident.** Build descriptors, classpaths,
   modules, and jars stay out, as in Plan 012.

## Start Rule

Read before starting:

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md) §1, §3,
  §5, §6, §11. §5 is on the list because a chain walk creates a dependency
  fan-out that incremental maintenance must carry.
- [ADR 003](../adr/003_reject_name_match_assertions.md),
  [ADR 004](../adr/004_allow_java_same_package_type_resolution.md),
  [ADR 008](../adr/008_java_visibility_boundaries.md),
  [ADR 009](../adr/009_java_static_calls.md).
- [Plan 012](012_java_semantic_quality_without_query_regression.md), especially
  [Stage 4](012_java_semantic_quality_without_query_regression.md#stage-4-reading-a-receiver-name-as-a-type),
  which specifies the covered binding list this plan reuses, and
  [its progress log](../reports/012_java_semantic_quality_without_query_regression_progress.md),
  sections "The Addressable Receiver Subset" and "Supertype Guard Opportunity".
- [Plan 013 progress](../reports/013_unresolved_mentions_from_the_callee_anchor_progress.md)
  Stage 4, whose per-anchor evidence names receivers one by one.
- [Follow-up 013](../followups/013_java_supertype_guard_relaxation.md),
  [Follow-up 014](../followups/014_java_instance_receiver_calls.md),
  [Follow-up 017](../followups/017_plan_012_external_evidence_reproducibility.md),
  [Follow-up 018](../followups/018_unexplained_assertion_delta.md).
- `src/frontends/java.zig`: `analyze`, `resolveType`, `emitTypeReference`,
  `emitInvocations`, `qualifiedTarget`, `Bindings`, `collectMethodBindings`.
- `src/frontends/java_members.zig`: `ClassShape`, `classShapeOf`, `methodsOf`,
  `Aspect`, `aspectsOf`, and the reader hint.

Create `docs/reports/014_java_receiver_coverage_progress.md` with standard
progress-log frontmatter before the first code change.

Stop and re-open this plan if Stage 0 finds that the guard's opportunity is not
dominated by interfaces after all. The stage order assumes it is; that
assumption is checked first and recorded.

## Scope

- Admit Java interface declarations as definitions, with the methods they
  declare, under the same labels a class carries.
- Record each declared supertype as a reference claim from the declaring type,
  resolved in the declaring unit's own scope.
- Walk that recorded hierarchy and relax the supertype guard exactly where the
  chain is closed in indexed source and nothing reachable declares the name.
- Extend invalidation so an edit to any type in a walked chain reanalyzes the
  readers that walked it.
- Attach declared types to the bindings Plan 012 already collects, and resolve a
  value-receiver call under Plan 012's rules where that declared type is exact.
- Record both halves as ADRs, measure both on apache/dubbo, and close or re-price
  Follow-ups 013 and 014 against what shipped.

## Non-Scope

Do not admit enum, record, or annotation type declarations. A supertype chain is
classes and interfaces and nothing else: a class extends a class and implements
interfaces, an interface extends interfaces, and no enum, record, or annotation
type can appear in that chain. Their declarations keep their current
`unsupported_construct` diagnostic and keep claiming their names.

Do not select an inherited member. The chain is walked to **rule out** — to
establish that no reachable type declares the name — and never to reach past the
type that declares it. `super.m()` and a call to a method a class inherits stay
unresolved, and a follow-up records them if the measurement makes them worth it.

Do not admit generic, array, wildcard, or `var` receiver types. Follow-up 014
prices that relaxation at 18 in the sample; it stays deferred and keeps its own
unresolved reason.

Do not change `resolveType`'s existing meanings. Type parameters, member types,
static imports, non-class types, single-type imports, the same-package rule, and
the ADR 008 boundary keep their current behavior and their current
explanations; the guard's decline is the only answer this plan may change.

Do not read build descriptors, classpaths, modules, or jars. Do not add an
approximate assertion, a core kind, a persistence layer, a contract, or a
version bump. `semantic_contract_version` stays `null`.

Do not change any MCP tool's result shape, cursors, budgets, or arguments.
Interfaces appearing as definitions changes counts, not shapes.

Do not cut a release. The next preview release follows this plan and is not part
of it.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md): §1
  graph authority, §3 fact/unresolved/approximate, §5 incrementality and
  consistent observation, §6 frontends preserve meaning, §11 the decision test.
- [ADR 004](../adr/004_allow_java_same_package_type_resolution.md) and
  [ADR 008](../adr/008_java_visibility_boundaries.md): what a simple name may
  reach, and how far.
- [ADR 009](../adr/009_java_static_calls.md): the conditions a call target must
  satisfy, which this plan extends rather than reopens.
- [ADR 003](../adr/003_reject_name_match_assertions.md): a name match is not
  graph authority.
- [MEMORY.md](../../MEMORY.md), [SPEC.md](../../SPEC.md),
  [CORE.md](../../CORE.md),
  [docs/spec/capability_matrix.md](../spec/capability_matrix.md),
  [docs/mcp/local_preview.md](../mcp/local_preview.md).
- [Documentation policy](../agent-policy/documentation.md) and
  [testing policy](../agent-policy/testing.md).

**Drift control at readiness.** The owners above were checked and are aligned
with this plan as written. No core kind is added, no contract is published, no
language is added to the roster, and no consumer shape defines a graph
semantic. Three owners will contradict the result once it lands and are closure
targets rather than readiness blockers:
[docs/spec/capability_matrix.md](../spec/capability_matrix.md) and
[docs/mcp/local_preview.md](../mcp/local_preview.md), which describe Java
coverage as class declarations and their methods, and
[MEMORY.md](../../MEMORY.md), whose near-term priorities name both follow-ups as
deferred. `MEMORY.md` is deliberately **not** updated at plan creation: it is a
bounded file at its limit, and a planned document that may stop at Gate A should
not spend lines there before it has a result. Stage 6 owns it.

One open finding must not be inherited silently:
[Follow-up 018](../followups/018_unexplained_assertion_delta.md) records an
unexplained assertion delta. Stage 0 records whether it still reproduces on this
clone, so a later delta is not attributed to this plan's changes by accident.

## Current Evidence

**One guard, two sides, both measured.** `resolveType` declines a simple type
name beyond its own unit when the enclosing class declares any supertype
([java.zig:986-989](../../src/frontends/java.zig#L986-L989)), and the same
condition declines a receiver name
([java.zig:1398-1401](../../src/frontends/java.zig#L1398-L1401)) and an
unqualified invocation ([java.zig:1349](../../src/frontends/java.zig#L1349)).
Whole-graph on the Dubbo clone that is 8,083 references and 6,206 call
receivers; sampled over 1,200 definitions it is 335 references, of which 38
would resolve to exactly one class if the guard were simply lifted and **13**
have a hierarchy closed in indexed source. The other 322 are the guard doing its
job — or the graph not knowing enough to say.

**The hierarchy is not recorded.** `java.supertypes` is a boolean
([java.zig:639-660](../../src/frontends/java.zig#L639-L660),
[java_members.zig:93](../../src/frontends/java_members.zig#L93)), supertype
names are never emitted as references, and an interface is not a definition.
The 13-of-335 figure is therefore not a measurement of how closed real Java
hierarchies are; it is a measurement of how much can be closed **without
interfaces**, which is the smallest possible version of the question.

**The projection and the invalidation channel already exist.**
`src/frontends/java_members.zig` reads class shape and method candidates from
graph facts and decides nothing, and `Aspect` already separates a class-grained
change ("appears, disappears, or starts or stops declaring supertypes") from a
method-grained one, with a reader hint per `Class.method` pair
([java_members.zig:240-300](../../src/frontends/java_members.zig#L240-L300)).
A chain walk extends that vocabulary; it does not need a new one.

**The type environment is half-built.** Follow-up 014 defers on the cost of "a
lexical receiver type environment over method bodies". Plan 012 Stage 4 built
the lexical half: `Bindings` collects field names, parameters, and locals
visible at an invocation, with declaration-order visibility and poisoning for
uncovered introducers
([java.zig:1591-1606](../../src/frontends/java.zig#L1591-L1606)). What is
missing is one field per binding — the declared type — not the machinery that
finds the bindings.

**The prices to beat.** Plan 012 shipped 2,214 static-call facts whole-graph
with no hierarchy walk. The sampled instance-receiver subset was 63 addressable
in 1,200 definitions, which scales to roughly 1,390 whole-graph
(63 x 26,509 / 1,200), and 627 of the 1,311 receivers blocked by an unresolvable
receiver type are blocked by this very guard — which is why Follow-up 014 names
Follow-up 013 as its precondition and why the two are one plan here.

## Architecture Decisions

These are decisions, not open questions. An executing agent applies them.

**D1 — An interface is a definition; an enum, record, and annotation type are
not.** An `interface_declaration` at the top level becomes a definition with
role `interface`, the labels `java.construct`, `java.package`, and
`java.supertypes` (its `extends` list, by the same `declared` | `none` rule),
and its method declarations become definitions with role `method` exactly as a
class's do. The other three type declarations keep their current
`unsupported_construct` diagnostic, because none of them can appear in a
supertype chain and admitting them would widen this plan into general Java type
coverage.

**D2 — An interface method's implicit modifiers are recorded as Java defines
them.** A method declared in an interface with no access modifier is `public`,
not package-private, and `default` and `abstract` change neither `java.access`
nor `java.static`. Recording the absent modifier literally would make every
interface method look inaccessible to ADR 009's access check and silently
suppress the coverage this stage is for.

**D3 — A declared supertype is a recorded reference.** Each `superclass`,
`interfaces`, and `extends_interfaces` type node emits a `references`
relationship from the declaring type's entity, resolved through the unchanged
`resolveType` in the **declaring** unit's scope, with its own evidence and
range. This is the only correct place to resolve it: what `Foo` means in a
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
class-grained `Aspect` gains the declared supertype set, so a supertype edit
changes the aspect of the class that declares it, and a reader that walked a
chain is hinted for every type it visited, not only for the one it started at.
The fan-out this produces is measured in Stage 3 and is an acceptance input, not
an assumption.

**D8 — The relaxation applies to both sides of the guard.** References and
receiver names are declined by one condition and are relaxed by one test, with
their distinct explanations preserved on both the success and the failure path.

**D9 — Bindings gain a declared type and nothing else.** Plan 012's covered
binding list stands unchanged, and every introducer outside it still poisons the
name for its lexical region. A covered binding records the type its declaration
writes; a declared type that is not a simple name — generic, array, wildcard,
`var` — is recorded as uncovered and declines with its own reason.

**D10 — A value-receiver call is a fact only when every condition holds at
once**: the receiver is a simple name bound by a covered introducer; its
declared type is a simple name; that name resolves through the unchanged
`resolveType` inside the ADR 008 boundary; the target type declares exactly one
method of the invoked name; access permits the call; the call is not inside a
nested class body; and the target type either declares no supertypes or has a
chain closed under D4 in which nothing declares the name. `this.m()` is admitted
on the same terms, because the enclosing type is known exactly. `super.m()` is
not, because it selects an inherited member (D6).

**D11 — No new category and no new authority.** No approximate assertion, no
ranking, no name matching, no normalization. ADR 003 stands as written, and a
chain walk is evidence gathering, not a match.

**D12 — The gates are arithmetic fixed in advance.** Three gates, each measured
on something that exists when it is measured:

| Gate | When | Test | If it fails |
| --- | --- | --- | --- |
| **A** | end of Stage 0, from a source classification | A1: at least half of the guard family's closable opportunity depends on interfaces. A2: the closed-hierarchy upper bound is **>= 1,000** whole-graph claims (references plus call receivers). | Stages 1-4 are not executed. Stage 0 then prices the value-receiver half on today's graph; if Gate C passes there, the plan continues at Stage 5 by amendment. If both fail, the plan closes as measured-and-declined and both follow-ups are re-priced. |
| **B** | end of Stage 2, from the real graph | Guard-declined claims whose chain is now closed in indexed source: **>= 700**. | Stage 3 is not executed. Interfaces and supertype references stay — they are value on their own — and Follow-up 013 is re-priced with the first honest number anyone has had. |
| **C** | Stage 4 re-measure, from the real graph after Stage 3 | Value-receiver calls addressable under D10: **>= 1,000**. | Stage 5 is not executed. The plan closes after Stage 6 with the supertype half shipped and Follow-up 014 re-priced. |

The floors are chosen against what Plan 012 bought and what the samples predict.
1,000 whole-graph claims is 7% of the 14,289-claim guard family and about half
of Plan 012's 2,214 facts, for strictly more machinery — a walk, a dependency
fan-out, and a new definition kind. Without interfaces the sample predicts
13/335 x 14,289 = about 554, so Gate A2 cannot be cleared by the pre-interface
subset alone and is a real test of D1. For Gate C, the sampled 63 scales to about
1,390, and Stage 3 should raise it, so 1,000 is the level below which the type
environment is not paid for.

## Architecture Boundaries

1. **The Java frontend** decides what a Java name means, what a supertype is,
   and when a chain is closed. It reads its own unit's source and the projection
   the analyzer hands it, never another unit's syntax.
2. **The projection** (`java_members.zig`, and the hierarchy reader added
   beside it) carries graph facts and decides nothing. It creates no entity, no
   inheritance kind, and no relationship.
3. **The core graph** is untouched: no new kind, no new index, no new filter. A
   supertype is an ordinary `references` claim and a hierarchy is a walk over
   claims that already exist.
4. **The MCP preview** is untouched. Interfaces appear because they are
   definitions, not because a tool learned about them.
5. **Tests and gates** prove each unresolved reason separately, the chain's
   termination, the dependency fan-out, and that no family moved that this plan
   did not name.

## Executor Recommendation

A judgement about what each stage demands, not a measurement of any model.
Treat it as a default to depart from with a reason.

| Stage | What makes it hard | Recommended |
| --- | --- | --- |
| 0 | Numbers only, but Gate A decides whether four stages exist; the trap is an estimate that flatters the plan that commissioned it | Strongest available model |
| 1 | New definition coverage with Java's implicit modifier rules, and a diagnostic that must stop appearing without anything else moving | Strongest available model |
| 2 | Supertype references plus the first real measurement of closedness; small code, high consequence | Strongest available model |
| 3 | The relaxation itself: chain walk, cycles, depth, both guard sides, and a dependency fan-out that §5 must survive | Strongest available model |
| 4 | Mechanical re-measure; the risk is explaining a delta away instead of naming it | Mid-tier model |
| 5 | Large but specified: Plan 012 Stage 4 already wrote the binding rules, and this adds one field and one target test | Mid-tier model, strongest if Gate C is close to its floor |
| 6 | Canon: capability matrix, preview reference, `MEMORY.md`, roadmap, follow-up statuses, drift control | Mid-tier model |

Two notes that outrank the table:

- **Each ADR belongs in the same session as the stage it decides.** ADR 011 with
  Stage 1, ADR 012 with Stage 5. An ADR written afterwards by someone else
  becomes a retelling of the diff.
- **Zig 0.16 is read, never recalled.** Every stage reads the neighbouring
  source before editing it, as [RULES.md](../../RULES.md) requires.

## Implementation Stages

### Stage 0: Price Both Halves On The Clone

Purpose: decide, before any code, whether the interface-shaped opportunity is
real and large enough to pay for a hierarchy walk.

Likely files:

- `docs/reports/014_java_receiver_coverage_progress.md`
- `src/java_coverage.zig` and `build.zig` (a developer-only command, as
  `designator-shape` and `claim-sample` are)
- `docs/followups/013_java_supertype_guard_relaxation.md`, `docs/followups/014_java_instance_receiver_calls.md`,
  `docs/followups/018_unexplained_assertion_delta.md`

Required work:

- Run `./scripts/check-zig-version.sh`; record commit, worktree state, clone
  path, and clone commit.
- Reproduce today's baseline on apache/dubbo at `df9c5e1`: assertions, facts,
  unresolved, the unresolved-reason families `claim_sample` already names, and
  the definition and diagnostic totals. Record whether
  [Follow-up 018](../followups/018_unexplained_assertion_delta.md)'s delta still
  reproduces.
- Classify the guard family from source: for each guard-declined reference and
  receiver, the enclosing type's declared supertypes, and for each supertype
  whether a top-level declaration of that name exists inside the ADR 008
  boundary, split by class and interface. Produce the **upper bound**: claims
  whose whole chain has an indexed declaration for every link. Label it an
  upper bound in the log, because it does not yet check member types, access,
  staleness, or the real resolution of each name.
- Classify the value-receiver family the same way: covered introducer, declared
  type shape, target type resolvable, exactly one method of the name, access,
  target supertypes. Record it both as it stands today and as it would stand if
  the guard were relaxed.
- Measure the fan-out input: chain lengths encountered, the distribution of how
  many types a chain visits, and the largest number of readers a single class
  would hint under D7.
- Document the classification procedure in the progress log in enough detail to
  re-derive it without the program, as
  [tooling.md](../agent-policy/tooling.md) requires.

Branch handling:

- Gate A as defined in D12. A pass records both numbers and continues to Stage 1.
- A fail records both numbers, prices the value-receiver half on today's graph,
  and either continues at Stage 5 by a recorded amendment or closes the plan.
  Either way Follow-ups 013 and 014 are updated with the new figures in the
  same commit.

Done when: the log names the clone, the commit, the seed, the procedure, every
count above, and the Gate A verdict in the same words the plan uses.

Verification: `./scripts/check-zig-version.sh`, `zig build test-core`,
`zig fmt --check build.zig src tests`.

### Stage 1: Interfaces Are Declarations The Graph Holds

Purpose: put the dominant blocker's evidence into the graph, and gain the Java
API surface that is currently a diagnostic.

Depends on: Stage 0 (Gate A).

Likely files:

- `src/frontends/java.zig`, `src/frontends/java_members.zig`
- `docs/adr/011_java_hierarchy_from_indexed_source.md`, `docs/adr/README.md`
- fixtures and tests under `fixtures/`, `tests/`, `src/frontends/root.zig`

Required behavior:

- D1 and D2: interface declarations and their methods become definitions with
  the labels a class carries, implicit modifiers recorded as Java defines them.
- `other_types` no longer claims a name an indexed interface now declares, and
  `resolveType` may resolve a simple name to an interface under exactly the
  ADR 004 and ADR 008 conditions it already applies to a class — no new
  precondition, no relaxed one.
- `classShapeOf` and `methodsOf` accept an interface as a provider, so
  `Interface.staticMethod()` is decided by ADR 009's existing conditions rather
  than by the absence of a record.
- The `unsupported_construct` diagnostic for a top-level interface disappears;
  the ones for enum, record, and annotation types stay, and a test proves both.
- Write ADR 011 recording D1-D8 and D11, answering every §11 question, with §5
  answered concretely rather than waved through: the dependency fan-out of a
  chain walk is the clause's hard case.

Branch handling:

- A nested or member interface is not a top-level declaration and is not
  admitted here; it keeps its current treatment and a test pins that.
- If admitting interfaces changes a resolution that has nothing to do with the
  guard — a name that used to be claimed by `other_types` and now resolves —
  that is coverage, not a defect, but every such move is counted in the log and
  a fixture pins one example.

Done when:

- Fixture tests prove an interface definition, its methods, its labels, its
  `java.supertypes` value, and an interface method with no access modifier
  recorded as public.
- A test proves a static call to an interface's static method resolves under the
  same ADR 009 conditions, and that a `default` method does not become static.
- Fixture corpus counts are re-pinned deliberately, with the delta explained in
  the log claim family by claim family.
- ADR 011 is committed and linked from the commit message.

Verification: `zig build test-core`, `zig build test`, `zig build test-mcp`,
`zig build dogfood`, `zig fmt --check build.zig src tests`.

### Stage 2: A Declared Supertype Is A Recorded Claim

Purpose: make the chain readable from the graph, and measure how much of it is
actually closed — the first honest answer to the question Gate A estimated.

Depends on: Stage 1.

Likely files:

- `src/frontends/java.zig`
- `src/frontends/java_hierarchy.zig` (new projection beside `java_members.zig`)
- `src/java_coverage.zig`, tests

Required behavior:

- D3: every declared supertype emits a `references` claim from the declaring
  type, resolved in the declaring unit's scope, with evidence and range. A
  supertype that does not resolve stays unresolved with its existing
  explanation, which is what makes an open chain visible.
- A hierarchy projection reads those claims and reports, for one type: its
  direct supertypes as entities, or the first reason the chain is not closed.
  It performs no relaxation and no name matching, and it is not used by the
  frontend's decisions yet.
- No guard changes in this stage. Every existing unresolved answer is
  byte-identical, proven over the fixture corpus.

Branch handling:

- Gate B as defined in D12, measured with the Stage 0 tool over the real graph.
  A fail stops the sequence here: Stages 3 and 4 are not executed, the numbers
  go into Follow-up 013, and Gate C is measured here instead of in Stage 4,
  with the Stage 0 tool over the graph as it then stands. The plan continues
  at Stage 5 only if that verdict passes, and closes at Stage 6 otherwise.

Done when:

- A test proves a superclass and an interface list are recorded as references
  with their ranges, and that an unresolved supertype keeps the type's chain
  open.
- A test proves the projection reports a closed chain, an open chain, a cycle,
  and a depth-capped chain, each with its own reason.
- The log records reference and assertion count deltas on fixtures and on the
  clone, and the Gate B verdict.

Verification: `zig build test-core`, `zig build test`, `zig build test-mcp`,
`zig fmt --check build.zig src tests`.

### Stage 3: The Guard Lifts Only On A Closed Chain

Purpose: convert the measured subset, and nothing outside it.

Depends on: Stage 2 (Gate B).

Likely files:

- `src/frontends/java.zig`, `src/frontends/java_members.zig`,
  `src/frontends/java_hierarchy.zig`
- `src/claim_sample.zig` (reason families), tests

Required behavior:

- D4, D5, D6 and D8: `resolveType` and the receiver rule ask the projection
  whether the enclosing type's chain is closed and whether anything reachable
  declares the name. Closed and clean lifts the guard; anything else keeps
  today's answer and names the condition that failed.
- New unresolved reasons are added for each failure mode — supertype
  unresolved, provider stale, non-class supertype, cycle, depth cap, member type
  of the name found in a reachable type — and `claim_sample.zig` learns them so
  the families stay countable.
- D7: the class-grained aspect carries the declared supertype set, the reader
  hint covers every type a walk visited, and an edit to any of them reanalyzes
  the reader.
- The unqualified-invocation guard ([java.zig:1349](../../src/frontends/java.zig#L1349))
  is relaxed under the same test, because it declines for the same reason.

Branch handling:

- If the walk's cost makes analysis of the clone materially slower, cache the
  closedness answer per type for the duration of one analysis pass and record
  the measured before and after. Do not cache across analyses: a projection is
  re-read from the graph every time by design.
- If a converted claim turns out to depend on a member type this frontend does
  not record — an inherited field, a nested type inside an unindexed supertype —
  that is not a branch, it is a defect in D4's closedness test, and the stage
  does not ship until the test declines it.

Done when:

- The Follow-up 013 required tests all exist and pass: a fully indexed
  hierarchy resolves; an interface with no source keeps the unresolved answer; a
  member type of the name anywhere in the chain keeps it unresolved; a cycle
  keeps it unresolved and does not hang; adding a supertype anywhere in the
  chain reanalyzes the reader and removes a stale fact.
- The Plan 010 and ADR 008 boundary tests pass unchanged.
- A test proves no claim outside the guard family changed resolution.

Verification: `zig build test-core`, `zig build test`, `zig build test-mcp`,
`zig build dogfood`, `zig build preview-gate`,
`zig fmt --check build.zig src tests`.

### Stage 4: External Re-Measure Of The Supertype Half

Purpose: say what shipped, in the same numbers Stage 0 recorded, and price the
second half on the graph that now exists.

Depends on: Stage 3.

Likely files: the progress log, `docs/followups/013_java_supertype_guard_relaxation.md`

Required work:

- Re-run the Stage 0 measurement on the same clone at the same commit: the guard
  family before and after, converted claims by reason, facts created, and every
  family that did not move.
- Compare the realized count against Gate A's upper bound. If it is below half
  of it, the gap is explained in the log by naming the conditions that consumed
  it, not smoothed over.
- Re-measure ingestion time, memory, `semidx_context depth=2`, and the Plan 011
  work bounds. A latency regression that leaves the habit loop unusable is a
  stage failure, not a note.
- Measure Gate C on this graph and record the verdict.
- Close or re-price Follow-up 013 against what shipped.

Done when: the log holds a before/after table per family, the fan-out cost, the
latency numbers, the Gate C verdict, and Follow-up 013's updated status.

Verification: `zig build test-core`, `zig build test`, `zig build dogfood`,
`zig build preview-gate`.

### Stage 5: A Value Receiver With A Declared Type

Purpose: convert the second family, under rules Plan 012 already wrote.

Depends on: Gate C, measured in Stage 4 on the full path, or where an earlier
gate stopped the sequence.

Likely files:

- `src/frontends/java.zig`
- `docs/adr/012_java_value_receiver_calls.md`, `docs/adr/README.md`
- fixtures and tests

Required behavior:

- D9: each covered binding records the type its declaration writes; every
  uncovered introducer keeps poisoning the name; declaration-order visibility is
  unchanged.
- D10: a value-receiver call becomes a `CALLS` fact only when every condition
  holds at once, including the closed-chain test from Stage 3 for a target type
  that declares supertypes.
- Every failure keeps a distinct reason: uncovered introducer, uncovered type
  shape, receiver type unresolved, out-of-scope target, overloads, access,
  nested class body, target chain open, name declared in a reachable supertype.
- Write ADR 012 recording D9, D10 and D11, answering every §11 question, and
  stating why `super.m()` and inherited targets remain out.

Branch handling:

- If Gate C passed only marginally and Stage 5's own fixtures show the
  addressable subset is thinner than measured, stop and record rather than
  loosen a condition to reach the number. Loosening a condition to hit a
  forecast is the failure mode this plan's gates exist to prevent.

Done when:

- The Follow-up 014 required tests all exist and pass, including every
  binding-introducer poison case, before-declaration use, and provider edits
  reanalyzing the caller.
- A test proves `this.m()` resolves and `super.m()` does not.
- A re-measure on the clone records facts created, families that moved, and
  families that did not.

Verification: `zig build test-core`, `zig build test`, `zig build test-mcp`,
`zig build dogfood`, `zig build preview-gate`,
`zig fmt --check build.zig src tests`.

### Stage 6: Documentation And Closure

Purpose: leave the canon saying what is true, and leave the next step named.

Depends on: whichever stage the gates ended at.

Likely files:

- `docs/spec/capability_matrix.md`, `docs/mcp/local_preview.md`,
  `MEMORY.md`, `docs/design/001_project_roadmap.md`, `GLOSSARY.md`
- `docs/followups/013_java_supertype_guard_relaxation.md`, `docs/followups/014_java_instance_receiver_calls.md`,
  `docs/followups/README.md`, this plan, the progress log

Required work:

- State the Java coverage that now exists: interfaces as definitions, supertypes
  as claims, and whichever relaxations shipped. The capability matrix and the
  preview reference are the owners; neither may keep describing Java coverage as
  classes and their methods.
- Update `MEMORY.md` within its 350-line bound, compressing rather than
  appending, and update the roadmap's near-term direction, which currently names
  this work as the next priority.
- Set Follow-up 013 and Follow-up 014 to their true status — `fixed`,
  `wont_fix`, or `open` with new numbers — and link the resolving stage.
- Record any new deferred finding as a follow-up numbered from 020.
- Run drift control over every owner in Sources Of Truth and record the result.
- Mark this plan and its progress log historical, and record in the log that the
  next preview release is the following step and is not part of this plan.

Done when: every owner above agrees with the shipped behavior, no document
describes a coverage claim this plan did not deliver, and the follow-ups'
statuses match the code.

Verification: `./scripts/check-zig-version.sh`,
`zig fmt --check build.zig src tests`, `zig build test-core`, `zig build test`,
`zig build test-mcp`, `zig build dogfood`, `zig build preview-gate`.

## Risk Matrix

| Guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative case | Evidence |
| --- | --- | --- | --- | --- | --- |
| A relaxed name is still a fact | The chain looks closed while a supertype hides a member of the name | Frontend fixtures plus external re-measure | Every link a current fact inside the ADR 008 boundary, every reachable type checked for the name | A member type anywhere in the chain keeps the name unresolved | Stages 2-4 |
| The walk terminates | A declared cycle or a deep chain hangs analysis | Frontend fixture | Visited set plus depth cap of 16 | A cycle yields an unresolved claim, not a hang | Stage 3 |
| Incrementality survives the fan-out | A supertype edit leaves a stale fact in a reader that walked the chain | Core plus incremental test | Reader hinted for every type visited; class aspect carries the supertype set | Adding a supertype removes a stale fact from the reader | Stage 3 |
| Reasons stay distinguishable | A widened rule collapses six declines into one | Claim-family counters | Each failure mode has its own explanation and family | A family that disappears without conversion fails the stage | Stages 3 and 5 |
| Interfaces do not widen anything else | Admitting interfaces silently moves unrelated resolutions | Fixture corpus counts | Every moved claim counted and one pinned by fixture | An enum, record, or annotation type still raises its diagnostic | Stage 1 |
| The habit loop stays usable | More definitions and claims make queries slow | External latency measure plus Plan 011 work bounds | `semidx_context depth=2` stays interactive; bounds unchanged | A regression that makes the loop abandonable fails Stage 4 | Stage 4 |
| The gates are honest | An estimate is built to justify the plan that commissioned it | Recorded procedure plus real re-measure | Upper bound labelled as such; realized count compared to it | A realized count below half the upper bound is explained by named conditions | Stages 0 and 4 |
| No name match enters | A closed chain becomes an excuse to match names | Review against ADR 003 | The chain rules out; a target is still selected by existing rules | An inherited method is never selected | Stages 3 and 5 |

## Definition Of Done

- Java interface declarations and their methods are definitions, with implicit
  modifiers recorded as Java defines them, and no other type declaration was
  admitted.
- Every declared supertype is a recorded claim, resolved in the declaring unit's
  scope, and an open chain is visible as an unresolved supertype rather than as
  an absence.
- The supertype guard lifts only where a chain is closed under D4 and nothing
  reachable declares the name, on both the reference and the receiver side, with
  every failure naming its condition.
- A reader that walked a chain is reanalyzed when any type in it changes, proven
  by an incremental test.
- If Gate C passed: a value-receiver call is a `CALLS` fact exactly under D10,
  with `this.m()` admitted and `super.m()` declined.
- Every gate verdict is recorded with the number that produced it, and any gate
  that failed ended its stage sequence rather than being argued past.
- Facts, resolutions, explanations, producers, freshness, and entity identity
  are provably unchanged for every family this plan did not name.
- The clone measurement is reproducible from the recorded clone, commit, seed,
  and documented procedure.
- Follow-ups 013 and 014 hold their true status, the capability matrix, preview
  reference, `MEMORY.md`, `GLOSSARY.md`, and the roadmap agree with what
  shipped, and no release or version bump was made.
