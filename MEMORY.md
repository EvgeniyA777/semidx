# Project Memory

## Purpose

This file stores lightweight operational memory for the project:

- current implementation reality
- key non-ADR decisions
- active assumptions and constraints
- near-term next steps

Use this as a fast session bootstrap before deep-diving into ADRs and code.

## Current State

- Contract layer is established (`contracts/schemas`, `contracts/examples`, `fixtures/retrieval`).
- Clojure-side contract mirror is implemented with `malli`.
- MVP runtime is implemented with public API in `semantic-code-indexing.core`.
- Clojure parser path is `clj-kondo` primary with regex fallback.
- Java parser path is lightweight regex-based in MVP.
- Retrieval uses structural-first tiered scoring with non-compensating confidence ceilings.
- Optional snapshot persistence adapters exist: in-memory and PostgreSQL.

## Hard Invariants

- JSON Schema is the external contract source of truth.
- `malli` is a runtime mirror, not a competing source of truth.
- Outputs must remain bounded and contract-valid (`context_packet`, diagnostics, guardrails, events).
- If limits are exhausted, stop immediately and wait for explicit user instruction.

## Known Gaps

- No deep compiler-grade semantic resolution yet.
- No tree-sitter-enabled path in runtime yet (only optional slot exists).
- No production API server boundary yet (library-first only).
- Postgres adapter is implemented, but DB-backed integration smoke is not yet part of tests.

## Next Execution Priorities

1. Add PostgreSQL integration smoke in CI (conditional or service-backed).
2. Introduce optional tree-sitter path for Java/Clojure structural extraction.
3. Expand fixture corpus for ambiguous targets and stale/degraded scenarios.
4. Add retrieval benchmark suite aligned with ADR-014 categories.

## Update Rule

Update this file when any of the following changes:

- runtime behavior materially changes
- new invariants are introduced
- priorities or known gaps change
- integration assumptions change
