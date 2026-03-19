# ADR-027: Add Lua as a Separate Semantic Search Language

## Status

Accepted

## Date

2026-03-18

## Context

`ADR-004` defines parser adapters as capability-based fact extractors.  
`ADR-014` governs retrieval fixtures and benchmarks.  
`ADR-022` defines the standard onboarding flow for new language adapters.  
`ADR-026` established the recent pattern for promoting a language family into its own public lane instead of hiding it behind another existing lane.

The runtime already exposes language activation and onboarding through the public metadata surface:

- `supported_languages`
- `detected_languages`
- `active_languages`
- `language_policy`

Lua is a common source language for embedded runtimes, plugins, game tooling, and automation-heavy repositories. It is not well served by pretending it is another existing lane, and it should not be added only as an internal parser alias. If we want Lua semantic search support to stay explainable, we need to decide whether it is:

- a separate public language lane with its own activation metadata, docs, fixtures, and onboarding surface, or
- an undocumented parsing capability that does not appear honestly in runtime metadata.

This ADR chooses the first option.

## Decision

We add `lua` as a separate public language lane for semantic search.

The first implementation slice is intentionally `regex-first`. Lua support must ship as a bounded, explainable adapter lane before any optional `tree-sitter` deepening work is considered.

### Public contract changes

- Add `lua` to the supported language set.
- Map `.lua` files to the `lua` language key during discovery and activation.
- Expose Lua through activation metadata, retrieval metadata, and onboarding docs.
- Keep Lua visible as `lua`; do not alias it to another lane.

### Parser and activation changes

- Add a dedicated `runtime/languages/lua` entry namespace.
- Implement a regex-based Lua adapter that emits the canonical parsed-file shape:
  - `:language`
  - `:module`
  - `:imports`
  - `:units`
  - `:diagnostics`
  - `:parser_mode`
- Support the common v1 Lua surfaces:
  - `require("...")` import extraction
  - top-level function definitions
  - module-table function definitions
  - module-table method syntax
  - normalized call extraction for dot and colon calls
- Preserve bounded fallback behavior: Lua parsing failures must not crash indexing.

### Deliberate v1 limits

- Regex parsing is the only required Lua parsing mode in this slice.
- No Lua-specific parser option is added in v1.
- No Lua `tree-sitter` grammar path or engine selection is required in v1.
- Luau-specific syntax, metatable modeling, and dynamic `require` resolution remain out of scope.

### Onboarding and governance changes

- Add Lua onboarding coverage following `ADR-022`.
- Add Lua happy-path and ambiguity fixtures.
- Register Lua fixtures in the retrieval corpus used by benchmark governance.
- Add Lua onboarding tests and wire them into the standard test runner.
- Add Lua onboarding documentation under `docs/language-onboarding/`.
- Keep `scripts/validate-language-onboarding.sh lua` green as the structural onboarding check.

## Decision Drivers

- Lua should appear honestly in the public supported-language model.
- A regex-first lane keeps the initial implementation bounded and explainable.
- The runtime already has a stable multi-language activation surface that can absorb one more lane cleanly.
- Fixture and benchmark governance should cover Lua from the first accepted slice rather than as a later cleanup.

## Considered Options

### Option 1. Add Lua as a separate public language lane

Expose `lua` as a first-class language key with its own discovery, activation, docs, fixtures, and onboarding flow.

### Option 2. Parse Lua internally without a public lane

Allow internal parser support but do not expose `lua` in activation or public docs.

### Option 3. Delay Lua until tree-sitter is ready

Treat parser deepening as a prerequisite for any Lua support.

## Decision

We accept **Option 1: add Lua as a separate public language lane**.

We explicitly reject waiting for tree-sitter as the gate for initial support. The repo already accepts regex-first lanes when they stay bounded, documented, and benchmark-governed.

## Consequences

### Positive

- Lua repositories can be indexed and explained as Lua.
- The supported-language surface remains honest and user-facing metadata becomes easier to interpret.
- The implementation stays small enough to land quickly while preserving explainability.
- Lua joins the existing fixture and benchmark governance loop instead of becoming an undocumented side path.

### Negative

- The supported-language matrix grows again.
- Regex parsing will leave some deeper Lua semantics out of scope in v1.
- A later tree-sitter tranche will need a follow-up ADR or implementation note if parser depth is expanded materially.

## Definition of Done

This ADR is implemented correctly when all of the following are true:

1. `lua` appears in the supported-language set and activation metadata.
2. `.lua` files are discovered and indexed as `lua`.
3. The runtime exposes a dedicated Lua lane with bounded regex parsing.
4. Lua has its own onboarding doc, fixtures, corpus entries, and onboarding regression test.
5. Lua onboarding validation, tests, and benchmark/mvp gates pass.

## Alternatives Considered

1. **Hide Lua behind another lane**: rejected because it would make activation metadata misleading.
2. **Ship parser support without governance artifacts**: rejected because it would violate `ADR-022` and weaken change review.
3. **Wait for tree-sitter parity first**: rejected because the current adapter model already supports a bounded regex-first rollout.
