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

Stages 1 and 2 are implemented and verified. Discovery walks a root, and a unit's
identity no longer depends on where it is found, so a rename preserves everything
inside the renamed file. Nothing reconciles a rescan yet: the registry has the
primitives, but deciding what changed between two scans is Stage 3.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Plan creation | Completed | Created the staged plan and this log. Gate applied; findings below. |
| Stage 1: Source discovery | Completed | `src/source/{root,languages,scan,discovery}.zig`, the `semidx_source` module, `Index.addScan`, and a developer command that takes a root. |
| Stage 2: Unit identity independent of path | Completed | `model.Scope`, unit tombstones, `setSourceUnitPath`, `removeSourceUnit`, and both frontends scoping entities to the unit. |
| Stage 3: Scan reconciliation | Not started | Awaiting Stage 2. |
| Stage 4: Affected-region proof at scale | Not started | Awaiting Stage 3. |
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

Potential Stage 3 blockers:

- A scan that swaps two units' paths cannot be applied as two renames in either
  order, because a move onto an occupied path is rejected. Reconciliation has to
  order removals before renames, or stage the moves.
- Rename correspondence is exact-content only by decision. If a rescan of a real
  tree shows it almost never fires, the answer is a stronger evidence rule, not a
  similarity guess presented as a fact.

## Residual Risk

The plan's largest assumption is that unit identity can be made path-independent
without touching an accepted core definition. `file` is accepted with "Location
is a property, not an identity derived from byte or line position", which reads
as supporting the change rather than blocking it — but if implementation shows
otherwise, the plan's third stop condition applies and the work pauses for a
requirements change rather than proceeding.

## Next Handoff

Start with Stage 3: scan reconciliation. Both halves it needs now exist —
discovery produces content identity, and the registry can rename and remove
units without breaking what is inside them. Stage 3 decides which of unchanged,
changed, added, removed, or renamed applies to each unit between two scans, and
counts frontend invocations so "only the affected region was reanalyzed" is
measured rather than asserted.
