---
title: "Constitution distillation"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-13"
---

# Constitution Distillation

## Context

The DRAFT constitution had become logically stronger after pre-ratification
reviews, but it was carrying four responsibilities at once:

1. immutable product identity;
2. architectural rationale;
3. engineering policy;
4. conformance specification.

The combination of detailed invariants, detection mechanics, and a no-amendment
ratification rule made the cost of one bad mechanism too high. The issue was
not that `semidx` itself was overdesigned. The protected core remains the
semantic graph, stable identity, provenance and resolution, incrementality,
exact versus approximate separation, language frontends, consumer independence,
and local operation.

The issue was that too much good engineering material had been placed under the
same future freeze as the product identity.

## Decision

Distill [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md) to
the identity of the project and move detailed supporting material into
changeable companion documents:

* [ARCHITECTURE_RATIONALE.md](../../ARCHITECTURE_RATIONALE.md) explains why the
  constitutional constraints exist.
* [SPEC.md](../../SPEC.md) owns changing requirements and semantic contract
  lifecycle.
* [CORE.md](../../CORE.md) owns core-kind candidates, definitions, and admission
  evidence.
* [CONFORMANCE.md](../../CONFORMANCE.md) owns reviewable and executable scenario
  families.
* ADRs record durable decisions and their reasoning.

The constitution keeps:

* semantic graph as the product and source of truth;
* entity nodes rather than retrieval chunks;
* facts, partially resolved assertions, and approximate assertions as distinct
  attributed knowledge;
* stable semantic identity across edits;
* incremental maintenance and consistent observation;
* language-specific meaning preserved while contributing to a common core;
* consumers and projections downstream of the model;
* local operation with source-data transmission disabled by default and
  explicit opt-in required.

The constitution no longer freezes:

* the core roster;
* conformance fixture mechanics;
* detection procedures;
* fingerprint, revision, epoch, transaction, or storage mechanisms;
* delivery order;
* ADR procedure details;
* schema fields or public API shapes.

## Rationale

The right constitutional test is not "is this important?" It is "would losing
this make the project a different product?"

Many removed details are still important. They belong in requirements and
conformance because they protect quality, compatibility, and reviewability.
They should be strict enough to block releases, but changeable enough to improve
when a better mechanism proves the same semantic property.

This makes the no-amendment rule stronger rather than weaker. A small
constitution can be frozen honestly because it contains only the project
identity. A large constitution creates pressure to reinterpret or ignore clauses
when a mechanism ages badly.

## Architectural Decision Test

Answers correspond to constitution section 11.

1. **Semantic graph as source of truth:** preserved. The graph remains the
   product and authority for semantic answers.
2. **Entity nodes:** preserved. The constitution still forbids chunk nodes.
3. **Knowledge categories:** preserved. The categories remain constitutional;
   concrete encodings move to requirements.
4. **Stable identity:** preserved. Identity correspondence remains protected;
   algorithms and evidence formats move to requirements and conformance.
5. **Incrementality and consistency:** preserved. The semantic property remains;
   snapshot, revision, and invalidation mechanics move out.
6. **Language meaning and common core:** preserved. The core/extension boundary
   remains constitutional; roster membership and mappings stay changeable.
7. **Consumer independence:** preserved. MCP, RAG, search, IDEs, agents, and
   future compilation tooling remain downstream consumers or projections.
8. **Local operation:** preserved. Mandatory external services and default
   source-data transmission remain forbidden.

## Consequences

The architecture document set is now intentionally layered:

```text
ARCHITECTURE_CONSTITUTION.md
  immutable product identity

ARCHITECTURE_RATIONALE.md
  explanatory reasoning

SPEC.md and CORE.md
  changing requirements and semantic contracts

CONFORMANCE.md
  reviewable and executable checks

docs/adr/
  durable decisions
```

Future reviews should treat the constitution as a ratification candidate only
after asking whether every remaining clause defines `semidx` itself. Detailed
checks should be reviewed in conformance and requirements documents instead.

## Verification

This decision is documentation-only. Runtime conformance is not verified because
there is no semantic-graph implementation yet.

Expected verification for this change is document consistency: links resolve,
frontmatter is valid for new working documents, the constitution remains DRAFT,
the five defined terms remain present, the architectural decision test has
eight questions matching the eight constitutional principles, and no active
current document relies on the removed fourteen-invariant structure.
