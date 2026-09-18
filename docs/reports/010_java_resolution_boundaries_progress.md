---
title: "Java resolution boundaries progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-18"
---

# 010: Java Resolution Boundaries Progress

Companion log for
[docs/plans/010_java_resolution_boundaries.md](../plans/010_java_resolution_boundaries.md).

## Current Status

Stage 1 is complete and its verdict is **go**, with one correction to the plan's
premise that later stages must carry: the false fact Stage 3 exists to remove is
latent, not active. It is reproducible in two directories but occurs zero times
in a 119-module, 4,050-unit external Java repository. Stage 4's execution
condition is met. Details and evidence are in
[Stage 1](#stage-1-external-java-evidence-probe).

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: External Java evidence probe | Completed | Apache Dubbo at `df9c5e1`: 4,050 units in 17.5 s, 290 MB; orientation and refresh useful, reference and neighborhood answers thin; cross-module false facts **0 of 336** cross-unit reference facts; single-type imports are 28% of in-working-copy unresolved references, so Stage 4 executes. Verdict: go. |
| Stage 2: Boundary representation decision | Not started | Depends on the direction decision below. |
| Stage 3: Boundary-aware same-package resolution | Not started | |
| Stage 4: Java single-type imports | Not started | Condition met by Stage 1 evidence. |
| Stage 5: Documentation, capability matrix, and closure | Not started | |

## Plan Readiness Gate

Applied on 2026-09-18 before Stage 1, against
[documentation.md](../agent-policy/documentation.md#plan-readiness-gate).

No hard fail. Scope and non-scope are explicit and name the documents that own
what the plan may not touch (`CORE.md` for `module` and `IMPORTS`,
[ADR 007](../adr/007_text_fallback_migration_flag.md) for the text fallback).
The stop rule is concrete and reversible: Stage 1 is a go/no-go whose no-go
re-opens the language choice rather than proceeding on faith. Stage 4 is the
only conditional stage and carries its own execution condition, its skip path,
and the measurement that must justify skipping. Every stage names likely files
and an observable done condition, and the verification strategy names commands
that exist in this repository.

Two executor decisions the plan deliberately leaves open are recorded here so
later stages do not re-litigate them:

- **The probe repository** is chosen in Stage 1 below against the plan's own
  criteria (open source, multi-module, large enough that manual orientation is
  hard), and its identity is pinned by commit.
- **How the false-fact count is measured** is a census, not an estimate: under
  [ADR 004](../adr/004_allow_java_same_package_type_resolution.md) a cross-unit
  Java `REFERENCES` fact can only target a top-level class definition, so
  enumerating the incoming relationships of every top-level class definition
  enumerates every cross-unit reference fact in the graph. Where a number below
  is a sample rather than a census, it says so and gives the sample size.

## Stage 1: External Java Evidence Probe

### Repository Identity

| Property | Value |
| --- | --- |
| Repository | [apache/dubbo](https://github.com/apache/dubbo) |
| Commit | `df9c5e13bc014ef492ec20824f8623a5e092a5b1` (2026-09-15) |
| Clone | `--depth 1` of the default branch, outside this repository |
| Maven modules (`pom.xml` files) | 119 |
| Java source units | 4,050 (2,469 under `src/main/java`, 1,581 under `src/test/java`) |
| Working-copy size | 37 MB |

It meets the plan's criteria: open source, genuinely multi-module, and large
enough that orientation by reading files is not practical. Its source is not
committed here; only the measurements below are.

### Ingestion Outcome

`zig-out/bin/semidx-mcp --root <clone> < /dev/null`, measured with
`/usr/bin/time -l` on macOS 25.6.0:

| Measurement | Value |
| --- | --- |
| Source units indexed | 4,050 |
| Ingestion wall time | 17.5 s |
| Maximum resident set size | 290 MB |
| Peak memory footprint | 547 MB |
| Scan diagnostics | 0 |
| Units analyzed / stale / pending | 4,050 current, 0 stale, 0 pending |

Graph contents at that snapshot (`semidx_health`):

| Measurement | Value |
| --- | --- |
| Definitions | 26,509 |
| Assertions recorded | 228,972 |
| Current facts | 88,498 |
| Current unresolved | 140,474 |
| Current approximate | 0 |
| `unsupported_construct` diagnostics | 58,300 |
| `confirmed_absence` diagnostics | 722 |

Ingestion completes on a repository 60 times the size of this one, with no
diagnostic saying analysis was unavailable or failed for any unit.

### Question Set

The questions are the ones
[the adoption strategy](../design/002_product_adoption_strategy.md#core-promise)
names as the core promise, asked through the habit loop in the order the
[preview reference](../mcp/local_preview.md#first-calls) teaches. Every call ran
against the snapshot above, and the timings below are the idle-machine
measurements from the latency table further down.

| # | Question | Call | Answer | Verdict |
| --- | --- | --- | --- | --- |
| 1 | Is the graph current enough to trust? | `semidx_health` | 4,050 units current, 0 stale, 0 pending, parsers available, per-language coverage notes, 58,300 unsupported-construct and 722 confirmed-absence diagnostics | Useful |
| 2 | What exists in a chosen area? | `semidx_outline` (root) | 15 top-level directories with unit, analysis, diagnostic, and definition counts, ~5 KB | Useful |
| 3 | What exists inside one module? | `semidx_outline` (`dubbo-rpc/dubbo-rpc-api`) | One entry, `src/`. Reaching the package directories takes seven more descents through `src/main/java/org/apache/dubbo/...`, each a separate call | Thin |
| 4 | Which definitions are in this package? | `semidx_repo_map` (`.../rpc/protocol`) | Every unit with its top-level classes, line ranges, per-unit diagnostic counts, and nested-definition totals | Useful |
| 5 | Where is a named definition introduced? | `semidx_find_definitions` `name=RpcContext` | Both declarations, each with its `java.package` label distinguishing `com.alibaba.dubbo.rpc` from `org.apache.dubbo.rpc`, in 0.02 s | Useful |
| 6 | Who references it? | `semidx_references` `incoming` on `RpcInvocation` and on `RpcException` | The target entity and **zero** incoming relationships, in 1.3 s | Thin |
| 7 | What neighborhood matters for a focused edit? | `semidx_context` `depth=2` on `RpcInvocation` | One focus entity, its unit, its `defines` edge, its diagnostics, and no traversal edges, in 91 s | Thin |
| 8 | Is the answer still current after an edit? | `semidx_refresh` after appending one line to `RpcInvocation.java` | `changed: 1`, `analyzed: 1`, revision 6783 → 6785, `entity_ids_preserved: true`, in 0.89 s | Useful |

No answer in this set was misleading: nothing presented an unestablished claim
as a fact. The thin answers are thin in two distinct ways, and only one of them
is this plan's business.

**Orientation and incrementality hold at this scale.** Health, outline, the
scoped map, definition lookup, and refresh answer the questions they are for.
The incremental claim is measured, not assumed: one edited file in a 4,050-unit
repository reanalyzed exactly one unit and preserved entity ids.

**Reference and neighborhood answers are near-empty, and the cause is coverage,
not this plan's boundary.** `RpcInvocation` is one of the most widely used types
in Dubbo, and the graph records no incoming reference to it at all. The reason is
in [ADR 004](../adr/004_allow_java_same_package_type_resolution.md)'s own
preconditions as the frontend applies them: a simple type name resolves beyond
its unit only when the enclosing class has no supertypes and no import could give
the name another meaning. Real Java classes almost always implement or extend
something and almost always import, so the rule declines far more often than it
fires. That is the frontend being honest rather than wrong, but it means the
impact question the adoption strategy names as the strongest signal is currently
answered with an empty list plus a caveat.

### The Follow-up 003 Defect, Reproduced Minimally

Before measuring the defect at scale, it was reproduced at its smallest. Two
directory trees, no build file of any kind, no dependency between them, each with
one class in package `demo`:

```
moduleA/src/main/java/demo/Helper.java     class Helper { String name() { … } }
moduleB/src/main/java/demo/Consumer.java   class Consumer { Helper helper() { … } }
```

`semidx_references` on `Consumer.helper` returns:

```
references  {"category": "fact",
             "method": "the only current top-level class of this simple name
                        in the same explicit package"}
   -> Helper  moduleA/src/main/java/demo/Helper.java
```

`moduleB` cannot see `moduleA` — nothing in the working copy says it can — so the
graph presents as a fact a relationship no Java compiler would establish. This is
[Follow-up 003](../followups/003_java_classpath_boundaries.md)'s
`semantic_limitation` reproduced exactly, and it is the case Stage 3 must turn
into an unresolved assertion.

**Per-call latency is a product problem at this scale.** Measured on an idle
machine against the same snapshot:

| Call | Time | Structured bytes |
| --- | ---: | ---: |
| `semidx_repo_map` (one package directory) | 0.01 s | 7,680 |
| `semidx_find_definitions` (`name` + `path`) | 0.02 s | 1,065 |
| `semidx_outline` (root) | 0.17 s | 6,764 |
| `semidx_refresh` (nothing changed) | 0.98 s | 512 |
| `semidx_references` (`incoming`) | 1.33 s | 749 |
| `semidx_health` | 2.96 s | 3,221 |
| `semidx_context` `depth=1` | 2.61 s | 35,294 |
| `semidx_context` `depth=2` | 90.71 s | 35,430 |
| `semidx_context` `depth=3` | 90.21 s | 35,430 |

Orientation is fast. Traversal is not: `depth=2` costs 90 s and, for this
entity, returns the same 35 KB as `depth=1` because there is nothing to traverse
to. The cost does not vary with `detail`, `limit`, or `max_response_bytes`, so it
is per-call work rather than rendering. The adoption strategy names
`semidx_context` the default focused-context tool and the strongest adoption
signal; at 90 s it is not usable on a repository this size. This is outside this
plan's scope and is recorded as a finding, not fixed here.

### What Stays Unresolved, And Why

Measured on a random sample of 1,200 of the 26,509 Java definitions (seed
`20260918`), by asking `semidx_references` for every outgoing claim of each
sampled definition: 6,710 outgoing claims.

| Claim | Resolution | Count | Share |
| --- | --- | ---: | ---: |
| `calls` | unresolved | 5,662 | 84.4% |
| `references` | unresolved | 809 | 12.1% |
| `calls` | fact | 174 | 2.6% |
| `references` | fact | 65 | 1.0% |

3.6% of outgoing claims are facts. The dominant single reason is unrelated to
this plan: 4,624 of the 5,662 unresolved calls are declined because the
invocation is qualified by a receiver the frontend does not resolve.

The plan asks for the unresolved reference share split by whether the target has
source in the working copy. Classifying each unresolved `references` designator
by whether any indexed Java unit declares a top-level class of that simple name:

| Unresolved reference target | Count | Share |
| --- | ---: | ---: |
| No top-level class of that simple name is declared here (dependency or JDK) | 706 | 87.3% |
| A top-level class of that simple name is declared here | 103 | 12.7% |

The first bucket is the dependency edge and is unresolved by design: its most
common designators are `String` (177), `boolean` (97), `int` (43), `Map` (33),
`List` (30) and `Object` (23) — primitives and JDK types that have no source in
any working copy. The second bucket is the only one this plan could convert, and
it is 12.7% of unresolved references, which is 1.5% of all outgoing claims.

Why that second bucket is declined, which is what decides Stage 4:

| Reason the frontend declined | Count | Share of 103 |
| --- | ---: | ---: |
| The enclosing class has supertypes, and a member type it may inherit is not resolved | 64 | 62% |
| An import names this type, and imports are not resolved | 29 | 28% |
| The type is not declared in the analyzed source unit | 7 | 7% |
| A qualified type name is not resolved beyond the analyzed source unit | 3 | 3% |

**Single-type imports are a material share and Stage 4 executes.** They are 28%
of the in-working-copy unresolved references — second only to the supertype
guard, which needs a type hierarchy this plan explicitly does not add. A further
32 import-declined references name types with no source here; those stay
unresolved after Stage 4, as the plan requires.

### Cross-Module False Facts: A Census, And A Zero

The plan asks for the count of same-package resolutions that cross a build-module
boundary — the [Follow-up 003](../followups/003_java_classpath_boundaries.md)
defect measured on real source rather than fixtures.

Method. Under [ADR 004](../adr/004_allow_java_same_package_type_resolution.md) a
cross-unit Java `REFERENCES` fact can only target a top-level class definition,
so the incoming relationships of every one of the 3,337 top-level class
definitions were enumerated: a census, not a sample. Each resulting cross-unit
fact was classified by comparing the source and target units' derived Java source
root, Maven module, and source scope, with the intra-repository Maven dependency
closure read from the 119 `pom.xml` files as data.

| Cross-unit `REFERENCES` fact | Count |
| --- | ---: |
| Both units in the same Java source root | 170 |
| Same module, a test source reads a main source | 161 |
| Different modules, permitted by a declared dependency | 5 |
| **Different modules, not permitted — a false fact** | **0** |
| **Same module, a main source reads a test source — a false fact** | **0** |
| Total cross-unit reference facts | 336 |

**The false-fact count on this repository is zero, before any change.** All five
cross-module facts are a test class reading a main class of a module its own
`pom.xml` declares a dependency on, in the same package — exactly what Java
permits.

This is the opposite of what the plan expected, so it was checked twice. The
1,200-definition sample scanned independently from the other direction found 11
cross-unit reference facts split the same way — 5 same source root, 5 same module
test-reads-main, 1 cross-module permitted, 0 violations — and its cross-unit
share (11 of 65 reference facts, 17%) agrees with the census (336 of 1,580, 21%).
The classifier is not blind to violations: it found and correctly classified the
five cross-module cases, and it reports the minimal reproduction above as a
violation.

Why the defect does not fire here is legible in the frontend's own declining
reasons. ADR 004 resolves a simple type name only when the enclosing class has no
supertypes, declares no member type of that name, and no import could give the
name another meaning. In real Java almost every class extends or implements
something, so the rule declines far more often than it fires — 1.0% of sampled
outgoing claims are reference facts. The defect is real, as the minimal
reproduction shows, but the preconditions that make ADR 004 safe are also what
keeps it from reaching across modules in practice.

The defect therefore is not "a false fact at scale on real source". It is a
**latent** defect: a rule that is correct only by accident of how narrow its other
preconditions are, in a repository whose layout happens not to expose it.

### Start Rule Verdict

Against the [Start Rule](../plans/010_java_resolution_boundaries.md#start-rule),
the question is whether first-party-only resolution answers the questions the
adoption strategy names.

| Core promise question | Answer on this repository | Verdict |
| --- | --- | --- |
| What files and top-level definitions exist | Complete, bounded, fast | Useful |
| Where a named definition is introduced | Complete and fast, with the package that disambiguates same-named classes | Useful |
| Who references or calls an entity | 336 cross-unit reference facts across 26,509 definitions; no cross-unit call facts exist by design; widely used types report no incoming references at all | Thin |
| What neighborhood matters for a focused edit | One focus entity and its unit; traversal costs 90 s and finds nothing to traverse | Thin |
| Whether an answer is current, stale, unresolved, unsupported, or approximate | Every claim carries resolution, producer, and freshness; 58,300 unsupported-construct diagnostics are visible rather than silent | Useful |
| Whether the index needs refresh after edits | One edited file in 4,050 reanalyzed exactly one unit in 0.89 s, entity ids preserved | Useful |

**Go, with the plan's own premise corrected.**

Go, because the Start Rule's stop condition is not met and its proceed condition
is: ingestion is robust at 60 times this repository's size, orientation and
freshness answers are useful and honest, and the unresolved dependency edge —
87.3% of unresolved references naming JDK and dependency types with no source
here — is the expected honest result at the boundary, not a failure.

The premise that needs correcting is Stage 3's justification, and it should be
recorded rather than quietly carried: this plan was written to remove a false
fact that real source does not currently produce. What the evidence says instead:

- The false fact is latent, not active. Removing it is defensible as removing a
  trap, not as fixing a measured harm. The plan's Definition of Done — "the
  cross-module false-fact count on the probed external repository is zero" — is
  satisfied by the unmodified code, so it cannot by itself demonstrate that
  Stage 3 achieved anything. Stage 3's proof has to be the minimal reproduction
  and the Follow-up 003 tests, not the external count.
- What actually limits Java usefulness is coverage, not boundaries: the supertype
  guard (62% of in-working-copy unresolved references), unresolved receivers
  (4,624 of 5,662 unresolved calls), and the absence of cross-unit call
  resolution.
- The one stage with measured value on real source is Stage 4: single-type
  imports are 28% of in-working-copy unresolved references, and its condition to
  execute is met.
