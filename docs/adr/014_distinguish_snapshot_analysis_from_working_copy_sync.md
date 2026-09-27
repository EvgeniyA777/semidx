---
title: "Distinguish snapshot analysis from working-copy synchronization"
doc_type: "adr"
lifecycle: "active"
status: "proposed"
agent_action: "reference_for_context"
updated: "2026-09-27"
---

# 014: Distinguish Snapshot Analysis From Working-Copy Synchronization

## Feature Or Dependency

The MCP preview reports source units and claims as `current` when their analysis
matches the contents held by the published in-memory snapshot. It does not watch
the filesystem and does not compare that snapshot with the configured root until
`semidx_refresh` is called.

That distinction is correct inside the graph but unsafe at the product surface.
A long-lived MCP process can keep an internally current snapshot after another
process, branch switch, commit, or editor changes the working copy. A consumer
then sees `current` beside paths and ranges that no longer describe the files on
disk.

This happened in a real external Java review on 2026-09-27. Snapshot revision 18
reported all nine units current while two classes still had their earlier line
ranges. The first explicit refresh advanced revision 18 to 39, reported all nine
units changed, and corrected the ranges. The parser had not produced false
ranges; the consumer had mistaken snapshot-relative freshness for filesystem
synchronization.

This decision defines a separate source-state identity and a fail-closed MCP
synchronization boundary. Its implementation plan is
[016: Trustworthy Working-Copy Synchronization](../plans/016_trustworthy_working_copy_sync.md).

## Decision

### D1: Analysis State And Working-Copy State Are Separate Axes

`pending`, `current`, and `stale` keep their existing graph meaning. They answer
whether a unit's claims were successfully analyzed against the contents stored
in one published snapshot. They do not claim that the configured root still has
those contents.

The MCP preview adds a separate working-copy status:

- `in_sync`: a complete source discovery immediately preceding the result has
  the same source-state identity as the published snapshot;
- `out_of_date`: discovery succeeded and produced a different identity;
- `scan_failed`: discovery could not establish the current source state.

No result may translate `current` into working-copy synchronization. User-facing
documentation must call it snapshot-relative analysis state when the distinction
matters.

### D2: A Source-State Identity Names What Discovery Observed

Each successful `SourceScan` receives a deterministic SHA-256 identity over the
semidx-visible source state. The encoding is versioned and includes:

- the discovery budgets and excluded-directory policy that bound the scan;
- every scanned unit, in normalized path order, as a length-prefixed path,
  language tag, and existing 32-byte content digest; and
- every scan diagnostic, in deterministic order, as kind plus length-prefixed
  path and message.

`SourceScan` therefore retains an owned, normalized copy of every identity input,
including the effective excluded-directory policy. Diagnostic ordering compares
path, kind, and message so equal paths never fall back to directory iteration
order.

The absolute root path, allocation ids, graph ids, graph revision, timestamps,
frontend results, and host directory iteration order are excluded. Two processes
using the same scan policy over the same visible source state therefore produce
the same identity. A path, language, byte, diagnostic, or scan-policy change
changes it.

The identity is rendered as 64 lowercase hexadecimal characters. It identifies
source discovery input, not graph semantics: the same identity under another
producer version may still yield different assertions. Snapshot revision keeps
its existing process-local ordering meaning and is never replaced by the
identity.

### D3: Synchronization Is Explicit And Idempotent

Add `semidx_sync` as the recommended first MCP call. It performs one complete
discovery scan and compares source-state identities.

- If the identities match and recovery is not pending, it keeps the current
  snapshot and revision.
- If they differ, it reconciles the scan through the existing `Index.applyScan`
  path and atomically publishes the next snapshot.
- If scanning, reconciliation, or publication fails, the previously published
  snapshot and its identity remain paired and visible as the retained state.

`semidx_refresh` remains available during the preview as a compatibility alias
for the same idempotent operation. It must not bypass the identity comparison or
publish a new revision for unchanged input.

### D4: Graph Reads Use A Fail-Closed Preflight

Before serving `semidx_outline`, `semidx_repo_map`,
`semidx_find_definitions`, `semidx_references`, `semidx_context`, or
`semidx_rank_context`, the server performs source discovery and compares its
identity with the published snapshot.

- A match permits the read and records `working_copy.status = "in_sync"`.
- A mismatch returns a tool error naming `semidx_sync` as the next action and
  renders no graph answer from the older snapshot.
- A scan failure returns a tool error and does not silently fall back to the
  snapshot.
- `semidx_rank_context` performs no provider call when the preflight does not
  match.

There is no `allow_stale_snapshot` bypass in the first slice. A later explicit
offline-snapshot mode would require its own decision because it changes the
preview's trust contract.

Preflight establishes equality at the completion of its scan. It does not lock
the repository against a write that begins afterwards; the response identifies
the exact source state it checked so this race is visible rather than hidden.

