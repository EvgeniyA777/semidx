# ADR-022: Define Standard Onboarding Flow for New Language Adapters

**Status**: Accepted  
**Date**: 2026-03-08  
**Deciders**: project owner

---

## Context and Problem Statement

The runtime already supports multiple languages (`Clojure`, `Java`, `Elixir`, `Python`) via parser adapters.

As language coverage expands, ad-hoc onboarding risks:

- inconsistent parser outputs across languages
- missing benchmark/fixture coverage for ambiguity cases
- undocumented integration behavior for parser options and fallback

We need one repeatable contract for adding a new language safely.

---

## Decision

A new language must be integrated through a standard 8-step onboarding flow.

1. **Register file extensions** in `runtime.adapters/language-by-path`.
2. **Implement parser adapter** with canonical output shape:
   - `:language`, `:module`, `:imports`, `:units`, `:diagnostics`, `:parser_mode`
3. **Wire parser in dispatch** (`parse-file` case branch).
4. **Preserve fallback behavior**:
   - parser failures must degrade to bounded fallback output, never crash indexing
5. **Add functional tests** in `runtime_test`:
   - indexing presence
   - symbol targeting
   - call/link behavior relevant to that language
6. **Add retrieval fixtures and benchmark entries**:
   - at least one happy-path fixture
   - at least one ambiguity/edge-case fixture
7. **Document support surface** in runtime docs and README.
8. **Pass quality gates**:
   - `clojure -M:test`
   - `./scripts/run-benchmarks.sh`
   - `./scripts/run-mvp-gates.sh`

---

## Invariants for New Language Adapters

- must emit stable `unit_id` values suitable for storage/query APIs
- must keep `:calls` extraction explainable (no hidden heuristics without diagnostics)
- must not violate contract-bounded runtime outputs
- must keep cross-language parity with existing retrieval/guardrail behavior

---

## Consequences

### Positive

- predictable language onboarding with lower regression risk
- consistent adapter contracts across all languages
- stronger benchmark governance as language matrix grows

### Tradeoff

- adding a language now requires fixture + benchmark work, not only parser code
- initial onboarding takes longer but reduces long-term maintenance cost

---

## Follow-ups

- add a lightweight language-onboarding checklist template under `docs/`
- define minimum fixture categories per language (`symbol_target`, `ambiguity`, `fallback`)
