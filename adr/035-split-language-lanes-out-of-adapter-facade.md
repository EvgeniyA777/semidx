---
file_type: adr
decision_id: ADR-035
title: Split Language Lanes Out Of The Adapter Facade
status: accepted
date: 2026-07-20
deciders:
  - project owner
tags:
  - architecture
  - language-lanes
  - parser-boundary
summary: Language-specific parser and semantic extraction logic now lives in dedicated runtime language lane namespaces, while semidx.runtime.adapters remains only the stable public dispatch facade.
agent_summary: Read this ADR before adding or changing parser lanes. The decision of record is that language-specific extraction belongs in semidx.runtime.languages.* namespaces; semidx.runtime.adapters must stay a thin public facade and must not accumulate legacy parser fallbacks or duplicate lane logic.
supersedes: []
superseded_by: null
links:
  - plans/013_open_gaps_closure_program.md
  - reports/014_open_gaps_closure_program_progress_log.md
---

# ADR-035: Split Language Lanes Out Of The Adapter Facade

**Status**: Accepted  
**Date**: 2026-07-20  
**Deciders**: project owner

---

## Context

`semidx.runtime.adapters` started as both the public parser facade and the
implementation home for multiple language lanes. That made the namespace a
large change hotspot: Clojure, Java, Python, Lua, and remaining TypeScript
compatibility code all lived beside cross-language dispatch, fallback handling,
and semantic IR finalization.

This shape made every deeper semantic tranche more expensive. Shared scanning
and tree-sitter helpers were hard to isolate, language-specific parser changes
risked unrelated dispatcher churn, and old compatibility facades could survive
after no external caller needed them.

Stage 1 of `plans/013_open_gaps_closure_program.md` moved the parser lanes into
dedicated namespaces and removed the remaining legacy adapter-level TypeScript
block.

## Decision Drivers

- Keep the public parser entry point stable for existing callers.
- Make language-specific parser ownership explicit and local to each lane.
- Remove duplicate or legacy parser paths when the product is not bound to
  backward-compatible internals.
- Keep shared helper code reusable without coupling it to any one lane.
- Reduce blast radius before the next semantic and tree-sitter dependency
  tranches.

## Considered Options

### Option 1. Keep adapters as the implementation hub

Continue to host most language parser internals in `semidx.runtime.adapters`
and add more helpers around the existing structure.

### Option 2. Extract helper utilities only

Move generic line, token, and tree-sitter utilities to a shared namespace while
leaving each language's parser implementation in `semidx.runtime.adapters`.

### Option 3. Dedicated language lanes plus a thin adapter facade

Move language-specific parser and semantic extraction logic into
`semidx.runtime.languages.*` namespaces, keep `semidx.runtime.adapters` as the
stable public facade, and remove legacy adapter wrappers and fallback blocks
when their callers can use the lane namespace directly.

## Decision

We accept Option 3: dedicated language lanes plus a thin adapter facade.

After this decision:

- `semidx.runtime.adapters/parse-file` remains the canonical public parser
  facade.
- Language selection stays registry-driven through
  `semidx.runtime.language-registry`.
- Clojure, Java, Python, Lua, TypeScript, and JavaScript parsing dispatches
  directly to their dedicated lane namespaces.
- Generic line/signature/token and tree-sitter CLI/config/CST helpers live in
  `semidx.runtime.languages.shared`.
- Adapter-level legacy facades such as `parse-clojure-file`,
  `parse-java-file`, `parse-python-file`, `parse-lua-file`,
  `parse-typescript-legacy`, and duplicate TypeScript regex/tree-sitter parser
  blocks are not retained.

Option 1 loses because it preserves the hotspot and makes future semantic work
pay unrelated adapter complexity. Option 2 helps reuse but leaves the ownership
problem unresolved. Option 3 keeps the external facade stable while making the
internal boundary match the product architecture.

## Consequences

### Positive

- Future language-lane changes are scoped to the owning namespace and focused
  tests.
- `semidx.runtime.adapters` is easier to reason about: dispatch, fallback, and
  finalization are visible without paging through language-specific parsers.
- Legacy parser code has a clear deletion rule: if the lane owns the behavior
  and no public caller needs the adapter-private wrapper, the wrapper is
  removed.
- Stage 2 tree-sitter work can target shared helpers and lane modules directly
  instead of disentangling adapter-local parser code first.

### Negative

- Parser behavior is now distributed across more namespaces, so broad parser
  audits need the repository map or language-lane documentation rather than one
  large file.
- Shared helpers must stay generic. Pulling lane-specific policy back into
  `semidx.runtime.languages.shared` would recreate coupling under a different
  name.
- Tests that intentionally monkeypatch parser lanes must target the lane
  namespace, not old adapter-private facades.

### Follow-Up

- Stage 2 of `plans/013` should remove the hard runtime dependency on an
  externally installed tree-sitter CLI through the shared helper boundary and
  per-lane parser modes.
- New language onboarding should follow the lane namespace pattern and avoid
  placing parser internals in `semidx.runtime.adapters`.

## Status Changes

None.

## References

- `plans/013_open_gaps_closure_program.md` - Stage 1
- `reports/014_open_gaps_closure_program_progress_log.md` - Stage 1.1 through
  Stage 1.6 implementation and verification record
- `src/semidx/runtime/adapters.clj` - public parser facade
- `src/semidx/runtime/languages/shared.clj` - shared lane helpers

## Definition Of Done

`semidx.runtime.adapters` dispatches supported languages directly to
`semidx.runtime.languages.*` lane namespaces; no adapter-private legacy parser
facades or duplicate TypeScript parser blocks remain; `MEMORY.md`,
`docs/roadmap-status.md`, CCC artifacts, and the Stage 1 progress log describe
the same boundary; full tests, retrieval benchmarks, semantic quality reporting,
MVP gates, and CCC checks pass after the split.
