---
title: "Unresolved mentions from the callee anchor"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "reference_for_context"
updated: "2026-09-20"
---

# 013: Unresolved Mentions From The Callee Anchor

## Goal

Make the impact question answerable on real code: when semidx cannot resolve a
call or reference, the claim it did record must still be reachable **from the
entity that was named**, not only from the caller that wrote it.

Two measurements define the gap.

On apache/dubbo at `df9c5e1` the graph holds 230,753 assertions: 90,439 facts
and 140,314 unresolved. Of those, **118,349 are unresolved calls**, against
2,214 static-call facts and 336 cross-unit reference facts across 26,509
definitions ([Plan 012 progress](../reports/012_java_semantic_quality_without_query_regression_progress.md)).
Every one of the 118,349 is a recorded claim with a location and a stated
reason, and none of them can be found by asking about the definition it names.

On this repository, today:

```
semidx_references name=bucket direction=incoming  →  relationships: 0
```

while [`src/core/graph.zig`](../../src/core/graph.zig#L1483-L1498) calls
`bucket` three times. The answer is not wrong — no fact exists — but it is
empty where the graph is holding three located, explained claims.

This plan changes what a designator **is** and what the reference tool **shows**.
It creates no fact, resolves no name, and relaxes no resolution rule.

## Product Principle

When a stage offers a choice, decide in this order:

1. **A mention is never a relationship.** Nothing this plan adds may read as
   "these call the anchor". The anchor is a name; the claim stays unresolved,
   carries its own reason, and says so in the same field it always has.
2. **The graph answers, the projection arranges.** Every mention rendered is an
   assertion already in the snapshot. No new assertion, no ranking, no score,
   no similarity, no case folding, no substring match.
3. **Exact byte equality or nothing.** A mention is admitted only when the
   producer's own designator equals the anchor name exactly.
4. **Bounded like everything else.** Mentions live inside the Plan 009 budget,
   limit, and narrowing-hint machinery, and inspect only their own index
   bucket.

## Start Rule

Read before starting:

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md) §1, §3,
  §6, §7, §11
- [ADR 003](../adr/003_reject_name_match_assertions.md), which this plan must
  not weaken
- [Plan 012 progress](../reports/012_java_semantic_quality_without_query_regression_progress.md),
  for the counts this plan is built on
- [Follow-up 017](../followups/017_plan_012_external_evidence_reproducibility.md),
  which Stage 0 closes
- `src/core/model.zig`: `Target`, `SourceEvidence`
- `src/core/graph.zig`: `RelationshipFilter`, `candidatesFor`,
  `RelationshipIterator`
- `src/core/relationship_index.zig`: `DesignatorAdjacency`
- `src/frontends/java.zig`: `emitInvocation`; `src/frontends/zig.zig`:
  `emitCall`; `src/frontends/clojure.zig`: `emitDesignation`
- `src/mcp/tools.zig`: `references`

Create `docs/reports/013_unresolved_mentions_from_the_callee_anchor_progress.md`
with standard progress-log frontmatter before the first code change.

Stop and re-open this plan if Stage 0 finds that the dominant unresolved
families already key on a bare name. The stage order assumes they do not; that
assumption is checked first and recorded.

## Scope

- Make every unresolved relationship target a **name**, in every frontend,
  with the written form kept as evidence.
- Record that decision as an ADR.
- Prove the designator-anchored query inspects only its own bucket.
- Add an `unresolved_mentions` section to `semidx_references`, with its own
  limit, budget participation, and narrowing hints.
- Re-measure on apache/dubbo and record what the callee anchor now reaches.
- Update the documents that own designator meaning, preview behavior, and
  vocabulary on closure.

## Non-Scope

Do not resolve anything. No new fact, no relaxed guard, no receiver typing, no
hierarchy walking. [Follow-up 013](../followups/013_java_supertype_guard_relaxation.md)
and [Follow-up 014](../followups/014_java_instance_receiver_calls.md) stay
deferred and are not partially implemented here.

Do not rank, score, sort by likelihood, fold case, match substrings, or match
across languages. A mention is an exact byte match on the producer's designator
within the anchor's language.

Do not change `semidx_context`, traversal, cursors, or any existing tool's
result fields. `unresolved_mentions` is additive.

Do not change resolution categories, explanations, freshness, producers, or
identity. Do not touch dependency invalidation rules.

Do not add persistence, watching, HTTP, a daemon, or a release. No product
version bump in this plan.

