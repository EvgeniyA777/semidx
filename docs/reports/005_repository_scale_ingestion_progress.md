---
title: "Repository-scale ingestion progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-14"
---

# 005: Repository-Scale Ingestion Progress

Companion log for
[docs/plans/002_repository_scale_ingestion.md](../plans/002_repository_scale_ingestion.md).

## Current Status

Stages 1 through 4 are implemented and verified. A tree can be scanned,
rescanned, and reconciled; changing one unit costs the same whatever else the
repository holds, and that is now enforced by a guard rather than believed.
Stage 5 is next: giving invalidation something real to act on.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Plan creation | Completed | Created the staged plan and this log. Gate applied; findings below. |
| Stage 1: Source discovery | Completed | `src/source/{root,languages,scan,discovery}.zig`, the `semidx_source` module, `Index.addScan`, and a developer command that takes a root. |
| Stage 2: Unit identity independent of path | Completed | `model.Scope`, unit tombstones, `setSourceUnitPath`, `removeSourceUnit`, and both frontends scoping entities to the unit. |
| Stage 3: Scan reconciliation | Completed | `src/source/registry.zig` decides correspondence as a pure function; `Index.applyScan` applies it; `Analyzer.invocations` measures what was re-read. |
| Stage 4: Affected-region proof at scale | Completed | Per-unit buckets and indexes in the graph, `Graph.unit_work`, `fixtures/repository-scale/`, and scale tests that fail if a keyed lookup regresses into a sweep. |
| Stage 5: Cross-unit dependency tracking | Not started | Awaiting Stage 3. Opens with an ADR. |
| Stage 6: Closure and documentation | Not started | Awaiting Stage 5. |

## Plan Readiness Gate

