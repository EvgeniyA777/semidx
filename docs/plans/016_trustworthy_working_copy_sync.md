---
title: "Trustworthy working-copy synchronization"
doc_type: "plan"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-27"
---

# 016: Trustworthy Working-Copy Synchronization

## Goal

Make the local MCP preview unable to present an internally current but
filesystem-outdated snapshot as ready for code work.

The delivered habit loop begins with one idempotent `semidx_sync`, every graph
read proves that the configured root still matches the published snapshot, and
every response distinguishes snapshot-relative analysis from working-copy
synchronization. The plan also gives each scan a deterministic source-state
identity and makes health compact enough to remain a practical first-line
diagnostic.

## Product Principle

Trust comes before breadth and ranking quality:

1. An explicit unknown or blocked result is better than a plausible stale range.
2. `current` inside a snapshot must never imply that the filesystem was checked.
3. Synchronization must reuse incremental reconciliation, not rebuild by policy.
4. A content-derived identity beats a process-local revision for comparison.
5. Exact preflight may be optimized later, but never replaced by a heuristic
   presented as exact.

## Start Rule

Before Stage 0:

- read `RULES.md`, `ARCHITECTURE_CONSTITUTION.md`, `MEMORY.md`, `SPEC.md`,
  [ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md),
  [proposed ADR 014](../adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md),
  [Follow-up 021](../followups/021_snapshot_revision_is_not_a_content_identity.md),
  the [local MCP reference](../mcp/local_preview.md), and the
  [habit-loop gate](../mcp/habit_loop_gate.md);
- run `./scripts/check-zig-version.sh` and record the exact Zig 0.16.0 result;
- create `docs/reports/016_trustworthy_working_copy_sync_progress.md` with
  standard progress-log frontmatter;
- record current branch, worktree state, product version, snapshot health, and
  the existing tool list; and
- apply the Plan Readiness Gate against the then-current tree.

Stop before source work if ADR 014 remains disputed, if a proposed shortcut can
miss a byte/path/policy change while reporting `in_sync`, or if implementation
requires a watcher, VCS command, persistence layer, remote service, or frontend
semantic change. Revise the decision and plan explicitly before resuming.

## Scope

- Give every successful `SourceScan` a deterministic, process-independent
  source-state identity.
- Pair the MCP server's published snapshot with the identity of the scan that
  produced it.
- Add idempotent `semidx_sync` and keep `semidx_refresh` as a compatibility
  alias over the same behavior.
- Preflight every graph-reading MCP tool against a fresh source discovery scan.
- Fail closed with an actionable `semidx_sync` instruction on mismatch or scan
  failure.
- Prevent optional Jev ranking from making a network attempt on a mismatched or
  unscannable working copy.
- Add compact/default and full health detail with explicit working-copy status.
- Add source-state identity to every normal result envelope without publishing
  a semantic contract.
- Update the agent habit loop, local MCP docs, gates, operational memory, and
  the related follow-up.
- Measure exact-preflight cost as an observation on maintained profiles.

## Non-Scope

- No filesystem watcher, daemon, polling thread, subscription, notification, or
  persistence backend.
- No mtime-, size-, VCS-, or editor-event shortcut may claim exact
  synchronization in this plan.
- No automatic graph publication inside a normal read tool. Reads detect and
  fail; `semidx_sync` performs mutation.
- No stale-snapshot bypass or offline-snapshot mode.
- No source bodies, snippets, resources, `semidx_render_source`, or broader
  `--allow-evidence-text` behavior. Bounded source rendering needs a separate
  consent and output-budget plan under ADR 005.
- No graph kind, relationship, resolution rule, language coverage, frontend,
  semantic identity, storage representation, or public semantic contract.
- No Jev quality evaluation, model change, provider behavior change, release,
  version bump, HTTP transport, or new dependency.
- No promise that the filesystem cannot change after preflight completes. The
  result identifies the source state checked immediately before the graph read.

## Sources Of Truth

- `ARCHITECTURE_CONSTITUTION.md`: §1 graph authority, §3 honest state
  distinctions, §5 incremental maintenance and consistent queries, §7 consumer
  independence, §8 current-working-copy and local-operation requirements, and
  §11 the decision test.