Do not return source text by default. The written form of a mention is evidence
text and stays behind `--allow-evidence-text`.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md): §1 —
  "A text-derived or approximate mechanism may discover candidates, rank them,
  and render located source; it must never establish a program relationship";
  §3 exactness; §6 distinguishable coverage; §7 consumers do not define the
  model; §11 the decision test.
- [ADR 003](../adr/003_reject_name_match_assertions.md): a name match is not
  graph authority.
- [MEMORY.md](../../MEMORY.md): current runtime reality.
- [docs/mcp/local_preview.md](../mcp/local_preview.md): the preview's own
  description of designators and tool results.
- [Documentation policy](../agent-policy/documentation.md): ADR procedure,
  drift control, glossary ownership.
- [Testing policy](../agent-policy/testing.md).

**Drift control at readiness.** The owners above were checked and are aligned
with this plan as written: no core kind is added, no contract is published,
`semantic_contract_version` stays `null`, and no language coverage claim
changes. Two documents will contradict the result once it lands and are
therefore closure targets, not readiness blockers:
[docs/mcp/local_preview.md](../mcp/local_preview.md), which currently describes
a designator as "callee names as written", and
[GLOSSARY.md](../../GLOSSARY.md), which does not yet own the term
*unresolved mention*.

## Current Evidence

