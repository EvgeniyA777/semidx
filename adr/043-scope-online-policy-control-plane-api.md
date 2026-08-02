---
title: "Scope Online Policy Control-Plane API"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-08-02"
---

# ADR 043: Scope Online Policy Control-Plane API

## Context

Currently, `semidx` relies on offline governance for retrieval policies via server-configured registries and `clojure -M:eval` (or similar offline tooling) for lifecycle management (`draft`, `shadow`, `active`, `retired`). `authz.clj` provides local file/callback authorization. Broader online policy-management APIs have been intentionally absent.
As the operational maturity of the project grows (Stage 6 of the gaps closure program), there is a need for a bounded online policy-management/control-plane API to introspect the registry and safely promote or retire policies without bypassing the authoritative offline governance gates.

## Decision

We will add a bounded online policy control-plane surface with the following constraints:
1. **Introspection**: A read endpoint to list policies in the registry and view their state and governance metadata.
2. **Lifecycle Hooks**: Write endpoints to promote (`active`) and retire (`retired`) policies.
3. **Guardrails**: The online API MUST NOT bypass promotion gates, protected-case checks, or approval tiers (e.g. `manual_approval_required`, `blocked` policies cannot be auto-promoted).
4. **Authorization Boundary**: These endpoints must be protected by the existing `tenant_id`-based authorization (`authz.clj`). The control-plane endpoints will require specific `operation` authz checks (e.g., `policy_read`, `policy_promote`, `policy_retire`).
5. **Contract First**: The requests and responses will be defined via JSON Schema and mirrored in `malli`.

The endpoints will be exposed over the runtime HTTP edge (and mirrored on gRPC/MCP where applicable). They will reuse the existing unified error taxonomy (`invalid_request`, `forbidden`, `internal_error`).

## Consequences

- **Positive**: Operators can introspect active/shadow policies and execute safe promotions/retirements without needing direct filesystem access to the registry.
- **Negative**: Adds a new mutable surface to the runtime edges which requires careful authorization and audit logging.
- **Constraints**: Offline governance remains authoritative. The online API is strictly a control plane for state transitions within the rules defined offline.
