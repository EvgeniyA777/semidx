# ADR-024: Make Compact-First Staged Retrieval the Canonical Public Flow

**Status**: Accepted  
**Date**: 2026-03-10  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-002` established the bounded `context packet` contract.  
`ADR-006` established late raw-code fetch.  
`ADR-016` established canonical examples as part of the architecture reference layer.  
`ADR-018` established thin runtime edges over the same library behavior.

The runtime has already converged on staged retrieval behavior:

- `resolve_context` is a compact selection stage, not the rich detail payload;
- `expand_context` and `fetch_context_detail` already exist across library, HTTP, gRPC, and MCP;
- `selection_id` artifacts already bridge stages;
- snapshot mismatch, eviction, and API-version errors are already explicit runtime behavior.

Without a dedicated ADR, the repo still has a governance gap:

- docs can drift back toward "single-call rich retrieval" language;
- examples can under-document staged usage even though runtime behavior is already staged;
- clients may silently re-resolve on a newer snapshot and lose explainability;
- internal convenience helpers can be mistaken for the canonical external path.

We need to decide what the canonical public retrieval flow is, how stage transitions remain stable, and what docs/examples must treat as normative.

---

## Decision Drivers

- Compact default token cost
- Snapshot-bound correctness and explainability
- Stable stage-to-stage behavior across library and runtime edges
- Explicit failure modes instead of silent drift
- Idempotent detail fetch while a selection artifact is retained
- Clear documentation and example governance

---

## Considered Options

### Option 1. Keep a single-call rich retrieval flow as the main public story

Treat `resolve_context` as conceptually equivalent to the old rich payload, even if implementation internally stages work.

### Option 2. Make compact-first staged retrieval the canonical public flow

Treat `resolve_context -> expand_context -> fetch_context_detail` as the primary contract line and document the selection artifact boundary explicitly.

### Option 3. Allow later stages to silently re-resolve against the latest snapshot

Optimize for convenience by allowing selection handles to drift to a newer snapshot when the repo or index changes.

---

## Decision

We accept **Option 2: compact-first staged retrieval is the canonical public flow**.

The intended public retrieval line is:

1. `resolve_context`
2. optional `expand_context`
3. optional `fetch_context_detail`

`resolve_context` is the compact hot path.  
`expand_context` is the bounded structural expansion path.  
`fetch_context_detail` is the rich detail path with optional late raw-code escalation.

Internal convenience helpers may still exist, but they do not replace this canonical public contract.

---

## Canonical Stage Semantics

### `resolve_context`

Must return a compact selection artifact bound to:

- `selection_id`
- `snapshot_id`
- selected focus units
- bounded budget summary
- `next_step`

It must not silently behave like the rich detail endpoint.

### `expand_context`

Must reuse the exact prior selection artifact and return bounded structural expansion only, such as:

- skeletons
- optional impact hints
- stage budget summary

### `fetch_context_detail`

Must reuse the exact prior selection artifact and return the rich detail layer, including:

- `context_packet`
- `guardrail_assessment`
- `diagnostics_trace`
- `stage_events`
- optional bounded raw context

---

## Selection Stability Rules

Selection artifacts are part of the public contract, not just an internal cache detail.

### Required rules

- A `selection_id` is bound to the exact `snapshot_id` from which it was created.
- Later stages must validate both `selection_id` and `snapshot_id`.
- Later stages must not silently re-resolve against a newer snapshot.
- Missing, evicted, or snapshot-mismatched selection artifacts must return explicit typed errors.

### Error expectations

Canonical error paths for staged retrieval include:

- `selection_not_found`
- `selection_evicted`
- `snapshot_mismatch`
- `unsupported_api_version`

These errors must remain aligned across library, HTTP, gRPC, and MCP surfaces.

---

## Idempotency Rule

While a retained selection artifact exists, repeated `fetch_context_detail` calls with the same:

- `selection_id`
- `snapshot_id`
- `detail_level`
- `unit_ids`

must produce an identical detail result.

If the selection artifact is later evicted, the system must fail explicitly rather than silently rebuilding a different result.

---

## Documentation and Example Governance

Repository reference materials must treat staged retrieval as normative.

### Required behavior

- `README` must describe staged retrieval as the default public path.
- runtime and MCP docs must document `resolve_context`, `expand_context`, and `fetch_context_detail` in staged order.
- canonical examples and catalogs must include staged-flow references where that flow is part of the intended semantics.
- convenience helpers such as `resolve-context-detail` must be labeled as convenience APIs, not the primary public story.

This rule follows `ADR-016`: prose, schemas, and examples must agree on the intended contract shape.

---

## Consequences

### Positive

- Public docs now match the shipped runtime contract.
- Clients get a cheaper default path for large repositories.
- Snapshot drift becomes visible instead of implicit.
- Rich detail fetches become easier to reason about and cache safely.

### Negative

- Integrations must retain `selection_id` and `snapshot_id` between calls.
- Documentation and examples now need to describe a multi-step flow instead of a single response shape.
- Selection-artifact retention/eviction semantics remain part of the operational contract surface.

---

## Definition of Done

This decision is correctly implemented when all of the following are true:

1. The canonical public flow is documented as `resolve_context -> expand_context -> fetch_context_detail`.
2. Selection artifacts are described as snapshot-bound and explicitly evictable.
3. Cross-surface docs call out `selection_not_found`, `selection_evicted`, `snapshot_mismatch`, and `unsupported_api_version`.
4. Canonical examples/catalog metadata no longer imply that rich detail is the default `resolve_context` result.