- [ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md): MCP remains a
  local consumer over complete published snapshots.
- [ADR 014](../adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md):
  proposed source-state identity, preflight, fail-closed, sync, and health
  decisions.
- `SPEC.md`: changing snapshot/query requirements and the absence of a public
  semantic contract.
- `MEMORY.md`: current in-memory snapshot, manual refresh, no watcher or
  persistence, and adoption-first priorities.
- [Follow-up 021](../followups/021_snapshot_revision_is_not_a_content_identity.md):
  revision cannot identify content across observations or processes.
- [Product adoption strategy](../design/002_product_adoption_strategy.md): the
  preview must tell an agent what it can trust and whether refresh is needed.
- [Local MCP preview](../mcp/local_preview.md) and
  [habit-loop gate](../mcp/habit_loop_gate.md): current tool behavior and
  executable client workflow.
- [Documentation](../agent-policy/documentation.md),
  [testing](../agent-policy/testing.md), and
  [tooling](../agent-policy/tooling.md) policies.

## Current Evidence And Integration Points

The planning snapshot was revision 102 of product `0.1.0-preview.4`: 77 units,
74 current units, three pending units, 3,444 current facts, 4,630 current
unresolved assertions, and no approximate assertions. Its `last_scan` still
described the initial 77 additions, illustrating that health reports only the
last explicit scan rather than current filesystem agreement.

The observed external-review regression is reproducible in the current design:

1. start a server and publish a snapshot;
2. change source through another process while the server remains alive;
3. call health and map without refresh;
4. observe internally `current` units and old ranges;
5. refresh and observe a changed scan plus corrected ranges.

Relevant ownership boundaries found through semantic exploration:

- `src/source/scan.zig` owns `ScannedUnit`, existing SHA-256 `ContentId`, sorted
  `SourceScan.units`, scan diagnostics, budgets, and pure scan fixtures.
- `src/source/discovery.zig` owns complete bounded filesystem discovery and
  deterministic path/diagnostic ordering.
- `src/root.zig` owns `Index.applyScan` and affected-region reconciliation.
- `src/core/graph.zig` owns immutable `Snapshot` and snapshot-relative
  `pending/current/stale`; those meanings do not change.
- `src/mcp/root.zig` owns server lifetime, the retained `Index`/`Snapshot`,
  refresh recovery, dispatch, and the only filesystem-to-MCP orchestration
  boundary.
- `src/mcp/tools.zig` owns tool definitions, validation, common result envelope,
  health rendering, and annotations. It must remain free of filesystem reads.
- `tests/mcp_smoke_test.zig`, `tests/mcp_gate.zig`,
  `tests/mcp_fixture_gate_test.zig`, and `tests/mcp_dogfood_test.zig` own the real
  stdio and habit-loop proof seams.

Semantic exploration was exact for those definitions but incomplete for some
method-style Zig calls, and one depth-2 Server context exhausted its response
budget. Direct targeted reads are therefore required during execution for
precise member layout and all test call sites.

## Plan Readiness Verdict

**Ready for staged execution, with ADR acceptance intentionally owned by Stage
0.** The behavior, ownership boundaries, order, stop conditions, test levels,
offline constraints, and observable completion criteria are explicit. No stage
depends on a later result. The only decision gate is whether ADR 014 survives
its constitutional review; a dispute stops source work and requires the ADR and
this plan to change together. Exact-preflight cost is an evidence question, not
permission to weaken the trust contract.

## Fixed Runtime Contract

### Result Envelope

Every successful tool result keeps `semantic_contract_version: null` and adds:

```json
{
  "snapshot": {
    "revision": 39,
    "source_state_id": "<64 lowercase hex>"
  },
  "working_copy": {
    "status": "in_sync",
    "observed_source_state_id": "<same 64 lowercase hex>"
  }
}
```

`working_copy.status` is one of `in_sync`, `out_of_date`, or `scan_failed`.
Normal graph reads succeed only with `in_sync`; health may report all three. The
sync response reports the post-operation state as `in_sync`. When status is
`scan_failed`, `observed_source_state_id` is `null`.

Tool errors for out-of-date or failed preflight use the existing MCP tool-error
shape: `isError: true`, one text content item, and no `structuredContent` or
graph payload. The text starts with one stable reason and then includes the
retained revision and source-state identity:

```text
semidx_preflight_out_of_date: working copy differs from the published snapshot; call semidx_sync and retry
semidx_preflight_scan_failed: working-copy scan failed; fix root access, then call semidx_sync and retry
```

The scan-failure text may add a closed, sanitized reason code, but never absolute
paths beyond the configured-root reporting policy, source contents, or raw OS
error context that may contain unrelated paths. Contract tests pin both prefixes,
the absence of structured content, and the retained-state suffix.

### Source-State Identity Encoding

Use one named version marker, `semidx-source-state-v1`, and an unambiguous binary
encoding with fixed-width big-endian lengths/counts before variable byte
strings. Hash, in this order:

1. version marker;
2. discovery budgets;
3. excluded-directory entries in normalized sorted order;
4. unit count, then each already path-sorted unit's path, language tag, and
   32-byte content digest; and
5. diagnostic count, then each already deterministically sorted diagnostic's
   kind, path, and message.

The implementation must not hash serialized JSON, absolute root, graph ids,
revision numbers, timestamps, or pointer/layout bytes. Commit fixed vectors for
empty, one-unit, reordered-input, byte-change, path-change, diagnostic-change,
and policy-change cases.

Because the current `SourceScan` stores budgets but not exclusions, Stage 1 adds
an owned canonical policy field to the scan before calculating the identity.
Diagnostic canonicalization compares path, kind, and message; the current
path/message comparator is insufficient when two kinds share both values.

### Preflight And Sync Ordering

- `semidx_health`: scan, compare, report; never apply or publish.
- Graph read: scan, compare, fail on mismatch/failure, otherwise capture and
  render the already-published snapshot.
- `semidx_sync` and compatibility `semidx_refresh`: scan once; preserve the
  snapshot on an identity match; otherwise apply, publish, pair the new identity,
  and return the new state.
- Cursor continuation: preflight first. A mismatch directs sync; after sync the
  old cursor fails its existing revision binding and the client restarts.
- Jev ranking: preflight before candidate projection or provider invocation.

The server remains sequential under the current stdio loop. If execution finds
that dispatch can overlap calls, stop and add an explicit serialization boundary
before storing or comparing source-state identities.

## Architecture Boundaries

1. **Source-state identity (`src/source/scan.zig`)**
   - Responsibility: deterministic identity of one complete bounded scan.
   - Knows about: scan policy, normalized units, content digests, scan
     diagnostics.
   - Does not know about: graph revisions, MCP, cursors, Jev, filesystem handles.
   - Change contained: identity encoding and version.

2. **MCP sync coordinator (`src/mcp/sync.zig`, new)**
   - Responsibility: run discovery, compare retained/observed identities,
     coordinate idempotent apply/publish, and translate failure state.
   - Knows about: configured root, discovery, `Index`, published `Snapshot`,
     refresh recovery hooks.
   - Does not know about: tool JSON schemas, frontend semantics, ranking scores,
     source rendering.
   - Change contained: preflight and synchronization policy.

3. **MCP presentation (`src/mcp/root.zig`, `src/mcp/tools.zig`)**
   - Responsibility: dispatch preflight, tool authorization, result envelope,
     compact/full health, actionable errors.
   - Knows about: coordinator outcomes and immutable snapshot.
   - Does not know about: how identities are encoded or scans are reconciled.
   - Change contained: experimental MCP surface and habit-loop UX.

4. **Existing graph/frontends**
   - Responsibility: semantic authority, incremental reconciliation, immutable
     snapshots, analysis state, provenance.
   - Knows about working-copy policy: nothing.
   - Change contained: none. A requested core semantic or frontend change is a
     scope violation.

## Dependency Direction

```text
source discovery -> SourceScan/source-state identity
                         |
                         v
                 MCP sync coordinator -> Index.applyScan -> Snapshot
                         |
                         v
                 MCP dispatch and rendering
                         |
                         +-> optional ranking only after in-sync preflight
```

The coordinator depends on the existing source and index APIs. Core graph and
frontends never depend on MCP, working-copy status, or tool schemas. Tests may
inject a deterministic scan function into the coordinator; this is the one
justified seam because failure and change sequences otherwise require real
filesystem races.

