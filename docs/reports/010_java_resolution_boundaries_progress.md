---
title: "Java resolution boundaries progress"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-18"
---

# 010: Java Resolution Boundaries Progress

Companion log for
[docs/plans/010_java_resolution_boundaries.md](../plans/010_java_resolution_boundaries.md).

## Current Status

Plan 010 is complete. semidx has its first recorded evidence from a Java
repository it does not own, Java resolution is bounded by a derived source root,
single-type imports resolve inside that boundary, and cross-unit reference facts
on the probed repository rose from 336 to 496 with the cross-boundary false-fact
count at zero — now structurally, not accidentally.

One correction to the plan's premise is carried forward, because it should shape
what happens next: the false fact Stage 3 removed occurred **zero** times on real
source before the fix. It was a latent trap, not a measured harm. What actually
limits Java is coverage — the supertype guard and unresolved receivers — and the
90-second cost of `semidx_context` at depth 2. Both are in
[Residual Risk](#residual-risk) and in the roadmap's near-term direction. Stage 1's verdict is **go**, with one correction to the plan's
premise that later stages must carry: the false fact Stage 3 exists to remove is
latent, not active. It is reproducible in two directories but occurs zero times
in a 119-module, 4,050-unit external Java repository. Stage 4's execution
condition is met. Details and evidence are in
[Stage 1](#stage-1-external-java-evidence-probe).

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: External Java evidence probe | Completed | Apache Dubbo at `df9c5e1`: 4,050 units in 17.5 s, 290 MB; orientation and refresh useful, reference and neighborhood answers thin; cross-module false facts **0 of 336** cross-unit reference facts; single-type imports are 28% of in-working-copy unresolved references, so Stage 4 executes. Verdict: go. |
| Stage 2: Boundary representation decision | Completed (`691f9ac`) | [ADR 008](../adr/008_java_visibility_boundaries.md): visibility is the derived Java source root, plus standard-layout test → main in that direction only. No build descriptor is read and no core kind is admitted. |
| Stage 3: Boundary-aware same-package resolution | Completed | Same-package resolution establishes facts only inside a shared visibility scope. A name the package declares out of reach is unresolved for its own stated reason, not folded into "nothing declares this". The minimal reproduction is unresolved with its designator intact. |
| Stage 4: Java single-type imports | Completed | `import a.b.C;` resolves inside the boundary and is asked before the unit's own package, as Java orders them. On-demand, static, and unindexed imports each stay unresolved with their own reason. A package's importers are reanalyzed when its exports change, so a class appearing later reaches the unit that imported it. |
| Stage 5: Documentation, capability matrix, and closure | Completed | Capability matrix, preview reference, roadmap, and `MEMORY.md` state the boundary and the dependency edge. Follow-up 003 closed against ADR 008; its cross-module part split into Follow-up 011. |

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

## Stage 2: Boundary Representation Decision

[ADR 008](../adr/008_java_visibility_boundaries.md) decides it, answers all eight
questions of constitution section 11, and names the checks Stage 3 must satisfy.

The decision in one line: a Java source unit's **source root** is what remains of
its path once its declared package path and file name are stripped from the end;
two units share a visibility scope when their source roots are equal, or when the
referring unit is in `<base>/src/test/<lang>` and the provider is in
`<base>/src/main/<lang>` — that direction only. Everything else is unresolved.

### Options Considered

The three candidates the plan names, scored against the Stage 1 census of 336
cross-unit reference facts and against what each would have to read:

| Option | False facts left | True facts lost | Reads |
| --- | ---: | ---: | --- |
| A: same source root only | 0 | 166 of 336 (49%) | unit path, package declaration |
| **B: same source root, plus standard-layout test → main (chosen)** | **0** | **5 of 336 (1.5%)** | unit path, package declaration |
| C: B plus declared module dependencies | 0 | 0 | the above plus every `pom.xml` |

B was chosen. A discards nearly half the true cross-unit facts for no additional
safety. C recovers 1.5% more at the cost of interpreting Maven inheritance,
`dependencyManagement`, property interpolation, and profiles — where a misread
invents a dependency that does not exist, which is the same class of defect this
plan exists to remove, and where Gradle offers no data to read at all because its
build files are programs. B reads nothing that is not already parsed.

### What Stage 2 Deliberately Leaves Open

Cross-module same-package resolution stays unresolved even where a build tool
would permit it. That is a decision, not an oversight, and it is carried into
Stage 5 as a narrower follow-up rather than closed here.

## Stage 3: Boundary-Aware Same-Package Resolution

[ADR 008](../adr/008_java_visibility_boundaries.md) implemented in the Java
frontend and its package projection.

### What Changed

- `java.sourceRoot(path, package)` derives a unit's Java source root by walking
  the declared package backwards through the path's directories, segment by
  segment, so a directory ending in `mydemo` never satisfies a package `demo`. A
  path that does not spell its package has no source root.
- `java.sharesScope(referring, provider)` is the visibility rule: equal roots, or
  `<base>/src/test/<lang>` reading `<base>/src/main/<lang>`, and nothing else.
- `java_packages.Packages.context` now takes the analyzed unit's source root. A
  candidate outside the scope is never offered as a target. A unit with no source
  root gets an empty context and resolves nothing beyond itself.
- `Binding` gained `out_of_scope`. A name the package declares but the unit
  cannot see is not silently folded into "nothing declares this name": it is
  unresolved for a stated, different reason. Constitution section 3 requires
  every assertion to carry how far it was resolved, and "declared out of reach"
  and "not declared" are not the same answer.

### The Minimal Reproduction, After

The same two directories from Stage 1 now answer:

```
references  {"category": "unresolved",
             "missing": "target_entity",
             "explanation": "package `demo` declares 1 current top-level class of
                             this name, none of them in a Java source root this
                             unit can see"}
   -> designator "Helper"
```

The designator survives, the producer and freshness are unchanged, and the claim
is neither a confirmed absence nor an unsupported construct.

## Stage 4: Java Single-Type Imports

Executed: Stage 1 measured single-type imports at 28% of the unresolved
references whose target has source in the working copy, which is the plan's
condition.

### What Changed

- `java.singleTypeImports` reads `import a.b.C;` declarations as a package and a
  simple name. A static import, an on-demand import, and an unqualified import
  are not single-type imports and are not read as ones.
- `Context.imports` carries what each imported simple name currently means,
  resolved by `java_packages.importBindings` under the same visibility rule as
  the same-package table. A simple name imported twice is ambiguous whatever it
  reaches, because Java forbids it and semidx must not pick one.
- `resolveType` asks the import before the unit's own package, which is Java's
  order, and the import's answer is final: a name Java takes from an import does
  not fall back to the package. Every existing guard still runs first, so a type
  parameter, a member type, a supertype that could introduce one, and a static
  import all still decline before any import is consulted.
- Static imports moved to their own `static_imported` list and decline with their
  own reason. An import whose target no indexed unit declares declines with a
  third, distinct reason.

### Invalidation

A unit whose import resolved to nothing declares no dependency, so nothing would
have reached it when the class later appeared. `Packages` now also records which
packages each unit imports from, and `Upkeep.finish` reanalyzes a package's
importers along with its declarers when that package's exports change. The hint
is a superset, exactly like the existing declarer hint: a unit that has since
stopped importing from a package is reanalyzed for nothing, which costs a pass
and changes no claim. `a class appearing in an imported package reaches the unit
that imported it` proves the case that previously had no path at all.

### Measured On The External Repository

The same 1,200-definition sample as Stage 1, same seed, same calls, so the two
runs are directly comparable.

| Outgoing claim | Before | After |
| --- | ---: | ---: |
| `calls` unresolved | 5,662 | 5,662 |
| `references` unresolved | 809 | 804 |
| `calls` fact | 174 | 174 |
| `references` fact | 65 | 70 |

By how each fact was established:

| Resolution method | Before | After |
| --- | ---: | ---: |
| Type name declared in the analyzed source unit | 54 | 54 |
| The only top-level class of this simple name in the same package | 11 | 10 |
| The single-type import of this name | 0 | 6 |

Stage 3 cost one same-package fact in the sample — the boundary refusing a
resolution it can no longer establish — and Stage 4 added six. Unresolved
references whose target has source in the working copy fell from 103 to 98. Calls
did not move at all, which is the expected result: neither stage touches them.

Ingestion cost on the 4,050-unit repository rose from 17.5 s and 290 MB to 21.5 s
and 371 MB. The increase is the import bindings plus the extra reanalysis the
import hint causes; the snapshot revision after a first scan rose from 6,783 to
7,274, which is those extra passes.

### Checking The Graph Did Not Grow A Second Copy Of Anything

Graph-wide, current facts rose by 1,941 and current unresolved fell by 160, which
did not obviously balance, so it was checked rather than assumed.

- `recorded` equals `fact + unresolved` exactly, both before (228,972 = 88,498 +
  140,474) and after (230,753 = 90,439 + 140,314). No assertion is left behind as
  current after being superseded.
- On a four-unit reproduction with and without the imports, every relationship
  kind balances: `contains` 4 and 4, `defines` 5 and 5, `references` 0 facts and
  4 unresolved against 3 facts and 1 unresolved. Thirteen relationships in both.
  The only change is the conversion.
- The sample's reference population balances exactly: five facts gained, five
  unresolved lost.

What remains is not a relationship. Entities are unchanged (1 repository, 4,050
files, 26,509 definitions), so the additional assertions are identity
correspondences — the assertion kind a reanalysis records when it re-establishes
that an entity it is seeing again is the same entity. More reanalysis passes
record more of them.

### The Census, Re-Run

The Stage 1 census repeated against the same repository and commit, by the same
method: the incoming relationships of every one of the 3,337 top-level class
definitions.

| Cross-unit `REFERENCES` fact | Before | After |
| --- | ---: | ---: |
| Both units in the same Java source root | 170 | 273 |
| Same module, a test source reads a main source | 161 | 223 |
| Different modules, permitted by a declared dependency | 5 | 0 |
| Different modules, not permitted | 0 | 0 |
| Same module, a main source reads a test source | 0 | 0 |
| **Total** | **336** | **496** |

By how each fact was established:

| Resolution method | Before | After |
| --- | ---: | ---: |
| The only top-level class of this simple name in the same package | 336 | 331 |
| The single-type import of this name | 0 | 165 |

This is exactly what [ADR 008](../adr/008_java_visibility_boundaries.md)
predicted it would cost and buy. Stage 3 refused precisely the five cross-module
facts and nothing else: 336 same-package facts became 331. Stage 4 added 165.
Cross-unit reference facts rose 48%, and the graph-wide current unresolved count
fell by exactly 160, which is 496 − 336 — the same conversions counted from the
other side, and the answer to the balance question above.

The false-fact count is still zero. The difference from Stage 1 is what that zero
now rests on: before, it was zero because ADR 004's other preconditions happened
not to reach across a module; now it is zero because a cross-boundary resolution
cannot be established at all.

## Stage 5: Documentation, Capability Matrix, And Closure

| Document | Change |
| --- | --- |
| [capability matrix](../spec/capability_matrix.md) | The Java entry gains a **Visibility scope** row stating the source-root rule and the one directional exception, a **Dependency edge** row naming what will never resolve and why, per-import-form unresolved reasons, and an **Evidence** row recording the external repository, its commit, and its ingestion cost. The "known overbroad case" row is gone: it described the defect this plan removed. |
| [local preview reference](../mcp/local_preview.md) | Two new limits: what a Java answer's boundary is in terms a user can act on, and that a reference to a type with no source under `--root` is unresolved by design and no configuration changes it. |
| [Follow-up 003](../followups/003_java_classpath_boundaries.md) | Closed against ADR 008 and this plan, with each of its four required tests named against the test that implements it, and with the part that is deliberately not closed split out. |
| [Follow-up 011](../followups/011_java_cross_module_visibility.md) | New. Cross-module visibility a build descriptor would establish, with the measurement that bounds its value (5 of 336 facts) and the risk that deferred it. |
| [roadmap](../design/001_project_roadmap.md) | Records that the adoption track was entered and what the probe showed, including the two findings that outrank further boundary work. |
| [MEMORY.md](../../MEMORY.md) | Java resolution reality, the boundary, what does not exist, the latency finding, and the next-step reading order. |

### Verification

All six commands from the plan's verification strategy, on the final tree:

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches the target |
| `zig fmt --check build.zig src tests` | clean |
| `zig build test-core` | pass |
| `zig build test` | 20/20 steps, 224/225 tests passed, 1 skipped |
| `zig build dogfood` | 10/10 steps, 5/5 tests, `dogfood success` |
| `zig build preview-gate --summary all` | 14/14 steps, 6/6 tests, `preview-gate success` |

The test lane grew by eleven tests: three unit tests for the source-root and
scope rules, four boundary integration tests, and four import tests including the
invalidation case.

### Definition Of Done

| Requirement | Status |
| --- | --- |
| Same-package facts only within an explicit visibility boundary; false-fact count on the probed repository zero | Met. 496 cross-unit facts, none crossing a boundary it may not cross. |
| Absent or ambiguous boundary evidence yields unresolved, never a name-selected fact | Met, and tested for a path that does not spell its package, for a cross-root pair, and for ambiguity inside one scope. |
| Dependency references unresolved with designators intact, distinguishable from confirmed absence and unsupported constructs | Met; `expectHonestlyUnresolved` checks resolution, designator, producer, freshness, missing part, and the absence of a confirmed-absence diagnostic. |
| No shared-core kind admitted; `module` and `IMPORTS` remain CORE.md's | Met. The source root is Java extension vocabulary in the analyzer's projection. |
| No build tool executed, no network at index or query time | Met. Only the unit path and the package declaration are read. |
| Recorded evidence of semidx against a Java repository it does not own, including what it could not answer | Met, in Stage 1 above, thin answers included. |
| Follow-up 003 closed or narrowed; capability matrix states the boundary in actionable terms | Met; closed, with the cross-module part split into Follow-up 011. |

### Residual Risk

- **The evidence is one repository.** apache/dubbo is a Maven repository that
  follows the standard directory layout in all 4,050 of its units. A repository
  with a different layout, or one whose paths disagree with its package
  declarations, gets less resolution, not wrong resolution — but nothing here
  measures how much less.
- **Cross-module references a build tool would permit stay unresolved**, by
  decision ([Follow-up 011](../followups/011_java_cross_module_visibility.md)).
- **Framework and dependency-injection relationships are invisible.** A
  source-only graph cannot see what Spring, SPI, or reflection wires together,
  and Dubbo is built on exactly that. Nothing in `semidx_references` will show
  those edges, and no diagnostic says they exist.
- **The importer hint is a superset that only grows.** A unit that stops
  importing from a package is still reanalyzed when that package changes. It
  costs a pass and changes no claim, and nothing prunes it while the graph lives.
- **Java coverage, not its boundary, is the limit.** The supertype guard declined
  62% of the unresolved references whose target does have source in the working
  copy, and receivers accounted for 4,624 of 5,662 unresolved calls. Neither is
  in this plan's scope and neither is improved by it.
- **`semidx_context` at `depth` 2 or more cost about 90 s** on this repository,
  against 0.02 s for `semidx_find_definitions`. The adoption strategy names it
  the default focused-context tool.

### Architecture Review Addendum

Post-closure architecture review found no new correctness defect in the Java
source-root boundary or single-type-import rule. The decision remains sound:
ADR 008 narrows graph authority, keeps the source root as Java frontend
projection vocabulary, and turns unestablished cross-boundary names into
unresolved assertions with designator, producer, freshness, and missing-part
evidence intact. That is the right architectural trade: less coverage, no false
fact.

Findings recorded for future planning:

- **High: `semidx_context(depth >= 2)` is not architecturally ready to be the
  default impact tool on external-scale repositories.** The 90 s Dubbo result is
  supported by the current traversal shape: it repeatedly asks the snapshot for
  relationships of each focus/frontier entity. Response budgets cap output size,
  not traversal work. Future work should add graph or snapshot adjacency indexes
  and a latency fitness check against an external-scale root before treating
  depth-2 context as an adoption-path default.
- **Medium: the next Java bottleneck is coverage, not the boundary.** The
  supertype guard and receiver-qualified invocation gap explain far more missing
  value than cross-module visibility. The next Java semantic plan should prefer
  exact supertype/member-type evidence or receiver-qualified calls over another
  boundary plan.
- **Medium: growing Java package/import hints are a bounded maintenance tradeoff
  today and a persistence/watch risk later.** The hints are correctly
  non-authoritative and re-read from the graph before use, so they do not create
  false facts. Before long-running watch or persistent indexes, add pruning,
  compaction, or per-unit current import-package ownership so historical imports
  do not accumulate unnecessary invalidation work.

Review verification on the closed tree:

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches the target |
| `zig build test-core --summary all` | 5/5 steps, 89/89 tests passed |
| `zig build test --summary all` | 20/20 steps, 224/225 tests passed, 1 skipped |
| `zig build dogfood --summary all` | 10/10 steps, 5/5 tests passed |
| `zig build preview-gate --summary all` | 14/14 steps, 6/6 tests passed |
| `zig fmt --check .` | Failed on the intentionally unparsable fixture `fixtures/vertical-slice/zig/edits/05_unparsable.zig`; the plan's scoped format command remains `zig fmt --check build.zig src tests` |

### Drift Check At Closure

Owners checked and aligned: `CORE.md` unchanged and correct — no kind was
admitted, and `module` and `IMPORTS` remain its open questions. `SPEC.md`
unchanged; the capability matrix it owns is updated. The constitution is
untouched and its seal verifies. `CONFORMANCE.md` unchanged: no scenario family
changed shape. `GLOSSARY.md` needs no entry — "Java source root" is defined by
ADR 008 and stated in the capability matrix, which the documentation policy
accepts as naming the owning document. `MEMORY.md`, the roadmap, the capability
matrix, the preview reference, and the follow-up register are updated in this
plan's commits.

### Next Step

Do not start another Java boundary plan. The probe says the next Java work worth
doing is coverage where it measurably stops — the supertype guard first, then
receiver-qualified calls — and that per-call latency is a product problem that no
amount of coverage compensates for. Both are recorded in the roadmap's near-term
direction. Whether either is worth more than a second external probe in a
different language is a product decision this plan does not make.