### D5: Health Reports; It Does Not Repair

`semidx_health` performs the same read-only source-state preflight but never
publishes. It always returns the retained snapshot identity and, when discovery
succeeds, the observed working-copy identity and comparison status. A scan
failure is reported as `scan_failed` without discarding the retained snapshot.

Health becomes compact by default. It retains root, product/server identity,
snapshot revision and source-state identity, working-copy status, unit and
diagnostic counts, parser availability, recovery state, and redacted outbound
capability status. `detail: "full"` adds graph counts, producer/capability notes,
extensions, and the full last-scan outcome. Compact health must not remove the
information an agent needs to decide whether it can trust the next call.

### D6: Responsibilities Stay Separated

- `src/source/` owns deterministic source-state identity because discovery
  already owns normalized, bounded scans.
- A narrow MCP sync coordinator owns probing, comparison, idempotent apply and
  publish orchestration, retained identity, and error translation.
- `src/mcp/tools.zig` owns schemas and rendering but performs no filesystem I/O.
- `Graph`, language frontends, semantic resolution, entity identity, and
  assertion provenance do not depend on MCP or working-copy policy.

The first implementation uses the existing complete discovery scan as the exact
probe. A watcher or metadata cache may later accelerate detection only if a
content-identity comparison remains the authority before an answer is labelled
`in_sync`.

## Rationale

The product is positioned as exact when it knows and honest when it does not.
Returning an old but internally consistent snapshot is compatible with snapshot
isolation, but labelling its claims `current` without separately stating that
the filesystem was never checked is not an honest user experience.

An explicit sync tool reduces agent reasoning to one operation, while a
fail-closed preflight protects clients that skip the documented habit loop. A
complete scan is deliberately chosen before watcher or metadata optimization:
trust is the feature being repaired, and an optimization may not weaken the
comparison into a heuristic presented as exact.

Keeping source-state identity outside graph meaning prevents filesystem policy
from defining semantic entities or relationships. Keeping `revision` alongside
the identity preserves cheap ordering inside one process while finally giving
consumers a value they can compare across processes.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Preserved. Synchronization chooses
   which complete graph snapshot may answer; it establishes no relationship.
2. **Nodes as entities, not chunks.** Preserved. Source-state identity is scan
   metadata and creates no graph node.
3. **Facts, unresolved, and approximate stay distinct.** Strengthened at the
   surface. Snapshot-relative analysis and working-copy synchronization are no
   longer collapsed into one `current` label.
4. **Stable semantic identity.** Preserved. Existing reconciliation remains the
   only edit and correspondence path; scan hashes are evidence, not entity ids.
5. **Incrementality and consistent observation.** Preserved. Changed scans use
   `Index.applyScan`, and a query observes one atomically published snapshot.
6. **Language frontends preserve meaning.** Preserved. No frontend rule,
   coverage claim, core kind, or extension mapping changes.
7. **Consumers do not define the model.** Preserved. MCP owns only trust and
   presentation policy around graph snapshots.
8. **Local operation without mandatory transmission.** Preserved. Discovery,
   comparison, synchronization, and results remain local and network-free;
   optional ranking is blocked before any outbound call when source state does
   not match.

## Consequences

- The normal first call changes from health-only inspection to idempotent sync.
- Read tools pay for exact source discovery before answering. This latency and
  I/O cost must be measured on repository-copy, fixture, and named external
  profiles before release claims; it is not hidden behind a heuristic.
- A working copy changed by an editor, branch switch, commit, or another agent
  cannot silently receive old graph ranges through the MCP read tools.
- Existing cursors remain snapshot-bound. If preflight finds a change, the
  client syncs and restarts pagination without the old cursor.
- `semidx_refresh` stays temporarily for compatibility but no longer advances a
  revision on an unchanged scan.
- File watching, persistence, daemon operation, and source-body rendering remain
  separate product decisions.

## Terminology Ownership

This ADR owns the proposed preview terms **source-state identity**,
**working-copy status**, and **sync preflight** until Stage 0 of Plan 016 accepts
the decision and moves stable user-facing vocabulary into `GLOSSARY.md` and
`SPEC.md`.

## Planned Verification

Plan 016 must prove at least:

- identical scans across two processes yield the same source-state identity;
- one changed byte, path, language, diagnostic, budget, or exclusion policy
  changes the identity;
- an unchanged `semidx_sync` preserves snapshot revision and entity ids;
- an external edit makes health report `out_of_date` and every graph read fail
  before rendering stale ranges;
- sync after that edit publishes one new snapshot and restores graph reads;
- parser failure after an edit remains distinguishable from working-copy sync;
- scan failure retains the previous snapshot but blocks graph reads;
- a branch-switch-shaped remove/add/change batch is detected;
- Jev is never called for an out-of-date or unscannable working copy;
- cursor continuation cannot cross a sync; and
- the full credential-free test and habit-loop gates remain local and offline.