## Implementation Stages

### Stage 0: Accept The Trust Contract And Freeze Fixtures

Purpose: make the product behavior explicit before adding hashes or I/O to the
read path.

Required work:

- Create the progress log and record readiness evidence.
- Review ADR 014 against all eight constitutional questions. Accept it unchanged
  or revise the ADR and this plan together.
- Update `SPEC.md` with separate snapshot-analysis and working-copy-sync axes,
  the fail-closed MCP requirement, source-state identity meaning, and the fact
  that no semantic contract is published.
- Add the accepted terms to `GLOSSARY.md`; do not redefine constitutional terms.
- Commit a synthetic nine-unit regression fixture or gate setup that reproduces
  the observed sequence without using the external repository or its source.
- Freeze identity vectors and compact/full health examples before source code
  depends on them.
- Measure the existing complete discovery scan on the repository-copy and
  fixture profiles as a baseline observation.

Stop rule: stop if accepted behavior permits a graph read after mismatch or scan
failure, or if source-state identity is asked to identify semantic assertions
rather than source discovery input.

Done when: ADR 014 is accepted, SPEC and glossary own the contract vocabulary,
fixtures/examples are committed, and the progress log records a passing
readiness review.

Verification: documentation drift review, fixture parse checks, identity-vector
format review, `./scripts/check-zig-version.sh`.

### Stage 1: Deterministic Source-State Identity

Purpose: build the pure comparison primitive before changing MCP behavior.

Likely files:

- `src/source/scan.zig`, `src/source/root.zig`
- focused unit tests colocated with the scan implementation

Required behavior:

- Implement the versioned SHA-256 encoding exactly once in `src/source/`.
- Extend `SourceScan` with an owned, normalized representation of the effective
  exclusion policy; do not read mutable caller options after discovery returns.
- Calculate it from a complete `SourceScan` after units and diagnostics are in
  deterministic order.
- Canonically order diagnostics by path, kind, then message before hashing.
- Render and parse only lowercase 64-character hex at the MCP boundary; internal
  comparison remains fixed-size bytes.
- Prove input order cannot change the identity and every named input category
  can.
- Do not alter per-unit `ContentId`, registry correspondence, graph identity, or
  analyzer behavior.

Done when: the fixed vectors pass, two independently built equivalent scans
match, and source discovery behavior is otherwise unchanged.

Verification: `zig fmt --check build.zig src tests`,
`zig build test-core --summary all`, and
`zig build test-core -Dgrammars-dir=/nonexistent --summary all`.

### Stage 2: Idempotent Sync Coordinator

Purpose: centralize scan/compare/apply/publish behavior without duplicating
refresh recovery.

Likely files:

- new `src/mcp/sync.zig`
- `src/mcp/root.zig`, `src/mcp/tools.zig`
- focused MCP unit tests

Required behavior:

- Store the identity paired with the currently published snapshot.
- Add `semidx_sync` to discovery and dispatch.
- Make unchanged sync preserve revision, entity ids, cursor validity, graph
  counts, last applied scan outcome, and Jev capability state.
- Make changed sync reuse `Index.applyScan`, atomic publication, and the current
  failed-refresh rebuild path.
- Make `semidx_refresh` delegate to the same coordinator and preserve its
  existing response fields while adding `changed` and source-state fields.
- On every failure, retain the previous snapshot/identity pair and report which
  state remains published.

Done when: sync is idempotent on unchanged input, changed input publishes once,
and every existing refresh recovery injection still converges.

Verification: `zig fmt --check build.zig src tests`, `zig build test-core`,
`zig build test-mcp`.

### Stage 3: Fail-Closed Read Preflight

Purpose: make the Warehouse failure mode impossible through the MCP read tools.

Likely files:

- `src/mcp/sync.zig`, `src/mcp/root.zig`, `src/mcp/tools.zig`
- focused MCP tests and stdio smoke fixtures

Required behavior:

- Run exact discovery preflight before every graph-reading tool named by ADR
  014 D4.
- Return an actionable tool error and no graph data for mismatch or scan
  failure.
- Keep health callable in every state and make it report rather than repair.
- Add retained and observed identities/status to normal result envelopes.
- Ensure a failed preflight does not invalidate cursors, change revision, mutate
  graph counts, or call Jev.