Applied against
[documentation.md](../agent-policy/documentation.md#plan-readiness-gate) before
any implementation.

### Hard Fail Conditions

| Condition | Result |
| --- | --- |
| Product or runtime behavior unclear, or conflicting with sources of truth | Pass. The plan was written after reports 003 and 004, so it uses the accepted roster including the `CONTAINS`/`DEFINES` split, and changes no accepted meaning. |
| Scope boundaries missing, vague, or allowing unrelated refactoring | Pass. Non-Scope names persistence, public surfaces, ignore-file parsing, language import semantics, snapshot redesign, and performance work explicitly. |
| A key technical decision implicit, unjustified, or externally gated without a stop rule | Pass after correction; see finding 1. |
| Branches mentioned but not carried through stages, files, verification, and DoD | Pass after correction; see finding 1. |
| Stages depending on later stages, or lacking concrete outputs | Pass. Each stage names files or artifacts. Stage 5 depends on Stage 3, not on Stage 4, and the gate records that ordering. |
| DoD not verifiable through files, commands, tests, or artifacts | Pass. Every DoD item is a test, a command, or a document state. |
| Test strategy missing main risks | Pass. The risk matrix covers discovery correctness, core/environment separation, rename identity, identity-loss visibility, affected-region measurement, quadratic behavior, invalidation, approximate-versus-fact, freshness at scale, privacy, and documentation truthfulness. |
| Runtime constraints ignored | Pass. Budgets, symlink handling, temporary-tree isolation, and the no-network constraint are named. |
| Documentation targets contradicting each other or carrying stale bookkeeping | Pass after correction; see finding 2. |
| Requires guessing what to implement, skip, test, or when to stop | Pass. Four stop conditions are stated with resume behavior. |

### Findings Raised And Fixed Before Execution

1. **Stage 5 was an unresolved branch.** The first draft left "record cross-unit
   name matches as approximate assertions" as a good idea without saying what
   happens if it turns out to conflict with
   [§1](../../ARCHITECTURE_CONSTITUTION.md#1-semantic-graph-is-the-product).
   That is two hard-fail conditions at once: an externally gated decision with no
   stop rule, and a branch not carried through DoD. Fixed by opening the stage
   with an ADR and giving both outcomes a complete DoD, so the plan completes
   either way.

2. **The plan had to be rewritten against a roster that changed while it was
   being written.** Reports 003 and 004 admitted `repository`, `file`,
   `definition`, `CONTAINS`, `DEFINES`, `REFERENCES`, and `CALLS`, and split
   containment from definition introduction. An earlier draft still described
   `repository DEFINES file`. Corrected throughout.

### Ready Criteria

| Criterion | Result |
| --- | --- |
| Contract changes explicit and tied to sources of truth | Pass. The one model change — identity scope becoming unit identity rather than a path — is stated as a plan-level decision and tied to §4. |
| Scope and non-scope explicit | Pass. |
| Key decisions and rationale recorded | Pass. Seven plan-level decisions, each with its reason. |
| Blockers and branches have precise stop and resume behavior | Pass. |
| Each stage has purpose, ordered dependencies, and concrete outputs | Pass. |
| Verification commands and acceptance checks named | Pass. The lanes are the ones [testing.md](../agent-policy/testing.md#verification-lanes) already records. |
| DoD observable and falsifiable | Pass. The load-bearing one is a frontend invocation count, which fails if a rescan does more work than it should. |
| Risk-based tests mapped to behavior | Pass. |
| Runtime and environment traps considered | Pass. |
| Internally consistent, not overloaded with irrelevant detail | Pass. |

**Gate result: ready for execution.**

## Stage 1 Record

### What Was Built

- `src/source/languages.zig` owns the one extension-to-language table.
  `semidx.languageForPath` now forwards to it instead of carrying a second copy.
- `src/source/scan.zig` owns the scan value: `ScannedUnit`, `ScanDiagnostic`,
  `Budgets`, `Options`, and the exclusion list. Content identity is SHA-256.
- `src/source/discovery.zig` owns the walk. `scan` opens a root path; `scanDir`
  walks an already-open handle, which is what lets tests work against a
  temporary directory without assuming anything about the working directory.
- `build.zig` gains the `semidx_source` module. It has no C dependency, so it
  joins the `test-core` step; that step's description now reads "every lane that
  needs no parser" rather than naming only the core.
- `Index.addScan` registers a scan's units and records what the scan declined as
  graph diagnostics, so a file that was found but not ingested stays visible.
- `semidx-dev` takes directories as well as files.

### Decisions Taken During Stage 1

- **Symbolic links are not followed at all.** The plan asked to refuse links
  that leave the root and to terminate on loops; declining every link satisfies
  both with no path arithmetic and no cycle bookkeeping. Every link is reported,
  so a skipped one is never silent. A link pointing inside the root is therefore
  also skipped: a real limitation, recorded below rather than hidden.
- **Exclusion is an explicit directory-name list, not a dot-prefix rule.**
  `.git` must be skipped and `.github` must not be; only a list can express that.
- **Units are sorted by path.** Directory iteration order is a filesystem detail,
  and letting it through would make unit identity allocation in Stage 2 and every
  test over a scan depend on it.
- **Content identity is SHA-256, not a fast 64-bit hash.** This value will decide
  "unchanged, do not reanalyze" and "same unit under a new path". A collision
  there is not a slow answer; it is a wrong graph with a heuristic wearing the
  face of a fact.
- **Policy exclusions produce no diagnostic; everything else does.** A file no
  frontend covers and a directory on the exclusion list are not degradation. A
  budget refusal, an unreadable file, and a symbolic link are.

### Plan Correction

The plan's Dependency Direction said `source/discovery` depends on "nothing in
`core/`", while Stage 1's task list required one extension-to-language table
shared with `languageForPath`, which returns `model.Language`. Both could not
hold: honoring the first would have forced a second `Language` enum whose first
symptom would be a file that is a source unit to one caller and invisible to
another. The line now permits `core/model` value vocabulary only — `Language`
and `DiagnosticKind` — and forbids `core/graph`, `core/contract`, and
`core/reconcile`. The property being protected, that nothing in the core depends
on the filesystem, is unchanged and is still proved by
`zig build test-core -Dgrammars-dir=/nonexistent`.

### Defect Found And Fixed During Stage 1

`SourceScan` carries its arena by value, and the returned struct literal
initialized `.arena` before a field that allocated into that arena. The field
initializers run in written order, so the arena state was copied before the last
allocation was made, and that allocation was unreachable from the result. The
leak checker caught it on the empty-tree case, where it was the only allocation.
Fixed by hoisting every allocation above the literal, with a comment saying why
the order matters.

### Verification

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 50/50 passed: core 38, source 12. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 50/50 passed; source ingestion has no parser dependency either. |
| `zig build test --summary all` | 80/80 passed across five lanes, after deleting `.zig-cache/` and `zig-out/`. |
| `zig build run -- fixtures` | Walked the fixture tree, registered 12 units, and reported the two deliberately unparsable fixtures as `pending` rather than as empty files. |
| `zig fmt --check build.zig src tests` | Clean. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

Stage 1 DoD, item by item:

- Tests build a temporary tree and assert the discovered set, including that an
  excluded directory contributes nothing and an unmapped extension is not a
  unit. Two exclusion cases are covered (`.git`, `zig-out`), plus a `.java.bak`
  file that must not match on a suffix.
- A file at the size budget produces a diagnostic naming the limit, and the
  smaller file beside it is still ingested.
- A symbolic link loop terminates: a link to its own containing directory is
  reported, the walk completes, and only the real files are found.
- The unit budget and the depth budget each produce one diagnostic naming the
  limit.
- An unreadable root is `error.RootUnavailable`, not an empty scan.
- A scan of the same tree twice is identical.
- `zig build test-core` passes with no filesystem dependency in `src/core/`.

### Residual Risk From Stage 1

- A symbolic link pointing inside the root is skipped along with one pointing
  out. Correct for confinement, wrong for a repository that uses links
  internally. The diagnostic makes it visible; widening it needs real path
  resolution and a cycle set.
- `SourceScan` holds its arena by value, so copying one and releasing both is a
  double free. Same shape as `Graph`; documented, not type-enforced.
- `Index.addScan` is first-pass only. Calling it twice rejects the repeated
  paths, because reconciliation against an existing registry is Stage 3.
- Budgets are defaults picked by judgement, not measurement: 4 MiB per file,
  20,000 units, 64 levels. Stage 4 is the first point where a real tree can say
  whether they are reasonable.

## Stage 2 Record

### The Stop Condition Did Not Fire

The plan's third stop condition was that unit identity might not be makeable
path-independent without changing the accepted `file` definition in `CORE.md`.
It did not apply: that definition already says "Location is a property, not an
identity derived from byte or line position. Renames and moves obey the
constitutional identity and provenance rules", which supports the change rather
than blocking it. No accepted core meaning changed.

### What Was Built

- `model.Scope` is a union of `repository` and `unit: SourceUnitId`.
  `IdentityEvidence.scope` now carries it instead of a path string.
- Source units carry `removed_revision` and tombstone rather than disappear, so
  a removed unit's identity is never handed to a later one. `SourceUnitView`
  carries the unit's source-container entity, which is how a consumer gets from
  a path to entities now.
- `Graph.setSourceUnitPath` moves a unit: it updates the path property, refreshes
  the container's evidence, and re-records what ingestion claims. It does not
  touch `content_revision`, so a rename does not make a unit stale and owes no
  reanalysis.
- `Graph.removeSourceUnit` withdraws the unit's assertions and removes its
  entities, recording a `removed` identity event for each — a definition that
  left with its file is observable as having left, not merely missing.
- `Snapshot.EntityFilter` gained `path`, resolved through the unit registry.
  `findDefinition(path, name)` keeps its shape, so most call sites did not move.
- Both frontends scope entities to `input.unit.id`.

### Decisions Taken During Stage 2

- **The source container entity has no name.** Its identity is its unit and its
  role. Naming it by its path would have made the container itself break
  identity on exactly the operation this stage exists to survive. The path lives
  on the unit and in the entity's evidence, both of which a rename refreshes.
- **A missing scope became unrepresentable rather than validated.**
  `ValidationError.MissingIdentityScope` is gone, because `Scope` is a union with
  no empty case. A constraint the type enforces is better than one a function
  checks.
- **A rename is not an edit.** It opens a revision, because it mutates the graph,
  but leaves `content_revision` alone. Freshness therefore stays `current`
  through a rename, which is correct: the contents nobody touched are still the
  contents that were analyzed.
- **Unit identity stays an index into an append-only table**, the same shape
  `EntityId` already uses. Allocated by the graph, never derived from the path,
  never reused because the table only grows.

### Verification

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 56/56 passed, up from 50. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 56/56 passed. |
| `zig build test --summary all` | 87/87 passed, after deleting `.zig-cache/` and `zig-out/`. |
| `zig build run -- fixtures/vertical-slice/java` | Unit paths now come from the registry rather than from identity evidence; output unchanged in shape. |
| `zig fmt --check build.zig src tests` | Clean. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

Stage 2 DoD, item by item:

- A unit-level test renames a unit and asserts that every definition in it, the
  source container itself, and the relationship count between them are unchanged
  — and that what ingestion claims about the unit now carries the new path.
- A test registers two units at the same relative path under different roots and
  asserts they are distinct units whose definitions, identical in every field a
  consumer can name, do not correspond and do not occupy the same slot.
- The existing 81 tests passed unchanged in meaning. The only test edits were
  three filters where `.scope = <path>` became `.path = <path>`, which is the
  same question asked of the registry instead of of identity evidence.
- An end-to-end test renames a real fixture unit, asserts no identity event was
  recorded at that revision, and then edits the renamed unit and gets four
  preserved entities — so identity survives a rename *and* an edit after it.

### Residual Risk From Stage 2

- Unit identity is an index into an append-only table. Tombstones make removal
  safe, but the table never shrinks, so a long-lived process over a churning
  repository grows it without bound. Same shape as entity tombstones; a
  compaction story belongs with persistence.
- `setSourceUnitPath` rejects a move onto an occupied path. A scan that swaps two
  files' paths therefore cannot be applied as two renames in either order. Stage
  3 owns rescan reconciliation and must handle the swap, probably by resolving
  removals before renames.
- Nothing yet detects a rename. Stage 2 makes one survivable; deciding that a
  removed path and an added path are the same unit is Stage 3's correspondence
  rule, using the content identity Stage 1 already produces.

## Stage 3 Record

### What Was Built

- `src/source/registry.zig` decides what happened between two scans, as a pure
  function over unit identity evidence. No filesystem, no graph, no frontend —
  which is what lets a swap, an ambiguous move, and a cross-language content
  collision be tested directly instead of through a whole indexing run.
- `model.ContentId`, `model.contentId`, and `model.UnitIdentityEvidence` moved
  into the shared model, so the registry deciding correspondence and the graph
  storing what it already holds agree on content identity exactly rather than
  approximately.
- `Graph.setSourceUnitPath` now records the move as a `preserved` identity event
  and an `identity_correspondence` assertion resolved as a fact. Identical bytes
  under a new path is exact resolution of "the same unit", not a similarity
  score, so it is recorded as established rather than heuristic.
- `Index.applyScan` replaces `addScan`. The first scan against an empty index is
  all additions; every later one is reconciled.
- `Analyzer.invocations` counts how many times a frontend was asked to read a
  unit. This is the stage's load-bearing number.
- `Snapshot.lastIdentityEvent` answers "what most recently happened to this
  entity's identity" without the caller having to know which revision of a
  multi-step operation recorded it.

### The Correspondence Rule

In order:

1. A path present in both scans is the same unit. Path is unambiguous — a scan
   holds each path once — and it is the strongest evidence available. Whether
   the contents changed decides only whether reanalysis is owed.
2. A unit whose path disappeared corresponds to a new unit with identical content
   and the same language, and only when exactly one of each exists for that
   content.
3. Everything else is a removal or an addition.

Two consequences worth stating, because both were open questions going in:

- **The path-swap problem predicted after Stage 2 does not exist.** If two files
  exchange contents, both paths are present in both scans, so path correspondence
  places both units where they already are and both are reanalyzed. No rename is
  claimed, so no rename has to be applied through a path another unit still
  occupies. Removals are still applied before renames, because a unit can be
  renamed onto a path a *departing* unit held.
- **A file that moved and changed is a removal and an addition.** Nothing
  establishes that the new unit is the old one, and inferring it from similarity
  is exactly what the constitution's identity clause forbids presenting as
  established.

### Plan Correction

The Stage 3 DoD asked for `lost` for a unit that was renamed while being edited.
That is wrong, and the plan now says so. `lost` means a replacement was
identified but correspondence to it could not be established. For units no such
case exists: a path present in both scans always corresponds, and a path that
disappeared leaves no slot for anything to take. Recording `lost` would name a
replacement the graph did not identify — the precise dishonesty the event exists
to prevent. The DoD now asks for `removed` plus `added`, with a `removed`
identity event for every definition that left, which is what the implementation
does and what the test asserts.

### Decisions Taken During Stage 3

- **An ambiguous move is reported, not resolved by picking one.** One removed
  unit whose content matches two added units produces no rename, and a diagnostic
  saying why. Choosing arbitrarily would produce a stable-looking identity that
  is stable by luck.
- **A rename requires the same language.** Identical bytes read as two different
  languages are two different units, whatever the byte comparison says.
- **A move owes no reanalysis.** Nothing inside the file changed, so nothing is
  re-read, and the unit does not go stale.
- **Scan-level diagnostics are replaced, not accumulated.** `dropScanDiagnostics`
  withdraws the previous scan's account of the tree before recording this one's,
  the same way per-unit diagnostics already describe only the latest attempt.
- **Lookups are keyed, not scanned.** The registry builds a path map and a
  content map rather than nesting loops, and orphaned units carry their evidence
  with them rather than being looked back up by id. Stage 4 will guard this; it
  was cheaper to not introduce the problem.

### Verification

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 67/67 passed, up from 56: core 44, source 23. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 67/67 passed. |
| `zig build test --summary all` | 106/106 passed, after deleting `.zig-cache/` and `zig-out/`. |
| `zig build run -- fixtures/vertical-slice` | Walked and reconciled the fixture tree; the two unparsable fixtures still report `pending`. |
| `zig fmt --check build.zig src tests` | Clean. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

Stage 3 DoD, item by item:

- Rescanning an unchanged tree invokes no frontend, opens no revision, and
  records no identity event. The test compares the invocation counter and the
  event count across two publishes.
- Moving a file with identical content preserves the unit id, its container
  entity, every definition id inside it, and their relationship counts, records
  `preserved`, and re-reads nothing.
- Moving a file while editing it records `removed` for the old unit with a
  `removed` event for each definition, and `added` for the new one, whose
  definitions are different entities. See the plan correction above.
- Deleting a file removes its entities with recorded events, leaves the other
  unit's entity ids and analysis state untouched, and re-reads nothing.
- The invocation count is asserted directly: a tree of thirteen units with one
  edited file moves the counter by exactly one.

Beyond the DoD, the pure registry has twelve tests of its own covering the first
scan, an unchanged tree, a content change, a move, a move-and-edit, a path swap,
an ambiguous move, a cross-language content collision, unrelated churn beside a
move, and an emptied tree.

### Residual Risk From Stage 3

- **`applyScan` publishes nothing between its phases, but it does open several
  revisions.** A scan with removals, renames, and edits walks the graph through
  intermediate revisions. No consumer can observe them, because observation is
  `publish`, but a future concurrent reader would need the whole scan to be one
  revision.
- **Reanalysis is decided by content identity alone.** A unit whose own bytes did
  not change is never re-read, which is correct today only because no assertion
  depends on another unit. The moment cross-unit resolution exists, this becomes
  the thing invalidation has to override, which is Stage 5.
- **The unit table still never compacts**, and a churning tree now grows it on
  every rescan rather than only on explicit removal.
- **Nothing measures cost yet.** The thirteen-unit test proves the shape of the
  work; Stage 4 is where a tree large enough to expose an accidental quadratic
  gets built.

## Stage 4 Record

### The Guard Required Fixing What It Measures

Writing the guard first showed that ingestion was quadratic in three places, all
of them per-unit operations implemented as graph-wide sweeps:

- `dropAssertionsForUnit` and `dropIngestionAssertionsForUnit` filtered every
  assertion in the repository to find one unit's.
- `definitionsInUnit` walked every entity in the repository.
- `unitByPath` walked every unit, and it is called on every registration and
  every move.

Each is O(graph) per unit, so a full scan of n units was O(n²). None of it was
visible at two units, which is exactly why the stage exists.

The fix is to store things the way they are accessed. Assertions and diagnostics
are bucketed by the source unit they were observed in, definitions are indexed
per unit, and paths are indexed to units. Withdrawing one unit's analysis now
touches that unit's bucket and nothing else. `publish` still walks everything —
deliberately, because a consumer observes one complete state — and now
concatenates the buckets, which makes assertion order grouped by unit rather than
global insertion order. That order is still deterministic.

One query was quadratic too, outside the ingestion path: `EntityFilter.path`
resolved a path to a unit once per candidate entity. It resolves once per query
now.

### How The Guard Works

`Graph.unit_work` counts stored records examined while applying a change scoped
to one source unit. The scale tests build two trees of different sizes, apply the
same one-unit edit to each, and assert the counter moved by exactly the same
amount. If any per-unit operation goes back to sweeping, that number grows with
the tree and the assertion fails.

It was verified by regression rather than by assumption: reverting `filterBucket`
to a graph-wide sweep made the counter read 1532 instead of 524 on the larger
tree, and all three scale tests failed. The change was then reverted.

A second test states the same property from the other side — building a tree of
three times the units costs between two and four times the work, not nine — and
bounds the work per unit by a constant.

### Measured Publish Cost

`publish` copies the observable state on every call. On a generated tree of 73
units:

| Records | Count |
| --- | --- |
| Source units | 73 |
| Entities | 292 (73 files, 218 definitions, 1 repository) |
| Assertions | 764 |

So one publish copies roughly 1,100 records for 73 units, around 15 per unit,
and it is linear in the graph rather than in the change. **This is recorded as an
accepted cost, not a solved problem.** It is the right shape for a slice that
publishes once per batch of edits and the wrong shape for a consumer that
publishes per query. Changing it means changing what a snapshot is, which is the
storage-and-snapshots item owned by `SPEC.md`, and this plan deliberately does
not touch it.

### `fixtures/repository-scale/`

Six units, three per language, with a namespace structure and cross-unit
references that are all currently unresolved — `Greeter` names the type `Helper`,
`demo.greeter/greet` names `decorate`, and both are declared in other units. A
test asserts they stay designators with recorded explanations while same-unit
references resolve as facts.

This is the tree Stage 5 needs, and it is small on purpose. The large trees that
make quadratic behavior observable are generated inside the tests: a few dozen
committed files differing only by an index would add noise without adding
evidence. The plan asked for rescan histories in the fixture directory; they are
generated too, for the same reason, and the fixture `README.md` says so.

### Verification

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 67/67 passed. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 67/67 passed. |
| `zig build test --summary all` | 110/110 passed, after deleting `.zig-cache/` and `zig-out/`. |
| `zig build run -- fixtures/repository-scale` | 6 units, 14 definitions, 48 assertions, 5 unresolved, 0 stale. |
| Deliberate regression of `filterBucket` to a graph-wide sweep | All three scale tests failed; reverted. |
| `zig fmt --check build.zig src tests` | Clean. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

Stage 4 DoD, item by item:

- Tests over trees of 25 and 73 units assert the edit cost is equal across them
  and that one frontend invocation happened in each.
- The guard fails if a keyed lookup becomes a scan, demonstrated by doing it.
- The measured `publish` cost is recorded above and named as an accepted risk.

### Residual Risk From Stage 4

- **`publish` is linear in the graph.** Measured above. Acceptable while
  publication is per batch; not acceptable per query.
- **Entity correspondence within a unit is quadratic in that unit's size.** A
  file with a thousand definitions compares a million pairs. It is bounded by
  what changed, not by the repository, so the guard passes — but a generated
  source file would find it. Fixing it means hashing identity evidence.
- **`Snapshot.entityById` is still a scan.** It is a query convenience and not on
  the ingestion path, so the guard does not cover it; a consumer resolving many
  ids would feel it.
- **The unit table, the entity table, and the identity event log never compact.**
  A long-lived process over a churning tree grows all three without bound.
- **`unit_work` counts what it was told to count.** It covers the operations this
  plan introduced; a future sweep added somewhere uncounted would not fail the
  guard. The counter is a tripwire, not a proof.

## Open Questions Carried Into Execution

These are decided inside the plan but are the ones most likely to need revisiting
once code exists:

- Whether exact-content-only rename correspondence is too narrow to be useful in
  practice. The plan chooses it deliberately over a similarity heuristic; if real
  use shows it almost never fires, the answer is a stronger *evidence* rule, not
  a guess presented as a fact.
- Whether unit identity should survive a root change, not only a path change. The
  plan scopes identity to one root; multi-root indexing is not in scope and would
  be a `SPEC.md` source-identity question.
- What `publish` costs once a repository-scale tree exists. Stage 4 measures it
  and records it as risk; the plan explicitly does not act on the number.

## Blockers

None for plan creation.

Neither anticipated Stage 1 blocker materialized. `std.Io.Dir.iterate` and
`openDir` with `follow_symlinks = false` were sufficient, and the symlink test
needed no platform scoping beyond skipping itself if the filesystem refuses to
create a link.

Neither anticipated Stage 2 blocker materialized. The `scope` change touched
both frontends and three test filters and nothing else, and the stop condition
did not apply.

The first anticipated Stage 3 blocker dissolved on contact: a path swap is not a
rename under the correspondence rule, so it never needs to be applied as one. The
second stands as a decision rather than a blocker — exact-content moves are
claimed, everything else is a removal and an addition.

Both anticipated Stage 4 blockers were resolved as predicted: large trees are
generated in the tests, and `Graph.unit_work` became the countable proxy for
graph-level work.

Potential Stage 5 blockers:

- The ADR that opens the stage may conclude that recording a repository-wide
  name match as an approximate assertion is incompatible with §1. The stage is
  written to complete either way, but the dependency mechanism alone is a
  thinner result than the stage suggests.
- Invalidation has to override the rule Stage 3 established — that a unit whose
  own content did not change is never re-read. That rule is currently
  unconditional and lives in the registry, which knows nothing about
  dependencies.

## Residual Risk

The plan's largest assumption is that unit identity can be made path-independent
without touching an accepted core definition. `file` is accepted with "Location
is a property, not an identity derived from byte or line position", which reads
as supporting the change rather than blocking it — but if implementation shows
otherwise, the plan's third stop condition applies and the work pauses for a
requirements change rather than proceeding.

## Next Handoff

Start with Stage 5, and start with its ADR rather than with code. The question is
whether recording a repository-wide unique-name match as an **approximate**
assertion is compatible with §1 forbidding an approximate mechanism from
establishing a program relationship, given that §3 provides the approximate
category and requires it to stay distinct from fact. Both answers have a complete
DoD in the plan; the dependency mechanism itself is independent of the outcome
and can be built first.