**The designator is not a name today, and the model says it should be.**
`model.Target.designator` is documented as "a name read from source that the
producer could not resolve to an entity"
([model.zig:136-137](../../src/core/model.zig#L136-L137)). What the Java
frontend stores for a qualified invocation is the whole invocation text:

```zig
const designator = if (receiver != null) try builder.dupe(node.text(source)) else name;
```

([java.zig:1269](../../src/frontends/java.zig#L1269)). `foo.bar(a, b)` is an
expression, not a name. The Zig frontend stores the callee path
([zig.zig:802](../../src/frontends/zig.zig#L802)), so `std.debug.print` and
`self.bucket` are stored whole. The Clojure frontend stores the symbol text
([clojure.zig:448](../../src/frontends/clojure.zig#L448)), so `str/join` is
stored whole.

The consequence is a key space, not a vocabulary: on Java the designator is
close to unique per call site, so the index that exists to group claims by name
groups almost nothing.

**The index and the query path already exist.** `DesignatorAdjacency`
([relationship_index.zig:57-80](../../src/core/relationship_index.zig#L57-L80))
buckets assertion positions by designator, and `candidatesFor` already answers a
designator-anchored query from it
([graph.zig:1498](../../src/core/graph.zig#L1498)), with `reference_query`,
`resolution`, and `freshness` as post-filters
([graph.zig:1427-1455](../../src/core/graph.zig#L1427-L1455)). Plan 011 built
this; nothing about it needs redesign.

**The MCP surface never asks it.** `semidx_references` runs exactly two passes
per target, both anchored on the target entity id
([tools.zig:1653-1671](../../src/mcp/tools.zig#L1653-L1671)). An unresolved
claim has a designator target, so the incoming pass skips it by construction
([graph.zig:1442-1447](../../src/core/graph.zig#L1442-L1447)). That is why
`bucket` reports zero.

**Why this and not more Java resolution.** The two open Java coverage
follow-ups were priced on the same clone: relaxing the supertype guard converts
13 of 335 measured cases safely, and the instance-receiver type environment
addresses 63. This plan does not convert anything — it makes 118,349 already
recorded calls reachable from the name they wrote, with each one's own reason
attached. The cost is one field's meaning and one result section.

## Architecture Decisions

These are decisions, not open questions. An executing agent applies them.

**D1 — A designator is a name.** Every frontend stores, as the designator, the
identifier the source wrote for the thing it could not resolve:

| Frontend | Today | After |
| --- | --- | --- |
| Java invocation | full invocation text for a qualified call | the invocation's `name` field, for every call |
| Java type reference | the type text as written | unchanged in this plan (see D2) |
| Zig call | the callee text (`std.debug.print`) | the last identifier of the callee path (`print`) |
| Clojure symbol | the symbol text (`str/join`) | the name segment (`join`) |

The written form is not lost: it stays in `SourceEvidence.text`, which every one
of these relationships already carries
([model.zig:68-73](../../src/core/model.zig#L68-L73)), together with the range
that locates it.

**D2 — Java type references are out of D1's rewrite.** A type reference's
designator is already a name in the dominant case; the exceptions are generic
and qualified type syntax. Normalizing those is a separate decision with its own
evidence, and mixing it in would make Stage 1's before/after unreadable. Record
what Stage 0 measures about them and leave them as they are.

**D3 — This is a graph correctness fix, not an MCP convenience.** D1 is
justified by `model.Target`'s own definition, independent of any consumer. §7 is
satisfied because the MCP capability falls out of the fix; the fix is not shaped
by the tool.

**D4 — A mention is rendered, never asserted.** `unresolved_mentions` items are
assertions read from the snapshot, each keeping its `resolution` category,
`missing`, `explanation`, `producer`, `freshness`, and `evidence`. Nothing is
created, nothing is converted, and the item names no target entity. This is §1's
permitted rendering and ADR 003 is untouched: no name match becomes a
relationship.

**D5 — Exact, language-scoped matching.** A mention is admitted when the
assertion's designator equals the anchor definition's name byte for byte **and**
the assertion's source entity has the anchor's language. Cross-language mentions
are out of scope; record the decision where the limit is documented.

**D6 — Mentions are their own section with their own limit.** They are not
merged into `relationships`, not counted in `relationships_total`, and not
reachable by the existing cursor. They carry `unresolved_mentions_total`,
`unresolved_mentions_truncated`, and participate in `max_response_bytes` like
every other list. `mention_limit` defaults to 50 (max 500), declared in
`src/mcp/tools.zig` so the advertised schema and the validator derive from it.

**D7 — `detail` governs mentions too.** `compact` gives the caller entity by
id with its name, role and location, the designator, the resolution category
with its explanation, and freshness. `full` adds producer version, revision,
and the full entity rendering, consistent with every other list.

**D8 — The walk is bucket-bounded and honest about it.** A mention query
inspects its own designator bucket and nothing else. `unresolved_mentions_total`
is the exact count over that bucket after post-filters. If Stage 4 measures a
hot name whose bucket makes the call non-interactive, record the number and open
a follow-up; do not invent an approximate count.

**D9 — Zero mentions is a result, not a gap.** When the bucket is empty the
section is present and empty. An absent section would be read as "not
supported".

## Architecture Boundaries

1. **Frontends** own what a designator says, because only they know the
   language's naming. They do not know about the index or the tool.
2. **Core graph** indexes and returns the string it was given. It never parses,
   splits, or normalizes a designator.
3. **MCP preview** anchors, bounds, and renders. It never decides what matches;
   byte equality and the language check are the whole rule.
4. **Tests and gates** prove the designator contract per language, the bucket
   bound, and that no fact moved.

## Implementation Stages

### Stage 0: Reproducible Baseline

Purpose: make every later claim comparable to a number recorded first, and close
the process defect that makes Plan 012's numbers unverifiable.

Likely files:

- `docs/reports/013_unresolved_mentions_from_the_callee_anchor_progress.md`
- `docs/followups/017_plan_012_external_evidence_reproducibility.md`

Required work:

- Run `./scripts/check-zig-version.sh`; record commit and worktree state.
- Clone apache/dubbo at `df9c5e1` outside the repository. Record the clone path
  and commit in the progress log.
- Run `zig build claim-sample` with a recorded seed and record: total
  assertions, facts, unresolved, unresolved calls by family, and the per-family
  counts Plan 012 published, so the two are comparable. This is the baseline
  [Follow-up 017](../followups/017_plan_012_external_evidence_reproducibility.md)
  asks for.
- Record the designator index shape: number of distinct designator keys, total
  bucketed positions, the twenty largest buckets with their sizes, and
  `DesignatorAdjacency.byteSize`.
- Record, for five widely referenced Dubbo definitions chosen and named in the
  log, the current `semidx_references direction=incoming` result.
- Record how many Java type-reference designators are not simple names, as
  D2's input.

Done when:

- The progress log names this plan, the clone, the commit, the seed, and every
  number above.
- Follow-up 017 is updated with the reproduced baseline, or states precisely
  which of Plan 012's numbers remain unreproducible and why.

Verification: `./scripts/check-zig-version.sh`, `zig build test-core`.

### Stage 1: A Designator Is A Name

Purpose: make the graph store what its own model says it stores.

Likely files:

- `src/frontends/java.zig`, `src/frontends/zig.zig`,
  `src/frontends/clojure.zig`
- `docs/adr/010_designator_is_a_name.md`
- fixtures and tests under `tests/`

Required behavior:

- Apply D1 per frontend. The written form moves to `evidence.text`; the range
  is unchanged.
- No resolution, explanation, producer, freshness, or dependency changes. A
  claim that was unresolved stays unresolved for the same stated reason.
- Write ADR 010 recording D1, D2, and D3, answering every §11 question, and
  stating explicitly that ADR 003 is unaffected because no designator becomes a
  target.

Branch handling:

- If a callee path's last identifier is empty or absent (a computed callee, a
  parse error region), keep the claim unresolved and skip the mention key
  rather than storing a synthetic name.
- If a test asserts a designator that was an expression, it is the assertion
  that moves, and the progress log records each one. If a test asserts a
  *resolution* that moves, that is a defect in this stage.

Done when:

- A fixture test per language proves the designator is the name and the
  evidence text is the written form: Java `foo.bar(a, b)` → `bar`, Zig
  `std.debug.print(...)` → `print`, Clojure `str/join` → `join`.
- A test proves two different call sites naming the same method share one
  designator key.
- Fact counts over the fixture corpus are unchanged, proven by a test, not by
  eye.
- ADR 010 is committed and linked from the commit message.

Verification: `zig build test-core`, `zig build test`,
`zig fmt --check build.zig src tests`.

### Stage 2: The Bucket Is The Whole Walk

Purpose: prove the anchored query is bounded before a tool depends on it.

Likely files:

- `src/core/graph.zig` or a core test file

Required behavior:

- A designator-anchored query inspects exactly the positions in its bucket.
  Existing post-filters stay post-filters.
- No signature, ordering, or result change. If ordering moves, the index build
  walked out of assertion order.

Done when:

- A work-bound core test, in the style of Plan 011's, fails if a designator
  query ever walks the assertion array.
- A test proves an absent designator returns empty without a scan.
- The progress log records the index key count and byte size after Stage 1
  against Stage 0's, with the change explained rather than assumed.

Verification: `zig build test-core`, `zig build test`,
`zig fmt --check build.zig src tests`.

### Stage 3: `unresolved_mentions` In `semidx_references`

Purpose: deliver the answer at the anchor a user already asks from.

Likely files:

- `src/mcp/tools.zig`, `src/mcp/root.zig`, MCP tests

Required behavior:

- Declare `mention_limit` in the tool's argument table per D6, so the
  advertised schema and the validator derive from it.
- For each shown target, run a third pass filtered by
  `.{ .designator = <target name>, .reference_query = true, .freshness = … }`,
  admitting an assertion only when D5 holds and the existing `resolution`
  argument admits it.
- Emit `unresolved_mentions`, `unresolved_mentions_total`, and
  `unresolved_mentions_truncated` per D6, rendered per D7, present-and-empty
  per D9.
- Participate in `max_response_bytes` and `budget` exactly as the other lists
  do, and add a narrowing hint when the section is cut.
- A mention that is also an incoming relationship cannot exist — an assertion
  has one target — but the `seen` set must still treat the two sections
  independently, so nothing is silently dropped.

Branch handling:

- If the anchor resolves to more than `max_targets` definitions, mentions
  follow the same shown-targets rule as relationships, and the existing
  narrowing hint covers it.
- If a name's bucket is very large, the limit and budget cut it and the hint
  says so. Do not sample.

Done when:

- On this repository, `semidx_references name=bucket direction=incoming`
  returns the three `.bucket(` call sites as unresolved mentions, each with its
  caller, location, and recorded reason, and still returns zero relationships.
  This exact check is the plan's own falsifiable demonstration.
- An MCP test proves a mention carries its resolution category, explanation,
  producer, and freshness, and names no target entity.
- An MCP test proves `resolution=fact` returns an empty mention section, and
  that a cross-language same-name designator is not admitted.
- Budget, limit, truncation, and hint behavior are covered by tests in the
  Plan 009 style.

Verification: `zig build test-core`, `zig build test`, `zig build test-mcp`,
`zig build dogfood`, `zig fmt --check build.zig src tests`.

### Stage 4: External Re-Measure

Purpose: state what the change bought, in the same terms as the gap.

Likely files:

- the progress log

Required work:

- On the Stage 0 clone at the same commit, record for the same five
  definitions: relationships before and after, mentions now returned, and the
  distribution of their recorded reasons.
- Record whole-graph numbers: distinct designator keys, bucketed positions,
  index byte size, and how many of the 118,349 unresolved calls are now
  reachable from a definition's name.
- Record wall-clock for `semidx_references` on the five definitions and on the
  largest bucket found in Stage 0, and the inspected-work count for each.
- Record that facts, resolutions, and diagnostics are unchanged against the
  Stage 0 baseline; any delta is a defect in Stage 1, not a result.

Done when:

- The progress log carries before/after for every number above, and names any
  number it could not obtain.
- If the largest bucket's latency is not interactive, a follow-up is opened
  with the measurement rather than the plan quietly accepting it.

Verification: the commands named in the log, recorded with their results.

### Stage 5: Documentation And Closure

Likely files:

- `docs/mcp/local_preview.md`, `GLOSSARY.md`, `MEMORY.md`,
  `docs/design/001_project_roadmap.md`, `docs/spec/capability_matrix.md`,
  the progress log, `docs/followups/README.md`, this plan

Required behavior:

- `docs/mcp/local_preview.md`: a designator is the name the producer could not
  resolve; the written form is evidence text under `--allow-evidence-text`;
  `unresolved_mentions` is documented with its limit, budget, exactness, and
  language scoping, and with the sentence that a mention is a name match over
  unresolved claims and not a relationship to the anchor.
- `GLOSSARY.md` owns *unresolved mention*.
- `MEMORY.md` states, as current reality and not as history, that designators
  are names and that `semidx_references` answers with facts plus mentions.
- `docs/design/001_project_roadmap.md`: refresh Current Position and Near-Term
  Direction, which still name Plan 011 as the next priority although Plans 011
  and 012 are executed.
- `docs/spec/capability_matrix.md`: update only if a per-language statement
  becomes inaccurate under D1.
- Follow-up 017 closed or narrowed by Stage 0's baseline; Follow-ups 013 and
  014 left open and explicitly unaffected.

Done when plan status, follow-up statuses, `MEMORY.md`, the preview reference,
and the progress log agree, and no document still calls a designator the text as
written.

Verification: `./scripts/check-zig-version.sh`,
`zig fmt --check build.zig src tests`, `zig build test-core`, `zig build test`,
`zig build test-mcp`, `zig build dogfood`, `zig build preview-gate`.

## Risk Matrix

| Guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative case | Evidence |
| --- | --- | --- | --- | --- | --- |
| A mention is not a relationship | An agent reads mentions as callers | MCP integration | Separate section, own totals, unresolved category and explanation on every item, no target entity | `resolution=fact` yields an empty section | Stage 3 |
| No fact moved | Renaming designators changes resolution | Frontend fixtures plus external diff | Fact counts identical over fixtures and the Dubbo clone | A resolution delta fails the stage | Stages 1 and 4 |
| Written form preserved | The source form is lost with the expression text | Frontend fixture | Evidence text carries the written form with its range | Evidence text missing on a rewritten designator | Stage 1 |
| Consent boundary intact | Expression text starts leaving by default | MCP test | Default results carry names, not written forms | Written form present without `--allow-evidence-text` | Stage 3 |
| Query stays bounded | A hot name scans the assertion array | Core work bound | Inspected work equals bucket size | Absent designator returns empty without a scan | Stage 2 |
| Exactness of matching | Fuzzy or cross-language matches creep in | MCP test | Byte equality plus anchor language | Same name in another language not admitted | Stage 3 |
| Budgets unchanged | The new section breaks pagination or budgets | MCP test | Existing cursor, limit, and budget behavior unchanged | Section cut yields a narrowing hint | Stage 3 |
| Reconcile churn understood | One-time assertion content change read as instability | Core and dogfood | Content ids change once, identity does not | Entity ids preserved across the first rescan | Stages 1 and 4 |
| Evidence reproducible | A second unverifiable external claim | Recorded seed and commit | Baseline reproduced from seed alone | A number that cannot be re-derived is named as such | Stages 0 and 4 |

## Definition Of Done

- Every unresolved relationship target is a name, per D1, in all three
  frontends, with the written form in evidence.
- ADR 010 records the decision and answers the §11 test.
- `semidx_references` returns `unresolved_mentions` bounded per D6, rendered
  per D7, present-and-empty per D9, and exact per D5.
- `semidx_references name=bucket direction=incoming` on this repository returns
  the three recorded `bucket` call sites as mentions and zero relationships.
- A work-bound test proves a designator query inspects only its bucket.
- Facts, resolutions, explanations, producers, freshness, and entity identity
  are provably unchanged on fixtures and on the Dubbo clone.
- Stage 0 and Stage 4 numbers are recorded from a named clone, commit, and
  seed, and Follow-up 017 is closed or narrowed against them.
- The preview reference, `GLOSSARY.md`, `MEMORY.md`, and the roadmap agree with
  the shipped behavior, and no release or version bump was made.
