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
- Clojure parser path supports `clj-kondo` primary with regex fallback and optional tree-sitter extraction mode.
- Java parser path supports regex mode and optional tree-sitter extraction mode.
- Elixir/Python parser paths are regex-based with class/module-aware symbol and call normalization.
- Retrieval uses structural-first tiered scoring with non-compensating confidence ceilings.
- Raw-code escalation stage is implemented (opt-in, late, bounded by query constraints).
- Semantic resolution includes import-aware and owner-aware call target disambiguation.
- Optional persistence adapters exist: in-memory and PostgreSQL (snapshots + unit/call-edge projections + query API).
- Retrieval benchmark suite exists and is integrated into gates (`scripts/run-benchmarks.sh`).
- Postgres integration smoke exists in tests (enabled by `SCI_TEST_POSTGRES_URL`) and CI service job.

## Hard Invariants

- JSON Schema is the external contract source of truth.
- `malli` is a runtime mirror, not a competing source of truth.
- Outputs must remain bounded and contract-valid (`context_packet`, diagnostics, guardrails, events).
- If limits are exhausted, stop immediately and wait for explicit user instruction.
- Before any service-backed tests (PostgreSQL or other servers): detect running instance -> shutdown if running -> start fresh with required config -> only then run tests.

## Known Gaps

- No deep compiler-grade semantic resolution yet.
- No production API server boundary yet (library-first only).
- Tree-sitter path currently depends on external grammar-path configuration (no bundled grammar management).
- Persistence graph queries are retrieval-oriented and not yet a full semantic graph query language.

## Next Execution Priorities

1. Add reproducible tree-sitter grammar bootstrap workflow (`scripts/setup-tree-sitter-grammars.sh`).
2. Add CI validation for tree-sitter parser path with grammar install in workflow.
3. Expand fixtures/benchmarks for multi-language ambiguity scenarios:
   Python method/function collisions.
   Java overload-like call ambiguity.
4. Design production API boundary as a dedicated phase:
   ADR for boundary and scope.
   Minimal HTTP/gRPC edge over current library-first runtime.
5. Elixir semantic resolution improvements:
   alias/import-aware resolution (`alias Foo.Bar, as: Baz` -> `Baz.fn()` maps to `Foo.Bar/fn`).
6. Elixir extraction quality improvements:
   distinguish `def`, `defp`, `defmacro`, `defdelegate`.
   improve `do/end` unit boundary precision.
7. Add Elixir-specific fixtures:
   ambiguous local vs aliased module calls.
   mixed `def/defp` scenarios.
   ExUnit module scenarios with rank/guardrails expectations.

## Update Rule

Update this file when any of the following changes:

- runtime behavior materially changes
- new invariants are introduced
- priorities or known gaps change
- integration assumptions change
