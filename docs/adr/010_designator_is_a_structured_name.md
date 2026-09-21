---
title: "Record a designator as a structured name"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-20"
---

# 010: Record A Designator As A Structured Name

## Feature Or Dependency

`model.Target.designator` is the target of every unresolved relationship the
graph holds. The model defines it as "a name read from source that the producer
could not resolve to an entity", and two of the three frontends did not store a
name in it:

| Frontend | What it stored |
| --- | --- |
| Java invocation | the whole invocation text for a qualified call — `config.load(secret, 42)` |
| Java type reference | the type text as written |
| Zig call | the callee path — `std.debug.print`, `self.bucket` |
| Clojure symbol | the symbol text — `str/join` |

This record decides what that field holds. It is the first stage of
[Plan 013](../plans/013_unresolved_mentions_from_the_callee_anchor.md), whose
purpose is that a recorded claim be reachable from the entity that was named,
and it closes the defect
[Follow-up 019](../followups/019_designator_may_carry_source_expression.md)
records.

## Evidence

[Plan 013 Stage 0](../reports/013_unresolved_mentions_from_the_callee_anchor_progress.md#stage-0-reproducible-baseline),
measured on apache/dubbo at `df9c5e1`, 4,050 Java source units, 26,509
definitions, whole graph rather than a sample:

| Measurement | Count |
| --- | ---: |
| Unresolved calls | 118,471 |
| Of those, designator is not a name but invocation text | **99,103** (83.6%) |
| Unresolved type references | 19,751 |
| Of those, designator is not a simple name | 4,200 |
| Distinct designator keys in the index | 57,068 |
| Of those keys, expression text rather than a name | **53,483** (93.7%) |

The index that exists to group claims by name grouped almost nothing: 138,222
claims over 57,068 keys, 2.4 claims to a key, because a key was very nearly a
call site. `semidx_references name=bucket direction=incoming` on this repository
returned zero while three located, explained claims named `bucket`.

## Decision

**D1 — A designator is a name in parts.** `model.Designator` carries the
identifier that names the thing and, where the source wrote a name in front of
it that the frontend knows to name a **scope**, that name as a separate
`qualifier` field. Per frontend:

| Frontend | `name` | `qualifier` |
| --- | --- | --- |
| Java invocation | the invocation's `name` field | the class, where this frontend established the receiver as a class and then declined to select a method of it; absent for a receiver it reads as a value or does not read at all |
| Zig call | the last identifier of the callee | the path in front of it, only when that path is rooted in a top-level `@import` alias nothing in scope shadows; absent for a call through a value |
| Clojure symbol | the part after `/` | the part before it, which is a namespace or a namespace alias |
| Java type reference | the type name as written | never — see D2 |

The frontends apply one rule, not four: record a qualifier only where the
frontend knows the prefix names a scope, and never where it is a value
expression. Only a frontend can tell those apart, which is why this is the
frontends' decision and not the index's or a tool's.

`name` is the match key: `DesignatorAdjacency` buckets on it. A producer that
could read no identifier at all — a computed callee — records an empty name, and
an empty key is not bucketed: nothing finds the claim by name, which is the
answer rather than a name synthesized from the text. An absent qualifier is
absent, never an empty string.

**D2 — Java type references stay as they are.** A type reference's designator is
already a name in the dominant case; the exceptions are generic and qualified
type syntax — `List<String>`, `java.util.List` — which is a separate decision
with its own evidence. Mixing it in would make this stage's before and after
unreadable. The 4,200 measured above are the input that decision will start
from.

**D3 — The written form is fed to the evidence explicitly.** All three frontends
handed one string to both the target and `evidenceOf`, so changing what the
designator holds would have silently rewritten the evidence with it. Each call
site now passes the text the source wrote — the whole invocation for Java, the
callee for Zig, the symbol for Clojure — so the name is in the graph and the
text is in `SourceEvidence.text`, with the range that locates it.

## Rationale

**The field was under-determined, and the query is not who should settle it.**
The model promised a name; Java stored an expression; Zig and Clojure stored
qualified names the field did not say how to hold. An under-determined field
gets settled by whoever reads it first, and the first reader here would have
been a designator-anchored query — a consumer deciding what a producer meant,
which §7 forbids. D1 settles it where the knowledge is: the frontend that parsed
the source.

**Nothing is discarded, which is what makes it reversible in one direction
only.** The rejected alternative is the obvious one: store the last segment and
keep the written form in evidence text. It is smaller, and it is wrong three
times over. It would hide language-specific naming behind an opt-in flag, making
a qualified name reachable only to a consumer that asked for source text; it
would leave the qualifier derivable only by splitting a string, which is the
frontend's knowledge re-derived by someone without it; and it is irreversible,
because a segment cannot be re-qualified later. Recording both parts can always
be flattened; flattening cannot be undone.

**The window is now.** There is no persistence, no published contract, and
`semantic_contract_version` is still `null`. A field that gains structure now
costs one interning site and one rendering site. The same change after a
contract exists is a breaking change with a migration.

**ADR 003 is untouched.** [ADR 003](003_reject_name_match_assertions.md) rejects
repository-wide name matching as graph authority. Nothing here establishes a
relationship: an unresolved claim stays unresolved, keeps its `missing` part, its
explanation, its producer and its freshness, and names no entity. What changes is
what the claim says the thing it could not resolve is *called*. A later stage may
render claims that share a name beside a definition of that name; that rendering
will carry each claim's own unresolved category and will not be a relationship
to the anchor.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Preserved. No claim is created,
   converted, or resolved. The same 138,222 unresolved assertions exist, from the
   same producers, with the same resolutions and explanations, and the fixture
   corpus records the same 396 facts before and after, proven by a test.
2. **Nodes as entities, not chunks.** Preserved, and strengthened in the
   direction §2 cares about. A designator was a run of source text selected by
   where an expression started and ended; it is now a name. An unresolved target
   still never becomes a node.
3. **Facts, unresolved and approximate stay distinct.** Preserved. Resolution
   categories, `missing` parts, explanations, producers and freshness are
   untouched. No assertion changed category in either direction; a test over the
   fixture corpus pins the counts, and the external re-measure repeats it.
4. **Stable semantic identity.** Preserved. Entity identity is not derived from
   assertion content: this changes what an assertion says, and the ids of the
   entities it connects are allocated by the graph and unaffected. Assertion
   content ids move once, on the first rescan after this change, which is content
   changing rather than identity — and it is a one-time move, not churn.
5. **Incrementality and consistent observation.** Preserved. Dependency
   declarations, invalidation channels, and propagation rules are untouched: no
   frontend reads anything new about another unit to decide a designator, so
   nothing new can go stale. A query still reads one published snapshot, and
   every pass of a tool reads the same one.
6. **Language frontends preserve meaning.** This is the clause the decision
   serves. A qualified name stays qualified, in the parts the language writes it
   in, instead of being flattened into one string that only that language's
   reader could split. Each frontend decides what a scope is in its own language;
   the core stores the fields it is given and never parses, splits, or normalizes
   them.
7. **Consumers do not define the model.** Preserved. The MCP preview renders the
   two fields and decides nothing: it does not split a designator, does not infer
   a qualifier, and no part of D1 was chosen because a query could compare it.
   The rendering change — `"designator": {"name": …, "qualifier": …}` — follows
   the model rather than shaping it, and the preview is not a published contract.
8. **Local operation without mandatory source-data transmission.** Preserved,
   and the consent boundary tightens. A designator renders with no opt-in while
   evidence text is gated; before this change a Java designator carried receiver
   and argument text into default output, against `src/mcp/tools.zig`'s own
   header claim that `SourceEvidence.text` is the only source-text field a
   snapshot carries. Default output now carries names and qualifiers only, and an
   MCP test proves a receiver expression reaches a result only under
   `--allow-evidence-text`.

## Consequences

- Every unresolved relationship target in every frontend changes shape. The
  designator index keys on `designator.name`, so claims naming one method from
  many call sites now share one bucket. On the fixture corpus the distinct key
  count fell from 20 to 16 with the same 74 claims; the external re-measure is
  [Plan 013 Stage 4](../plans/013_unresolved_mentions_from_the_callee_anchor.md).
- Evidence text now holds the whole Java invocation for unqualified calls too,
  where it previously repeated the method name. It stays behind
  `--allow-evidence-text` and within the existing byte bound.
- Assertion content ids move once on the first rescan after this change, because
  the content changed. Entity ids do not.
- Tests that asserted a designator that was an expression assert a name now.
  Every such move is recorded in the Plan 013 progress log; no test that asserts
  a *resolution* moved.
- A computed callee records an empty name and is not in the designator index.
  It remains in the assertion array with its evidence, reachable from its source
  entity like any other claim.

## What This Record Does Not Enable

- No resolution. No unresolved claim becomes a fact, no guard is relaxed, no
  receiver is typed, no hierarchy is walked.
  [Follow-up 013](../followups/013_java_supertype_guard_relaxation.md) and
  [Follow-up 014](../followups/014_java_instance_receiver_calls.md) stay
  deferred and untouched.
- No name matching becomes graph authority. ADR 003 stands as written.
- No normalization: no case folding, no substring matching, no cross-language
  matching, and no splitting of a designator anywhere outside the frontend that
  recorded it.
- No core kind, no published contract, no persistence, and no version bump.
  `semantic_contract_version` stays `null`.
- Java generic and qualified type syntax is not normalized (D2).

## Verification Evidence And Planned Checks

- Frontend tests, one per language, pin both fields and the evidence: a Java
  instance receiver records no qualifier and keeps `helper.describe(1, 2)` as
  evidence; a Java class-qualified call whose method choice failed records the
  class as its qualifier; `std.debug.print` records `print` qualified by
  `std.debug` while `self.bucket` records `bucket` alone; `str/join` records
  `join` qualified by `str`.
- A test proves two call sites naming one method share one designator key.
- A test over the fixture corpus pins definitions, assertions, facts,
  unresolved, approximate and diagnostics against the values measured on the
  commit before this change.
- An MCP test proves a default answer carries the name and no receiver or
  argument text, and that the expression reaches a result only under
  `--allow-evidence-text`.
- `zig build test-core`, `zig build test`, `zig build test-mcp`,
  `zig build dogfood`, `zig build preview-gate`, and
  `zig fmt --check build.zig src tests` all pass.
