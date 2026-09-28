---
title: "A snapshot revision is not a content identity"
doc_type: "follow_up"
lifecycle: "completed"
status: "fixed"
agent_action: "historical_reference_only"
updated: "2026-09-27"
---

# A Snapshot Revision Is Not A Content Identity

## Classification

`process_defect`

## Source

Observed while a `v0.1.0-preview.4` preview user reviewed an external Java
repository and quoted "snapshot revision 18" as the state two separate
observations shared. It is the same failure as
[Follow-up 017](017_plan_012_external_evidence_reproducibility.md) — evidence
that cannot be tied back to what produced it — one layer closer to the product
surface, where a consumer rather than a plan author draws the conclusion.

## Current Behavior

`Snapshot.revision` counts a running server's own refreshes. It starts from the
index that server built at startup and advances when `semidx_refresh` rebuilds
it. Every tool result carries it under `snapshot.revision`, and nothing in the
payload says anything about the content that was indexed.

So the number supports one comparison and no others. Two results from the same
running server carrying the same revision did see the same index. Beyond that it
says nothing: two servers over different roots both publish revision 18, and the
same repository re-indexed after a restart publishes a low revision again. A
consumer treating it as a state identifier gets a false confirmation, and the
result reads as evidence because the field is right next to resolution and
freshness, which are load-bearing.

`semidx_health`'s tool description now states what the revision orders and what
it does not identify. That removes the invitation; it does not give a consumer
anything to compare instead.

## Why Deferred

A content identity is a snapshot representation question, and `MEMORY.md`
records storage and snapshot representation as SPEC-owned and unresolved: any
persistence design changes the current snapshot story, and an identity chosen
before that is an identity chosen twice. Publishing one in the MCP payload also
widens what the preview promises, and the preview is a consumer rather than a
contract.

The cheap half — saying what the number means where a consumer reads it — did
not need to wait and is done.

[ADR 014](../adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md)
and [Plan 016](../plans/016_trustworthy_working_copy_sync.md) delivered the
intermediate source-state identity and working-copy trust boundary this
follow-up asked for as an acceptable narrow step before persistence.

## Resolution

`src/source/identity.zig` (Plan 016 Stage 1) implements
`semidx-source-state-v1`, published beside `snapshot.revision` in every normal
MCP result since Stage 3 (`src/mcp/tools.zig`'s `beginStructured`, shared by
all nine tools). Every required test above is proven:

- two servers over different roots can publish the same revision, and a test
  says so (`tests/mcp_smoke_test.zig`, "two servers over different roots can
  publish the same revision, distinguished only by source_state_id");
- a server restarted over unchanged content does not resume the revision it
  had before (`tests/mcp_smoke_test.zig`, "a server restarted over unchanged
  content does not resume the revision it had before");
- the same content indexed by two servers yields the same identity
  (`tests/mcp_smoke_test.zig`, "two independent server processes over the
  same content report the same source_state_id"), and a single edited byte
  changes it (`src/source/identity.zig`'s own unit tests, Plan 016 Stage 1);
- the identity appears in results alongside the revision, and the revision
  keeps its ordering meaning (every tool result's `snapshot` object; ADR 014
  D2, unchanged).

`semidx_health`'s description and `local_preview.md` now describe
`source_state_id` as the cross-process comparison, with `revision` kept for
its original process-local ordering role only.

## Acceptance Direction

When snapshot representation is decided, publish an identity derived from the
indexed content next to the revision, so two observations can be compared
without knowing which process produced them. Until then, no consumer-facing
document, report, or release note may present a revision as evidence that two
observations saw the same indexed state.

If an intermediate step is wanted before persistence lands, the narrow one is an
identity over the scanned source units and their contents, published alongside
the revision and never replacing it: the revision keeps ordering a server's
snapshots, and the identity answers whether two of them hold the same source.

## Required Tests

- Two servers over different roots can publish the same revision, and a test
  says so rather than leaving it to be discovered.
- A server restarted over unchanged content does not resume the revision it had
  before.
- When an identity exists: the same content indexed by two servers yields the
  same identity, and a single edited byte changes it.
- When an identity exists: it appears in results alongside the revision, and the
  revision keeps its current ordering meaning.