- Prove a sync followed by retry returns corrected ranges from the new revision.
- Prove parser failure after sync reports graph analysis `stale` separately from
  working-copy `in_sync`.

Done when: the synthetic external-edit regression fails closed before stale
ranges can be rendered and succeeds only after sync.

Verification: `zig fmt --check build.zig src tests`, `zig build test-mcp`,
`zig build dogfood`.

### Stage 4: Compact Health And Sequential Habit Loop

Purpose: make the safe path cheaper and obvious to agents.

Likely files:

- `src/mcp/tools.zig`, `src/mcp/root.zig`
- `tests/mcp_smoke_test.zig`, gate tests
- `docs/mcp/local_preview.md`, `docs/mcp/habit_loop_gate.md`
- `.agents/skills/semidx-code-exploration/SKILL.md`
- root `README.md` only if its public quickstart currently copies the changed
  first-call sequence

Required behavior:

- Add `detail: "compact" | "full"` to health, default compact.
- Keep parser availability, trust state, recovery, counts, and redacted enabled
  capabilities in compact output; move verbose coverage notes and full graph
  counts to full detail.
- Change first-call documentation to `semidx_sync`, then health only when a
  diagnostic summary is needed, then outline/map/context.
- State that sync and later graph reads are dependent calls and must not be
  launched in parallel.
- Update tool descriptions so `current` says snapshot-relative analysis and
  source-state fields say what was checked.
- Keep all normal output under existing response budgets.

Done when: a fresh agent can follow the documented sequence without inferring
working-copy state from `current`, and compact health is materially smaller than
full health on the repository-copy profile.

Verification: `zig build test-mcp`, `zig build dogfood`, documentation guards,
and transcript-byte observations for compact/full health.

### Stage 5: Habit-Loop Gate And External-Cost Evidence

Purpose: make trust behavior a permanent regression gate and expose its cost.

Required work:

- Change both maintained gate profiles to start with sync.
- Add hard gates for deterministic source-state identity, unchanged-sync
  revision stability, external-edit detection, graph-read refusal, corrected
  post-sync ranges, scan-failure refusal, parser-failure axis separation, cursor
  restart, and zero Jev calls on mismatch.
- Add branch-switch-shaped remove/add/change coverage in a temporary root.
- Record discovery/preflight elapsed time and bytes read, when available, as
  observations rather than machine-dependent hard gates.
- Run one privacy-safe real-task evaluation on an external repository and record
  whether stale graph data escaped, how many manual reads remained, and how many
  extra tool round trips sync required. Do not commit repository source or
  machine-specific absolute paths.

Stop rule: if exact preflight makes repeated MCP reads unusable at measured
scale, do not weaken it to metadata equality. Keep the fail-closed contract and
prepare a separate watcher/cache optimization plan whose final authority is the
same content identity.

Done when: the canonical preview gate reproduces and prevents the original
failure mode, and preflight cost is recorded honestly.

Verification: `zig build preview-gate --summary all` plus the privacy-safe
real-task evidence record.

### Stage 6: Canon, Review, And Closure

Purpose: align every owner with delivered behavior and remove stale workflow
language.

Required work:

- Run a findings-first review of source-state identity, failure retention,
  preflight ordering, cursor behavior, Jev blocking, and all error payloads.
- Run drift control across the constitution, accepted ADRs, `SPEC.md`,
  `CONFORMANCE.md`, `GLOSSARY.md`, `MEMORY.md`, MCP docs, skills, implementation,
  tests, and gates.
- Mark Follow-up 021 fixed only if source-state identity is present beside
  revision in every normal MCP result and cross-process vectors pass.
- Update `MEMORY.md` with actual runtime behavior and measured cost.
- Mark ADR 014 accepted, this plan completed, and the progress log historical
  only after every Definition of Done item passes.
- Do not publish a release or claim stable MCP/semantic contracts.

Verification: `./scripts/check-zig-version.sh`,
`zig fmt --check build.zig src tests`, `zig build test-core --summary all`,
`zig build test --summary all`, `zig build test-mcp`, `zig build dogfood`,
`zig build preview-gate --summary all`, and repository documentation guards.

## Risk Matrix

| Guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Source identity is deterministic | Equivalent scans disagree across order/process | Pure unit vectors | Versioned binary encoding over sorted values | Reordered units/diagnostics, empty scan, two processes | Stage 1 vectors |
| Every visible source change changes identity | A stale snapshot compares equal | Pure unit and discovery fixture | Path, language, bytes, diagnostics, policy each affect hash | Same-size edit, rename, add/remove, diagnostic-only change | Stages 1 and 5 |
| Analysis and sync remain separate | `current` again implies disk agreement | MCP contract test | Both fields appear with independent meanings | Current snapshot plus changed working copy; stale analysis after successful sync | Stages 3-4 |
| Unchanged sync is idempotent | A no-op invalidates ids/cursors and adds revisions | MCP integration | Same identity skips apply/publish | Repeated sync, refresh alias, enabled Jev capability | Stage 2 |
| Changed sync stays incremental | Product falls back to full graph rebuild | Integration plus scan outcome | Existing `Index.applyScan` path and preserved ids | Edit, rename, remove/add batch, dependency invalidation | Stages 2 and 5 |
| Graph reads fail closed | Old paths/ranges escape after external edit | MCP integration and stdio smoke | Preflight precedes snapshot rendering | Mismatch, scan failure, direct call without prior sync | Stage 3 regression |
| Health never repairs silently | A diagnostic call mutates graph state | MCP integration | Same revision/counts before and after health | Out-of-date and scan-failed roots | Stage 3 |
| Failure retains a paired state | Snapshot and identity describe different scans | Failure-injection integration | Atomic replacement after apply/publish success only | Scan/apply/publish allocation failure | Stages 2-3 recovery tests |
| Cursor safety survives sync | Pagination mixes revisions | MCP cursor test | Mismatch blocks, sync changes revision, old cursor fails | Edit between cursor pages | Stages 3 and 5 |
| Ranking never uses stale candidates | External call leaks obsolete metadata | Fake-provider integration | Preflight before projection/provider | Mismatch and scan failure with enabled fake provider | Stage 3 |
| Compact health remains actionable | Smaller output hides parser or trust failure | Contract and gate comparison | Required compact key set plus full superset | Parser unavailable, recovery pending, outbound capability enabled | Stage 4 |
| Required lanes remain local | Freshness feature adds service/VCS dependency | Full offline gates | Discovery uses configured local root only | No Git repository, no network, no watcher | Stages 1-6 |
| Exact preflight cost is visible | Trust fix makes tool slower without evidence | Runtime observation | Per-call scan timing in gate summary | Repository-copy and named external profile | Stage 5 |

## Definition Of Done

- ADR 014 is accepted and `SPEC.md`/`GLOSSARY.md` own the delivered vocabulary
  without changing the frozen constitution.
- A deterministic source-state identity covers scan policy, units, contents,
  and discovery diagnostics and is stable across equivalent processes.
- Every normal MCP result carries process-local revision and comparable
  source-state identity without publishing a semantic contract.
- `semidx_sync` is the documented first call; unchanged sync preserves revision,
  ids, and cursors, while changed sync uses incremental reconciliation and
  publishes exactly once.
- `semidx_refresh` remains a compatible idempotent alias during the preview.
- Health distinguishes `in_sync`, `out_of_date`, and `scan_failed` and does not
  mutate the graph.
- Every graph-reading tool fails before rendering graph data on mismatch or scan
  failure and names `semidx_sync` as the next action.
- A fake enabled Jev provider receives zero calls when preflight is not
  `in_sync`.
- Parser failure after a successful sync remains visible as stale/pending
  analysis rather than being confused with working-copy mismatch.
- The Warehouse-shaped external-edit regression, branch-switch batch, scan
  failure, no-op sync, changed sync, cursor restart, and recovery paths are hard
  gate evidence.
- Compact health is smaller than full health while retaining every trust and
  parser signal required by the habit loop.
- Required verification stays offline and credential-free; exact preflight cost
  is recorded as an observation rather than hidden or weakened.
- Watchers, persistence, source rendering, stale bypass, release/version work,
  and public semantic contracts remain outside this plan.
- Implementation, docs, skills, ADR, follow-up status, plan, progress log, and
  `MEMORY.md` agree, and every coherent stage is committed.
